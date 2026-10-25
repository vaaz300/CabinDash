import Foundation
import Testing
@testable import CabinCore

@Suite struct UnitsTests {
    @Test func convertsSpeed() {
        #expect(abs(Units.kmh.speed(fromMetersPerSecond: 10) - 36) < 0.0001)
        #expect(abs(Units.mph.speed(fromMetersPerSecond: 10) - 22.36936) < 0.0001)
    }

    @Test func convertsDistance() {
        #expect(abs(Units.kmh.distance(fromMeters: 2500) - 2.5) < 0.0001)
        #expect(abs(Units.mph.distance(fromMeters: 1609.344) - 1) < 0.0001)
    }

    @Test func labelsAndGaugeRange() {
        #expect(Units.kmh.speedLabel == "km/h")
        #expect(Units.mph.speedLabel == "mph")
        #expect(Units.kmh.distanceLabel == "km")
        #expect(Units.mph.distanceLabel == "mi")
        #expect(Units.kmh.gaugeMax == 200)
        #expect(Units.mph.gaugeMax == 120)
    }

    @Test func regionPicksTheUnit() {
        #expect(Units.preferred(forRegion: "US") == .mph)
        #expect(Units.preferred(forRegion: "gb") == .mph)
        #expect(Units.preferred(forRegion: "IE") == .kmh)
        #expect(Units.preferred(forRegion: nil) == .kmh)
    }

    @Test func unknownValueDecodesAsKmh() throws {
        let decoded = try JSONDecoder().decode([Units].self, from: Data(#"["mph","furlongs"]"#.utf8))
        #expect(decoded == [.mph, .kmh])
    }
}

@Suite struct GeoTests {
    @Test func oneDegreeOfLatitudeIsAbout111Km() {
        let meters = Geo.distance(0, 0, 1, 0)
        #expect(abs(meters - 111_195) < 50)
    }

    @Test func samePointIsZero() {
        #expect(Geo.distance(53.35, -6.26, 53.35, -6.26) == 0)
    }

    @Test func isSymmetric() {
        let forward = Geo.distance(53.35, -6.26, 51.5, -0.12)
        let back = Geo.distance(51.5, -0.12, 53.35, -6.26)
        #expect(abs(forward - back) < 0.001)
    }
}

@Suite struct CompassTests {
    @Test func cardinalDirections() {
        #expect(Compass.cardinal(0) == "N")
        #expect(Compass.cardinal(44) == "NE")
        #expect(Compass.cardinal(90) == "E")
        #expect(Compass.cardinal(225) == "SW")
        #expect(Compass.cardinal(350) == "N")
        #expect(Compass.cardinal(-10) == "N")
        #expect(Compass.cardinal(720) == "N")
    }

    @Test func needleTurnsTheShortWay() {
        #expect(Compass.unwrap(previous: 350, next: 10) == 370)
        #expect(Compass.unwrap(previous: 10, next: 350) == -10)
        #expect(Compass.unwrap(previous: 370, next: 20) == 380)
        #expect(Compass.unwrap(previous: 90, next: 100) == 100)
    }

    @Test func degreesAreThreeDigits() {
        #expect(Compass.degreesText(45) == "045\u{00B0}")
        #expect(Compass.degreesText(0) == "000\u{00B0}")
        #expect(Compass.degreesText(359.6) == "000\u{00B0}")
        #expect(Compass.degreesText(-5) == "355\u{00B0}")
    }
}

@Suite struct DriveFormatTests {
    @Test func gaugeFractionIsClamped() {
        #expect(DriveFormat.gaugeFraction(speed: 100, units: .kmh) == 0.5)
        #expect(DriveFormat.gaugeFraction(speed: 300, units: .kmh) == 1)
        #expect(DriveFormat.gaugeFraction(speed: -5, units: .kmh) == 0)
        #expect(DriveFormat.gaugeFraction(speed: 60, units: .mph) == 0.5)
    }

    @Test func distanceKeepsADecimalWhenShort() {
        #expect(DriveFormat.distance(meters: 1500, units: .kmh) == "1.5")
        #expect(DriveFormat.distance(meters: 1609.344, units: .mph) == "1.0")
        #expect(DriveFormat.distance(meters: 250_000, units: .kmh) == "250")
        #expect(DriveFormat.distance(meters: 0, units: .kmh) == "0.0")
    }

    @Test func durationFormats() {
        #expect(DriveFormat.duration(seconds: 0) == "0:00")
        #expect(DriveFormat.duration(seconds: 65) == "1:05")
        #expect(DriveFormat.duration(seconds: 3725) == "1:02:05")
        #expect(DriveFormat.duration(seconds: -5) == "0:00")
    }
}

@Suite struct TripTrackerTests {
    /// 0.0001 degrees of latitude is about 11.12 metres.
    private func fix(step: Int, speed: Double? = 11, accuracy: Double = 5, secondsPerStep: Double = 1) -> Fix {
        Fix(latitude: Double(step) * 0.0001, longitude: 0, time: Double(step) * secondsPerStep, speed: speed, course: 0, accuracy: accuracy)
    }

    @Test func firstFixOnlyReturnsSpeed() {
        var trip = TripTracker()
        let speed = trip.ingest(fix(step: 0))
        #expect(speed == 11)
        #expect(trip.meters == 0)
        #expect(trip.seconds == 0)
    }

    @Test func driftingAddsDistanceAndTime() {
        var trip = TripTracker()
        trip.ingest(fix(step: 0))
        trip.ingest(fix(step: 1))
        #expect(abs(trip.meters - 11.12) < 0.05)
        #expect(trip.seconds == 1)
    }

    @Test func standingStillAddsNothing() {
        var trip = TripTracker()
        trip.ingest(fix(step: 0, speed: 0))
        trip.ingest(fix(step: 1, speed: 0))
        #expect(trip.meters == 0)
        #expect(trip.seconds == 0)
    }

    @Test func poorAccuracyIsIgnored() {
        var trip = TripTracker()
        trip.ingest(fix(step: 0, accuracy: 100))
        trip.ingest(fix(step: 1, accuracy: 100))
        #expect(trip.meters == 0)
    }

    @Test func aJumpIsIgnored() {
        var trip = TripTracker()
        trip.ingest(Fix(latitude: 0, longitude: 0, time: 0, speed: 11, course: 0, accuracy: 5))
        trip.ingest(Fix(latitude: 1, longitude: 0, time: 1, speed: 11, course: 0, accuracy: 5))
        #expect(trip.meters == 0)
    }

    @Test func aLongGapIsNotCountedAsDriving() {
        var trip = TripTracker()
        trip.ingest(fix(step: 0))
        trip.ingest(fix(step: 1, secondsPerStep: 20))
        #expect(trip.meters == 0)
    }

    @Test func missingSpeedIsWorkedOutFromMovement() {
        var trip = TripTracker()
        trip.ingest(fix(step: 0, speed: nil))
        let speed = trip.ingest(fix(step: 2, speed: nil, secondsPerStep: 1))
        #expect(abs(speed - 11.12) < 0.1)
        #expect(trip.seconds == 2)
    }

    @Test func firstFixWithoutSpeedIsZero() {
        var trip = TripTracker()
        let speed = trip.ingest(fix(step: 0, speed: nil))
        #expect(speed == 0)
    }

    @Test func averageNeedsAFewSeconds() {
        var trip = TripTracker()
        for step in 0...3 { trip.ingest(fix(step: step)) }
        #expect(trip.averageSpeed == nil)
        for step in 4...8 { trip.ingest(fix(step: step)) }
        let average = trip.averageSpeed
        #expect(average != nil)
        #expect(abs((average ?? 0) - 11.12) < 0.1)
    }

    @Test func breakingContinuitySkipsTheGap() {
        var trip = TripTracker()
        trip.ingest(fix(step: 0))
        trip.breakContinuity()
        trip.ingest(fix(step: 1))
        #expect(trip.meters == 0)
    }

    @Test func resetClearsTheTrip() {
        var trip = TripTracker()
        trip.ingest(fix(step: 0))
        trip.ingest(fix(step: 1))
        trip.reset()
        #expect(trip.meters == 0)
        #expect(trip.seconds == 0)
        trip.ingest(fix(step: 2))
        #expect(trip.meters == 0)
    }

    @Test func savesOnlyTheTotals() throws {
        var trip = TripTracker()
        trip.ingest(fix(step: 0))
        trip.ingest(fix(step: 1))
        let data = try JSONEncoder().encode(trip)
        let restored = try JSONDecoder().decode(TripTracker.self, from: data)
        #expect(restored.meters == trip.meters)
        #expect(restored.seconds == trip.seconds)
        let keys = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?.keys.sorted()
        #expect(keys == ["meters", "seconds"])
    }

    @Test func emptyJSONDecodesToZero() throws {
        let trip = try JSONDecoder().decode(TripTracker.self, from: Data("{}".utf8))
        #expect(trip.meters == 0)
        #expect(trip.seconds == 0)
    }
}
