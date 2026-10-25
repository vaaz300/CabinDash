import Foundation

public enum Units: String, Codable, CaseIterable, Hashable, Sendable {
    case kmh
    case mph

    public var speedLabel: String { self == .mph ? "mph" : "km/h" }
    public var distanceLabel: String { self == .mph ? "mi" : "km" }
    /// The speed at which the gauge is full.
    public var gaugeMax: Double { self == .mph ? 120 : 200 }

    public func speed(fromMetersPerSecond ms: Double) -> Double {
        self == .mph ? ms * 2.236936 : ms * 3.6
    }

    public func distance(fromMeters meters: Double) -> Double {
        self == .mph ? meters / 1609.344 : meters / 1000
    }

    /// mph in the places that drive in miles per hour, km/h everywhere else.
    public static func preferred(forRegion region: String?) -> Units {
        ["US", "GB", "LR", "MM"].contains((region ?? "").uppercased()) ? .mph : .kmh
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Units(rawValue: raw) ?? .kmh
    }
}

public enum Geo {
    private static let earthRadius = 6_371_000.0

    /// Great-circle distance in metres.
    public static func distance(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let k = Double.pi / 180
        let dLat = (bLat - aLat) * k
        let dLon = (bLon - aLon) * k
        let s = sin(dLat / 2) * sin(dLat / 2) + cos(aLat * k) * cos(bLat * k) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, s.squareRoot()))
    }
}

public enum Compass {
    private static let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    public static func cardinal(_ degrees: Double) -> String {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return names[Int((positive / 45).rounded()) % 8]
    }

    /// The next angle, expressed so the needle turns the short way: 350 then 10 gives 370, not 10.
    public static func unwrap(previous: Double, next: Double) -> Double {
        var delta = (next - previous).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return previous + delta
    }

    public static func degreesText(_ degrees: Double) -> String {
        let whole = Int(degrees.rounded()) % 360
        let positive = whole < 0 ? whole + 360 : whole
        return String(format: "%03d", positive) + "\u{00B0}"
    }
}

public enum DriveFormat {
    /// 0...1, how full the speed gauge is.
    public static func gaugeFraction(speed: Double, units: Units) -> Double {
        max(0, min(1, speed / units.gaugeMax))
    }

    public static func distance(meters: Double, units: Units) -> String {
        let value = units.distance(fromMeters: meters)
        return value < 100 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    public static func duration(seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// One reading from the location hardware, with invalid values already turned into nil.
public struct Fix: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// Seconds, on any clock that only moves forward.
    public var time: Double
    /// Metres per second, or nil when the phone has no speed.
    public var speed: Double?
    /// Degrees from true north, or nil when the phone has no course.
    public var course: Double?
    /// Metres.
    public var accuracy: Double

    public init(latitude: Double, longitude: Double, time: Double, speed: Double?, course: Double?, accuracy: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.time = time
        self.speed = speed
        self.course = course
        self.accuracy = accuracy
    }
}

/// Adds up distance and driving time from a stream of fixes, ignoring jumps, poor readings and standing still.
public struct TripTracker: Codable, Equatable, Sendable {
    public private(set) var meters: Double
    public private(set) var seconds: Double
    private var last: Fix?

    private enum CodingKeys: String, CodingKey { case meters, seconds }

    public init(meters: Double = 0, seconds: Double = 0) {
        self.meters = meters
        self.seconds = seconds
        self.last = nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            meters: try c.decodeIfPresent(Double.self, forKey: .meters) ?? 0,
            seconds: try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        )
    }

    /// Returns the best speed estimate for this fix, in metres per second.
    @discardableResult
    public mutating func ingest(_ fix: Fix) -> Double {
        var speed = fix.speed
        if let previous = last {
            let dt = fix.time - previous.time
            let d = Geo.distance(previous.latitude, previous.longitude, fix.latitude, fix.longitude)
            if speed == nil, dt > 0, dt < 10, fix.accuracy < 50 { speed = d / dt }
            if dt > 0, dt < 15, fix.accuracy < 40, d < dt * 70, (speed ?? 0) > 1 {
                meters += d
                seconds += dt
            }
        }
        last = fix
        return speed ?? 0
    }

    public var averageSpeed: Double? { seconds > 5 ? meters / seconds : nil }

    public mutating func reset() {
        meters = 0
        seconds = 0
        last = nil
    }

    /// Forget the previous fix, e.g. after location was off for a while, so the gap is not counted as driving.
    public mutating func breakContinuity() { last = nil }
}
