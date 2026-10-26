import CabinCore
import CoreLocation
import MapKit
import Observation
import OSLog

private let log = Logger(subsystem: "app.cabindash", category: "route")

/// One driving route from where the iPhone is to a chosen place, and how far along it the car is.
///
/// The route and its instructions come from Apple Maps (MapKit). Progress is worked out from the GPS fix:
/// the card moves on to the next instruction once the car is near the place the last one applied.
/// There is no automatic rerouting. If the car leaves the route, the Reroute button asks for a new one.
@MainActor @Observable
final class RouteModel {
    enum Phase: Equatable {
        case idle
        case loading
        case preview
        case guiding
        case arrived
    }

    private(set) var phase: Phase = .idle
    private(set) var destination: MKMapItem?
    private(set) var route: MKRoute?
    private(set) var steps: [RouteStep] = []
    private(set) var stepIndex = 0
    /// Why the last attempt failed, in words for the driver. Cleared by the next attempt.
    private(set) var problem: String?

    private(set) var lastLatitude: Double?
    private(set) var lastLongitude: Double?

    /// Bumped by every new request, so an answer that arrives late for an old request is ignored.
    @ObservationIgnored private var generation = 0

    // MARK: What the screens read

    var destinationName: String {
        destination?.name ?? "Destination"
    }

    var currentStep: RouteStep? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    /// Straight-line metres to where the current instruction applies.
    var metersToNext: Double? {
        guard let latitude = lastLatitude, let longitude = lastLongitude else { return currentStep?.meters }
        return RouteGuide.metersToStepEnd(steps: steps, index: stepIndex, latitude: latitude, longitude: longitude)
    }

    var remainingMeters: Double {
        guard let route else { return 0 }
        guard phase == .guiding, let latitude = lastLatitude, let longitude = lastLongitude else { return route.distance }
        return RouteGuide.remainingMeters(steps: steps, index: stepIndex, latitude: latitude, longitude: longitude)
    }

    var remainingSeconds: Double {
        guard let route, route.distance > 0 else { return 0 }
        return route.expectedTravelTime * min(1, remainingMeters / route.distance)
    }

    // MARK: Planning

    /// Plans a driving route from the current location to `item`.
    func plan(to item: MKMapItem, startImmediately: Bool = false) async {
        generation += 1
        let mine = generation
        destination = item
        route = nil
        steps = []
        stepIndex = 0
        problem = nil
        phase = .loading

        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = item
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard mine == generation else { return }
            guard let best = response.routes.first else {
                fail("No driving route found.")
                return
            }
            let guideSteps = Self.guideSteps(for: best, destinationName: item.name ?? "your destination")
            guard !guideSteps.isEmpty else {
                fail("Couldn't read the directions for this route.")
                return
            }
            route = best
            steps = guideSteps
            stepIndex = 0
            phase = startImmediately ? .guiding : .preview
            if startImmediately { catchUp() }
        } catch {
            guard mine == generation, !(error is CancellationError) else { return }
            log.info("Directions failed: \(error.localizedDescription, privacy: .public)")
            fail(Self.message(for: error))
        }
    }

    /// Looks the address up with Apple Maps, then plans a route to the best match.
    func plan(toAddress address: String, name: String, near center: CLLocationCoordinate2D?) async {
        generation += 1
        let mine = generation
        destination = nil
        route = nil
        steps = []
        problem = nil
        phase = .loading

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard mine == generation else { return }
            guard let item = response.mapItems.first else {
                fail("Couldn't find \(name) on the map.")
                return
            }
            item.name = name
            await plan(to: item)
        } catch {
            guard mine == generation, !(error is CancellationError) else { return }
            log.info("Address search failed: \(error.localizedDescription, privacy: .public)")
            fail(Self.message(for: error))
        }
    }

    /// Asks for a fresh route from where the car is now, and goes straight to guidance.
    func reroute() async {
        guard let destination else { return }
        await plan(to: destination, startImmediately: true)
    }

    // MARK: Guidance

    func start() {
        guard phase == .preview, !steps.isEmpty else { return }
        stepIndex = 0
        phase = .guiding
        catchUp()
    }

    func clear() {
        generation += 1
        phase = .idle
        destination = nil
        route = nil
        steps = []
        stepIndex = 0
        problem = nil
    }

    func dismissProblem() {
        problem = nil
    }

    /// Called with every GPS fix.
    func update(latitude: Double, longitude: Double) {
        lastLatitude = latitude
        lastLongitude = longitude
        guard phase == .guiding else { return }
        catchUp()
    }

    private func catchUp() {
        guard let latitude = lastLatitude, let longitude = lastLongitude, !steps.isEmpty else { return }
        if RouteGuide.hasArrived(steps: steps, latitude: latitude, longitude: longitude) {
            stepIndex = steps.count - 1
            phase = .arrived
            return
        }
        stepIndex = RouteGuide.currentStep(steps: steps, from: stepIndex, latitude: latitude, longitude: longitude)
    }

    private func fail(_ message: String) {
        phase = .idle
        destination = nil
        route = nil
        steps = []
        stepIndex = 0
        problem = message
    }

    // MARK: Turning a MapKit route into guidance steps

    /// MapKit's instruction for a step describes the manoeuvre at the START of that step, so the card for
    /// "turn left onto Main Street" has to count down to where the previous step ends.
    /// Each guide step is therefore: this instruction, the road distance driven since the last one, and the place it applies.
    static func guideSteps(for route: MKRoute, destinationName: String) -> [RouteStep] {
        let all = route.steps
        var result: [RouteStep] = []
        var leg = 0.0
        for (index, step) in all.enumerated() {
            if index > 0, !step.instructions.isEmpty, let point = endCoordinate(of: all[index - 1]) {
                result.append(RouteStep(
                    instruction: step.instructions, meters: leg,
                    endLatitude: point.latitude, endLongitude: point.longitude
                ))
                leg = 0
            }
            leg += step.distance
        }
        guard let last = all.last, let finish = endCoordinate(of: last) else { return result }
        // MapKit often ends with its own "destination is on your left" step. Do not add a second arrival next to it.
        if let previous = result.last,
           Geo.distance(previous.endLatitude, previous.endLongitude, finish.latitude, finish.longitude) < 30 {
            return result
        }
        result.append(RouteStep(
            instruction: "Arrive at \(destinationName)", meters: leg,
            endLatitude: finish.latitude, endLongitude: finish.longitude
        ))
        return result
    }

    private static func endCoordinate(of step: MKRoute.Step) -> CLLocationCoordinate2D? {
        let count = step.polyline.pointCount
        guard count > 0 else { return nil }
        var coordinate = CLLocationCoordinate2D()
        step.polyline.getCoordinates(&coordinate, range: NSRange(location: count - 1, length: 1))
        return coordinate
    }

    private static func message(for error: Error) -> String {
        if let mapError = error as? MKError {
            switch mapError.code {
            case .directionsNotFound: return "No driving route to there."
            case .placemarkNotFound: return "Couldn't find that place."
            case .loadingThrottled: return "Maps is busy. Try again in a minute."
            default: break
            }
        }
        if error is URLError { return "Couldn't get directions. Check the connection." }
        return "Couldn't get directions."
    }
}
