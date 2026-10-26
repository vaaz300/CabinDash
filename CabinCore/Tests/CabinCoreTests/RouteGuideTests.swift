import Foundation
import Testing
@testable import CabinCore

private let straightRoute = [
    RouteStep(instruction: "Head north", meters: 1100, endLatitude: 0.01, endLongitude: 0),
    RouteStep(instruction: "Turn left", meters: 1100, endLatitude: 0.02, endLongitude: 0),
    RouteStep(instruction: "Arrive", meters: 0, endLatitude: 0.02, endLongitude: 0.01)
]

@Suite struct RouteGuideTests {
    @Test func staysOnTheFirstStepFarFromItsEnd() {
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 0, latitude: 0, longitude: 0) == 0)
    }

    @Test func advancesWhenTheStepEndIsReached() {
        // 0.0002 degrees of latitude is about 22 m.
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 0, latitude: 0.0098, longitude: 0) == 1)
    }

    @Test func doesNotAdvanceJustOutsideTheRadius() {
        // 0.0005 degrees is about 56 m, outside the 45 m radius.
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 0, latitude: 0.0095, longitude: 0) == 0)
    }

    @Test func neverMovesBackwards() {
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 2, latitude: 0, longitude: 0) == 2)
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 1, latitude: 0, longitude: 0) == 1)
    }

    @Test func stopsOnTheLastStep() {
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 1, latitude: 0.0199, longitude: 0) == 2)
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 2, latitude: 0.02, longitude: 0.01) == 2)
    }

    @Test func clampsABadIndexAndHandlesNoSteps() {
        #expect(RouteGuide.currentStep(steps: [], from: 5, latitude: 0, longitude: 0) == 0)
        #expect(RouteGuide.currentStep(steps: straightRoute, from: 99, latitude: 0, longitude: 0) == 2)
        #expect(RouteGuide.currentStep(steps: straightRoute, from: -4, latitude: 0, longitude: 0) == 0)
    }

    @Test func distanceToTheStepEnd() throws {
        let meters = try #require(RouteGuide.metersToStepEnd(steps: straightRoute, index: 0, latitude: 0, longitude: 0))
        #expect(abs(meters - 1111.95) < 1)
        #expect(RouteGuide.metersToStepEnd(steps: straightRoute, index: 7, latitude: 0, longitude: 0) == nil)
        #expect(RouteGuide.metersToStepEnd(steps: [], index: 0, latitude: 0, longitude: 0) == nil)
    }

    @Test func arrivalIsDetectedNearTheLastEnd() {
        #expect(RouteGuide.hasArrived(steps: straightRoute, latitude: 0.02, longitude: 0.0099))
        #expect(!RouteGuide.hasArrived(steps: straightRoute, latitude: 0, longitude: 0))
        #expect(!RouteGuide.hasArrived(steps: [], latitude: 0, longitude: 0))
    }

    @Test func remainingDistanceAddsTheRestOfTheRoute() {
        let remaining = RouteGuide.remainingMeters(steps: straightRoute, index: 0, latitude: 0, longitude: 0)
        #expect(abs(remaining - (1111.95 + 1100)) < 1)
        #expect(RouteGuide.remainingMeters(steps: straightRoute, index: 2, latitude: 0.02, longitude: 0.01) < 1)
        #expect(RouteGuide.remainingMeters(steps: [], index: 0, latitude: 0, longitude: 0) == 0)
    }
}

@Suite struct RouteFormatTests {
    @Test func travelTime() {
        #expect(RouteFormat.travelTime(seconds: 20) == "1 min")
        #expect(RouteFormat.travelTime(seconds: 420) == "7 min")
        #expect(RouteFormat.travelTime(seconds: 3600) == "1 h")
        #expect(RouteFormat.travelTime(seconds: 5100) == "1 h 25 min")
        #expect(RouteFormat.travelTime(seconds: -50) == "1 min")
    }

    @Test func metricManeuverDistance() {
        #expect(RouteFormat.maneuverDistance(meters: 5, units: .kmh) == "10 m")
        #expect(RouteFormat.maneuverDistance(meters: 43, units: .kmh) == "40 m")
        #expect(RouteFormat.maneuverDistance(meters: 430, units: .kmh) == "450 m")
        #expect(RouteFormat.maneuverDistance(meters: 1240, units: .kmh) == "1.2 km")
        #expect(RouteFormat.maneuverDistance(meters: 12_400, units: .kmh) == "12 km")
    }

    @Test func imperialManeuverDistance() {
        #expect(RouteFormat.maneuverDistance(meters: 40, units: .mph) == "150 ft")
        #expect(RouteFormat.maneuverDistance(meters: 100, units: .mph) == "350 ft")
        #expect(RouteFormat.maneuverDistance(meters: 300, units: .mph) == "0.2 mi")
        #expect(RouteFormat.maneuverDistance(meters: 20_000, units: .mph) == "12 mi")
    }

    @Test func manoeuvreSymbols() {
        #expect(RouteFormat.maneuverSymbol("Turn left onto Main Street") == "arrow.turn.up.left")
        #expect(RouteFormat.maneuverSymbol("Turn right onto Elm Road") == "arrow.turn.up.right")
        #expect(RouteFormat.maneuverSymbol("Bear right onto the N11") == "arrow.up.right")
        #expect(RouteFormat.maneuverSymbol("Keep left at the fork") == "arrow.up.left")
        #expect(RouteFormat.maneuverSymbol("Take the exit on the right") == "arrow.up.right")
        #expect(RouteFormat.maneuverSymbol("Make a U-turn") == "arrow.uturn.left")
        #expect(RouteFormat.maneuverSymbol("At the roundabout, take the second exit") == "arrow.triangle.turn.up.right.circle")
        #expect(RouteFormat.maneuverSymbol("Merge onto the M50") == "arrow.triangle.merge")
        #expect(RouteFormat.maneuverSymbol("Arrive at Home") == "flag.checkered")
        #expect(RouteFormat.maneuverSymbol("The destination is on your left.") == "flag.checkered")
        #expect(RouteFormat.maneuverSymbol("Continue straight") == "arrow.up")
        #expect(RouteFormat.maneuverSymbol("") == "arrow.up")
    }

    @Test func tripDistance() {
        #expect(RouteFormat.tripDistance(meters: 8400, units: .kmh) == "8.4 km")
        #expect(RouteFormat.tripDistance(meters: 42_000, units: .kmh) == "42 km")
        #expect(RouteFormat.tripDistance(meters: 16_100, units: .mph) == "10 mi")
    }
}

@Suite struct NavigationLinkTests {
    @Test func googleMapsUsesItsAppWhenInstalled() {
        let url = NavApp.google.directionsURL(toLatitude: 53.3498, longitude: -6.2603, appInstalled: true)
        #expect(url?.absoluteString == "comgooglemaps://?daddr=53.349800,-6.260300&directionsmode=driving")
    }

    @Test func googleMapsFallsBackToTheWeb() {
        let url = NavApp.google.directionsURL(toLatitude: 53.3498, longitude: -6.2603, appInstalled: false)
        #expect(url?.absoluteString == "https://www.google.com/maps/dir/?api=1&destination=53.349800,-6.260300&travelmode=driving")
    }

    @Test func wazeAndAppleMaps() {
        #expect(NavApp.waze.directionsURL(toLatitude: 1, longitude: 2, appInstalled: true)?.absoluteString
                == "waze://?ll=1.000000,2.000000&navigate=yes")
        #expect(NavApp.apple.directionsURL(toLatitude: 1, longitude: 2, appInstalled: false)?.absoluteString
                == "https://maps.apple.com/?daddr=1.000000,2.000000&dirflg=d")
    }
}

@Suite struct RecentTests {
    @Test func screensAndAppsShareTheRecentList() {
        var prefs = Preferences()
        prefs.noteRecent("maps")
        prefs.noteRecent("spotify")
        prefs.noteRecent("maps")
        #expect(prefs.recent == ["maps", "spotify"])
    }

    @Test func recentListKeepsSix() {
        var prefs = Preferences()
        for index in 0..<10 { prefs.noteRecent("app\(index)") }
        #expect(prefs.recent.count == 6)
        #expect(prefs.recent.first == "app9")
    }

    @Test func launchingAnAppIsARecent() {
        var prefs = Preferences()
        if let waze = Catalog.entry(id: "waze") {
            prefs.noteLaunch(waze)
            #expect(prefs.recent == ["waze"])
        } else {
            Issue.record("Waze is missing from the catalog")
        }
    }
}
