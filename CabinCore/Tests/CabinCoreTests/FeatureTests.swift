import Foundation
import Testing
@testable import CabinCore

@Suite struct FeatureTests {
    @Test func everyFeatureHasADistinctTitleAndSymbol() {
        let titles = Feature.allCases.map(\.title)
        let symbols = Feature.allCases.map(\.symbol)
        #expect(!titles.contains(""))
        #expect(!symbols.contains(""))
        #expect(Set(titles).count == Feature.allCases.count)
        #expect(Set(symbols).count == Feature.allCases.count)
    }

    @Test func firstDockPageHoldsTheDrivingScreens() {
        #expect(Dock.pages(showOtherApps: false).first == [.dashboard, .map, .music, .phone])
    }

    @Test func secondPageHoldsDriveAndSettings() {
        #expect(Dock.pages(showOtherApps: false) == [[.dashboard, .map, .music, .phone], [.drive, .settings]])
    }

    @Test func appsGoesOnTheSecondPageBeforeSettings() {
        #expect(Dock.pages(showOtherApps: true) == [[.dashboard, .map, .music, .phone], [.drive, .apps, .settings]])
    }

    @Test func noPageHoldsMoreThanFour() {
        for showOtherApps in [false, true] {
            #expect(Dock.pages(showOtherApps: showOtherApps).allSatisfy { $0.count <= Dock.perPage })
        }
        #expect(Dock.perPage == 4)
    }

    @Test func everyFeatureIsOnExactlyOnePage() {
        let features = Dock.pages(showOtherApps: true).flatMap { $0 }
        #expect(Set(features) == Set(Feature.allCases))
        #expect(features.count == Feature.allCases.count)
    }

    @Test func phoneIsAFeature() {
        #expect(Feature.phone.title == "Phone")
        #expect(Feature.phone.symbol == "phone.fill")
        #expect(Dock.isAvailable(.phone, showOtherApps: false))
    }

    @Test func pageOfAFeature() {
        #expect(Dock.page(of: .music, showOtherApps: false) == 0)
        #expect(Dock.page(of: .drive, showOtherApps: false) == 1)
        #expect(Dock.page(of: .settings, showOtherApps: true) == 1)
        #expect(Dock.page(of: .apps, showOtherApps: false) == nil)
    }

    @Test func appsNeedsTheSwitch() {
        #expect(Dock.isAvailable(.apps, showOtherApps: false) == false)
        #expect(Dock.isAvailable(.apps, showOtherApps: true))
        #expect(Dock.isAvailable(.map, showOtherApps: false))
        #expect(Dock.isAvailable(.map, showOtherApps: true))
    }

    @Test func routerStartsOnTheDashboard() {
        #expect(Router().current == .dashboard)
    }

    @Test func routerMovesToAvailableFeatures() {
        var router = Router()
        router.go(.music, showOtherApps: false)
        #expect(router.current == .music)
    }

    @Test func routerIgnoresAppsWhileOtherAppsIsOff() {
        var router = Router(current: .map)
        router.go(.apps, showOtherApps: false)
        #expect(router.current == .map)
    }

    @Test func routerLeavesAppsWhenTheSwitchGoesOff() {
        var router = Router(current: .apps)
        router.reconcile(showOtherApps: true)
        #expect(router.current == .apps)
        router.reconcile(showOtherApps: false)
        #expect(router.current == .dashboard)
    }

    @Test func reconcileLeavesOtherFeaturesAlone() {
        var router = Router(current: .drive)
        router.reconcile(showOtherApps: false)
        #expect(router.current == .drive)
    }
}

@Suite struct StripTests {
    @Test func noStripsOnTheDashboard() {
        #expect(Strips.visible(on: .dashboard, musicActive: true, routeGuiding: true).isEmpty)
    }

    @Test func routeBannerHidesOnTheMapOnly() {
        #expect(Strips.visible(on: .map, musicActive: false, routeGuiding: true).isEmpty)
        for feature in [Feature.music, .drive, .settings, .apps] {
            #expect(Strips.visible(on: feature, musicActive: false, routeGuiding: true) == [.route])
        }
    }

    @Test func musicStripHidesOnMusicOnly() {
        #expect(Strips.visible(on: .music, musicActive: true, routeGuiding: false).isEmpty)
        for feature in [Feature.map, .drive, .settings, .apps] {
            #expect(Strips.visible(on: feature, musicActive: true, routeGuiding: false) == [.music])
        }
    }

    @Test func routeComesBeforeMusic() {
        #expect(Strips.visible(on: .drive, musicActive: true, routeGuiding: true) == [.route, .music])
    }

    @Test func callStripShowsEverywhereButPhoneAndTheDashboard() {
        #expect(Strips.visible(on: .phone, musicActive: false, routeGuiding: false, callActive: true).isEmpty)
        #expect(Strips.visible(on: .dashboard, musicActive: false, routeGuiding: false, callActive: true).isEmpty)
        for feature in [Feature.map, .music, .drive, .settings, .apps] {
            #expect(Strips.visible(on: feature, musicActive: false, routeGuiding: false, callActive: true) == [.call])
        }
    }

    @Test func callComesFirst() {
        #expect(Strips.visible(on: .drive, musicActive: true, routeGuiding: true, callActive: true) == [.call, .route, .music])
    }

    @Test func routeAndMusicStillShowOnPhone() {
        #expect(Strips.visible(on: .phone, musicActive: true, routeGuiding: true) == [.route, .music])
    }

    @Test func nothingShowsWhenNothingIsActive() {
        for feature in Feature.allCases {
            #expect(Strips.visible(on: feature, musicActive: false, routeGuiding: false).isEmpty)
        }
    }
}

@Suite struct DockMetricsTests {
    @Test func sizeFillsTheHeight() {
        // 410 / (7 + 0.2 * 6) = 50
        #expect(abs(DockMetrics.iconSize(availableHeight: 410, itemCount: 7) - 50) < 0.001)
    }

    @Test func sizeClampsToTheMaximum() {
        #expect(DockMetrics.iconSize(availableHeight: 1000, itemCount: 5) == 52)
    }

    @Test func sizeClampsToTheMinimumOnShortScreens() {
        #expect(DockMetrics.iconSize(availableHeight: 120, itemCount: 7) == 30)
        #expect(DockMetrics.iconSize(availableHeight: -5, itemCount: 5) == 30)
    }

    @Test func noItemsGivesTheMaximum() {
        #expect(DockMetrics.iconSize(availableHeight: 300, itemCount: 0) == 52)
    }

    @Test func gapIsAFifthOfTheIcon() {
        #expect(abs(DockMetrics.gap(forIconSize: 40) - 8) < 0.001)
    }
}
