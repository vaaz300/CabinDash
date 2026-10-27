import Foundation
import Testing
@testable import CabinCore

@Suite struct DrivingLockTests {
    /// A driver cruising well above the engage speed, in metres per second.
    private let cruising = 14.0

    private func engaged() -> DrivingLock {
        var lock = DrivingLock()
        lock.update(speed: cruising, at: 0)
        return lock
    }

    @Test func thresholdsAreEightAndFourKilometresAnHour() {
        #expect(abs(DrivingLock.engageSpeed - 8.0 / 3.6) < 1e-9)
        #expect(abs(DrivingLock.releaseSpeed - 4.0 / 3.6) < 1e-9)
        #expect(DrivingLock.releaseHold == 10)
    }

    @Test func startsUnlocked() {
        let lock = DrivingLock()
        #expect(!lock.isMoving)
        #expect(!lock.isTypingLocked(passengerMode: false))
    }

    @Test func engagesAtEightKmh() {
        var lock = DrivingLock()
        lock.update(speed: DrivingLock.engageSpeed, at: 0)
        #expect(lock.isMoving)
    }

    @Test func doesNotEngageBelowEightFromRest() {
        var lock = DrivingLock()
        for (index, speed) in [0.0, 0.5, DrivingLock.releaseSpeed, 2.0, DrivingLock.engageSpeed - 0.01].enumerated() {
            lock.update(speed: speed, at: Double(index))
            #expect(!lock.isMoving)
        }
    }

    @Test func staysEngagedBetweenFourAndEight() {
        var lock = engaged()
        for second in 1...120 {
            lock.update(speed: 2.0, at: Double(second)) // 7.2 km/h
            #expect(lock.isMoving)
        }
    }

    @Test func staysEngagedThroughAShortStop() {
        var lock = engaged()
        lock.update(speed: 3.0, at: 1)
        lock.update(speed: 0, at: 2) // the stop starts here
        lock.update(speed: 0, at: 11) // nine seconds later
        #expect(lock.isMoving)
        lock.update(speed: 0, at: 12) // ten seconds later
        #expect(!lock.isMoving)
    }

    @Test func aMovingReadingResetsTheStopTimer() {
        var lock = engaged()
        lock.update(speed: 0, at: 1)
        lock.update(speed: 0, at: 8)
        lock.update(speed: 3.0, at: 9) // moving again
        lock.update(speed: 0, at: 10) // a new stop starts
        lock.update(speed: 0, at: 19)
        #expect(lock.isMoving)
        lock.update(speed: 0, at: 20)
        #expect(!lock.isMoving)
    }

    @Test func aCrawlAboveFourKmhAlsoResetsTheStopTimer() {
        var lock = engaged()
        lock.update(speed: 0, at: 1)
        lock.update(speed: 0, at: 8)
        lock.update(speed: DrivingLock.releaseSpeed, at: 9) // a crawl at exactly 4 km/h is not stopped
        lock.update(speed: 0, at: 10)
        lock.update(speed: 0, at: 19)
        #expect(lock.isMoving)
    }

    @Test func unknownSpeedKeepsEngaged() {
        var lock = engaged()
        lock.update(speed: nil, at: 500)
        #expect(lock.isMoving)
    }

    @Test func unknownSpeedKeepsReleased() {
        var lock = DrivingLock()
        lock.update(speed: nil, at: 0)
        #expect(!lock.isMoving)
    }

    @Test func unknownSpeedDoesNotStartTheStopTimer() {
        var lock = engaged()
        lock.update(speed: nil, at: 1)
        lock.update(speed: 0, at: 5) // the stop starts here, not at 1
        lock.update(speed: 0, at: 14)
        #expect(lock.isMoving)
        lock.update(speed: 0, at: 15)
        #expect(!lock.isMoving)
    }

    @Test func aSpeedThatCannotBeRightCountsAsUnknown() {
        var lock = engaged()
        lock.update(speed: -1, at: 1) // CoreLocation reports -1 when it has no speed
        lock.update(speed: .nan, at: 2)
        lock.update(speed: .infinity, at: 3)
        #expect(lock.isMoving)
        var rest = DrivingLock()
        rest.update(speed: .infinity, at: 0)
        #expect(!rest.isMoving)
    }

    @Test func canEngageAgainAfterReleasing() {
        var lock = engaged()
        lock.update(speed: 0, at: 1)
        lock.update(speed: 0, at: 11)
        #expect(!lock.isMoving)
        lock.update(speed: cruising, at: 12)
        #expect(lock.isMoving)
    }

    @Test func passengerModeNeverLocks() {
        let lock = engaged()
        #expect(lock.isMoving)
        #expect(!lock.isTypingLocked(passengerMode: true))
    }

    @Test func lockedOnlyWhenMovingAndNotPassenger() {
        let moving = engaged()
        let still = DrivingLock()
        #expect(moving.isTypingLocked(passengerMode: false))
        #expect(!moving.isTypingLocked(passengerMode: true))
        #expect(!still.isTypingLocked(passengerMode: false))
        #expect(!still.isTypingLocked(passengerMode: true))
    }
}
