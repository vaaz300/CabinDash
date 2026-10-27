import Foundation

/// Decides whether the car is moving fast enough that typing should be switched off.
///
/// It engages at 8 km/h and lets go only after the speed has stayed under 4 km/h for ten seconds, so a red light or a
/// queue does not unlock the screen for a moment and then lock it again. No usable speed (no GPS) changes nothing:
/// a lock that was on stays on, and one that was off stays off.
public struct DrivingLock: Equatable, Sendable {
    /// 8 km/h in metres per second.
    public static let engageSpeed = 8.0 / 3.6
    /// 4 km/h in metres per second.
    public static let releaseSpeed = 4.0 / 3.6
    /// How long the speed must stay under `releaseSpeed` before the lock lets go, in seconds.
    public static let releaseHold = 10.0

    public private(set) var isMoving = false
    /// When the speed first dropped under `releaseSpeed` in the current slow stretch.
    private var slowSince: Double?

    public init() {}

    /// Feeds in one speed reading. `time` is any steadily increasing clock in seconds.
    /// A reading that cannot be right (missing, negative, not a number) is treated as no reading at all.
    public mutating func update(speed: Double?, at time: Double) {
        guard let speed, speed.isFinite, speed >= 0 else { return }

        if speed >= Self.engageSpeed {
            isMoving = true
            slowSince = nil
            return
        }
        // From rest, speeds under the engage speed do nothing.
        guard isMoving else { return }

        if speed >= Self.releaseSpeed {
            slowSince = nil // still creeping along, so the stop starts over
            return
        }
        guard let since = slowSince else {
            slowSince = time
            return
        }
        if time - since >= Self.releaseHold {
            isMoving = false
            slowSince = nil
        }
    }

    /// Typing is off while moving, unless someone else is using the screen.
    public func isTypingLocked(passengerMode: Bool) -> Bool {
        isMoving && !passengerMode
    }
}
