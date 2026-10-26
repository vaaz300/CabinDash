import Foundation

/// One instruction of a route, reduced to what the guidance card needs.
public struct RouteStep: Equatable, Sendable {
    public var instruction: String
    /// Length of the step, in metres.
    public var meters: Double
    /// Where the step ends, which is where its instruction applies.
    public var endLatitude: Double
    public var endLongitude: Double

    public init(instruction: String, meters: Double, endLatitude: Double, endLongitude: Double) {
        self.instruction = instruction
        self.meters = meters
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
    }
}

public enum RouteGuide {
    /// Within this many metres of a step's end, the step counts as done.
    public static let reachedRadius = 45.0

    /// The step the driver is on. It only moves forward: once a step end has been passed, going near it again changes nothing.
    public static func currentStep(steps: [RouteStep], from index: Int, latitude: Double, longitude: Double) -> Int {
        guard !steps.isEmpty else { return 0 }
        var current = min(max(index, 0), steps.count - 1)
        while current < steps.count - 1 {
            let step = steps[current]
            let distance = Geo.distance(latitude, longitude, step.endLatitude, step.endLongitude)
            if distance > reachedRadius { break }
            current += 1
        }
        return current
    }

    /// Straight-line metres to the end of the current step. Not road distance, so it reads a little short on bends.
    public static func metersToStepEnd(steps: [RouteStep], index: Int, latitude: Double, longitude: Double) -> Double? {
        guard steps.indices.contains(index) else { return nil }
        let step = steps[index]
        return Geo.distance(latitude, longitude, step.endLatitude, step.endLongitude)
    }

    /// True when the last step's end is within the reached radius.
    public static func hasArrived(steps: [RouteStep], latitude: Double, longitude: Double) -> Bool {
        guard let last = steps.last else { return false }
        return Geo.distance(latitude, longitude, last.endLatitude, last.endLongitude) <= reachedRadius
    }

    /// Road metres still to go: the rest of the route after the current step, plus the straight line to the current step's end.
    public static func remainingMeters(steps: [RouteStep], index: Int, latitude: Double, longitude: Double) -> Double {
        guard steps.indices.contains(index) else { return 0 }
        let toEnd = metersToStepEnd(steps: steps, index: index, latitude: latitude, longitude: longitude) ?? 0
        let after = steps[(index + 1)...].reduce(0) { $0 + $1.meters }
        return toEnd + after
    }
}

public enum RouteFormat {
    /// "7 min", "1 h", "1 h 25 min". Never shows 0 minutes.
    public static func travelTime(seconds: Double) -> String {
        let minutes = max(1, Int((max(0, seconds) / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Distance to the next turn: short and rounded the way a driver reads it.
    /// Metric: "40 m", "450 m", "1.2 km", "12 km". Imperial: "350 ft", "0.2 mi", "12 mi".
    public static func maneuverDistance(meters: Double, units: Units) -> String {
        let value = max(0, meters)
        switch units {
        case .kmh:
            if value < 100 { return "\(max(10, Int((value / 10).rounded()) * 10)) m" }
            if value < 1000 { return "\(Int((value / 50).rounded()) * 50) m" }
            let km = value / 1000
            return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
        case .mph:
            let feet = value * 3.28084
            if feet < 500 { return "\(max(50, Int((feet / 50).rounded()) * 50)) ft" }
            let miles = value / 1609.344
            return miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
        }
    }

    /// An SF Symbol for the next manoeuvre, picked from the English wording of Apple's instruction.
    /// In other languages it falls back to a straight arrow: wrong for a turn, but the distance beside it stays right.
    public static func maneuverSymbol(_ instruction: String) -> String {
        let text = instruction.lowercased()
        if text.contains("arrive") || text.contains("destination") { return "flag.checkered" }
        if text.contains("u-turn") { return text.contains("right") ? "arrow.uturn.right" : "arrow.uturn.left" }
        if text.contains("roundabout") || text.contains("traffic circle") { return "arrow.triangle.turn.up.right.circle" }
        if text.contains("merge") { return "arrow.triangle.merge" }
        let left = text.contains("left")
        let right = text.contains("right")
        let gentle = text.contains("slight") || text.contains("bear") || text.contains("keep") || text.contains("exit")
        if left && !right { return gentle ? "arrow.up.left" : "arrow.turn.up.left" }
        if right && !left { return gentle ? "arrow.up.right" : "arrow.turn.up.right" }
        return "arrow.up"
    }

    /// Whole trip distance, with the unit: "8.4 km", "12 mi".
    public static func tripDistance(meters: Double, units: Units) -> String {
        let value = units.distance(fromMeters: max(0, meters))
        let number = value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
        return number + " " + units.distanceLabel
    }
}
