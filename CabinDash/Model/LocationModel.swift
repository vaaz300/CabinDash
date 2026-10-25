import CabinCore
import CoreLocation
import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "app.cabindash", category: "location")

/// Forwards Core Location callbacks to the main actor. Kept apart from the observable model because
/// delegates must be NSObject subclasses.
final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocations: (@MainActor ([CLLocation]) -> Void)?
    var onAuthorization: (@MainActor (CLAuthorizationStatus) -> Void)?

    // The manager is created on the main thread, so Core Location calls these on the main thread.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            if let handler = onLocations { handler(locations) }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            if let handler = onAuthorization { handler(status) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.info("Location error: \(error.localizedDescription, privacy: .public)")
    }
}

/// Live speed, heading and trip totals from the iPhone's GPS.
@MainActor @Observable
final class LocationModel {
    enum Access: Equatable {
        case unknown
        case denied
        case allowed
    }

    private(set) var access: Access = .unknown
    /// Metres per second, 0 when standing still or when the signal is lost.
    private(set) var speed: Double = 0
    /// Degrees. Keeps counting past 360 so the needle always turns the short way.
    private(set) var heading: Double = 0
    private(set) var hasHeading = false
    private(set) var hasFix = false
    private(set) var trip: TripTracker

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let delegate = LocationDelegate()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var wantsUpdates = false
    @ObservationIgnored private var updating = false
    @ObservationIgnored private var lastFixAt: Date?
    @ObservationIgnored private var lastSaveAt = Date.distantPast
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    private static let tripKey = "cabin-dash.trip.v1"
    /// Below this speed the car counts as stopped, which hides GPS jitter.
    private static let movingThreshold = 0.6
    /// The course is only meaningful when moving.
    private static let courseThreshold = 1.5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.tripKey),
           let saved = try? JSONDecoder().decode(TripTracker.self, from: data) {
            trip = saved
        } else {
            trip = TripTracker()
        }
        manager.delegate = delegate
        delegate.onLocations = { [weak self] locations in self?.handle(locations) }
        delegate.onAuthorization = { [weak self] status in self?.apply(status) }
    }

    // MARK: Control

    func start() {
        wantsUpdates = true
        apply(manager.authorizationStatus)
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        wantsUpdates = false
        endUpdates()
        saveTrip()
    }

    /// Returns the trip as it was, so the caller can offer Undo.
    @discardableResult
    func resetTrip() -> TripTracker {
        let previous = trip
        trip.reset()
        saveTrip()
        return previous
    }

    func restoreTrip(_ previous: TripTracker) {
        trip = previous
        trip.breakContinuity()
        saveTrip()
    }

    func saveTrip() {
        lastSaveAt = Date()
        guard let data = try? JSONEncoder().encode(trip) else { return }
        defaults.set(data, forKey: Self.tripKey)
    }

    // MARK: Updates

    private func apply(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            access = .unknown
        case .restricted, .denied:
            access = .denied
            endUpdates()
        case .authorizedWhenInUse, .authorizedAlways:
            access = .allowed
            if wantsUpdates { beginUpdates() }
        @unknown default:
            access = .unknown
        }
    }

    private func beginUpdates() {
        guard !updating else { return }
        updating = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        trip.breakContinuity()
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.dropStaleFix()
            }
        }
    }

    private func endUpdates() {
        guard updating else { return }
        updating = false
        manager.stopUpdatingLocation()
        watchdog?.cancel()
        watchdog = nil
        speed = 0
        hasFix = false
        lastFixAt = nil
        trip.breakContinuity()
    }

    private func handle(_ locations: [CLLocation]) {
        for location in locations {
            // A negative accuracy means the coordinate is invalid. Old fixes can be replayed when updates start.
            guard location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 15 else { continue }

            let fix = Fix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                time: location.timestamp.timeIntervalSinceReferenceDate,
                speed: location.speed >= 0 ? location.speed : nil,
                course: location.course >= 0 ? location.course : nil,
                accuracy: location.horizontalAccuracy
            )
            let estimate = trip.ingest(fix)
            speed = estimate < Self.movingThreshold ? 0 : estimate
            hasFix = true
            lastFixAt = Date()

            if let course = fix.course, estimate >= Self.courseThreshold {
                heading = hasHeading ? Compass.unwrap(previous: heading, next: course) : course
                hasHeading = true
            }
        }
        if Date().timeIntervalSince(lastSaveAt) > 15 { saveTrip() }
    }

    /// With no fix for a few seconds the car is in a tunnel or the signal dropped; showing the last speed would be wrong.
    private func dropStaleFix() {
        guard let last = lastFixAt, Date().timeIntervalSince(last) > 5 else { return }
        speed = 0
        hasFix = false
        trip.breakContinuity()
    }
}
