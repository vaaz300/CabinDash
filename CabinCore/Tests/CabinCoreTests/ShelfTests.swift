import Foundation
import Testing
@testable import CabinCore

@Suite struct PreferencesTests {
    @Test func defaultsFollowTheRegion() {
        #expect(Preferences.defaults(region: "US").units == .mph)
        #expect(Preferences.defaults(region: "IE").units == .kmh)
    }

    @Test func emptyJSONGivesDefaults() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(decoded.units == .kmh)
        #expect(decoded.navApp == .apple)
        #expect(decoded.theme == .auto)
        #expect(decoded.wallpaper == .dusk)
        #expect(decoded.keepAwake)
        #expect(decoded.autoDetect)
        #expect(decoded.places.count == 2)
        #expect(decoded.added.isEmpty)
    }

    @Test func unknownChoicesFallBackInsteadOfFailing() throws {
        let json = #"{"theme":"neon","wallpaper":"x","units":"furlongs","navApp":"bing","keepAwake":false}"#
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(decoded.theme == .auto)
        #expect(decoded.wallpaper == .dusk)
        #expect(decoded.units == .kmh)
        #expect(decoded.navApp == .apple)
        #expect(decoded.keepAwake == false)
    }

    @Test func roundTripsThroughJSON() throws {
        var prefs = Preferences(units: .mph, navApp: .waze, theme: .night, wallpaper: .ember, keepAwake: false)
        prefs.addApp(Catalog.entry(id: "plugshare")!, installed: [])
        prefs.hidden.insert("spotify")
        prefs.noteLaunch(Catalog.entry(id: "waze")!)
        prefs.places.append(Place(name: "Gym", address: "1 Main St", kind: .pin))
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == prefs)
    }

    @Test func recentsKeepTheLastSix() {
        var prefs = Preferences()
        for app in Catalog.all.prefix(8) { prefs.noteLaunch(app) }
        #expect(prefs.recent.count == 6)
        #expect(prefs.recent.first == Catalog.all[7].id)
    }

    @Test func launchingAgainMovesItToTheFront() {
        var prefs = Preferences()
        let a = Catalog.all[0], b = Catalog.all[1]
        prefs.noteLaunch(a)
        prefs.noteLaunch(b)
        prefs.noteLaunch(a)
        #expect(prefs.recent == [a.id, b.id])
    }
}

@Suite struct ShelfTests {
    private let installed: Set<String> = ["spotify", "waze"]

    @Test func detectedAppsAppearInCatalogOrder() {
        let shelf = Shelf.compose(installed: installed, preferences: Preferences())
        #expect(shelf.map(\.id) == ["waze", "spotify"])
    }

    @Test func nothingInstalledMeansAnEmptyShelf() {
        #expect(Shelf.compose(installed: [], preferences: Preferences()).isEmpty)
    }

    @Test func removingADetectedAppHidesIt() {
        var prefs = Preferences()
        let spotify = Catalog.entry(id: "spotify")!
        prefs.removeApp(spotify, installed: installed)
        #expect(prefs.hidden.contains("spotify"))
        #expect(Shelf.compose(installed: installed, preferences: prefs).map(\.id) == ["waze"])
        #expect(!prefs.isOnShelf(spotify, installed: installed))
    }

    @Test func addingItBackUnhidesIt() {
        var prefs = Preferences()
        let spotify = Catalog.entry(id: "spotify")!
        prefs.removeApp(spotify, installed: installed)
        prefs.addApp(spotify, installed: installed)
        #expect(prefs.hidden.isEmpty)
        #expect(prefs.added.isEmpty) // it shows up by itself, so it is not stored twice
        #expect(Shelf.compose(installed: installed, preferences: prefs).map(\.id) == ["waze", "spotify"])
    }

    @Test func appsThatCannotBeDetectedAreAddedByHand() {
        var prefs = Preferences()
        let plugshare = Catalog.entry(id: "plugshare")!
        #expect(!prefs.isOnShelf(plugshare, installed: installed))
        prefs.addApp(plugshare, installed: installed)
        prefs.addApp(plugshare, installed: installed)
        #expect(prefs.added.count == 1)
        #expect(Shelf.compose(installed: installed, preferences: prefs).map(\.id) == ["waze", "spotify", "plugshare"])
        prefs.removeApp(plugshare, installed: installed)
        #expect(prefs.added.isEmpty)
        #expect(prefs.hidden.isEmpty)
    }

    @Test func turningDetectionOffUsesOnlyAddedApps() {
        var prefs = Preferences()
        prefs.autoDetect = false
        #expect(Shelf.compose(installed: installed, preferences: prefs).isEmpty)
        prefs.addApp(Catalog.entry(id: "waze")!, installed: installed)
        #expect(prefs.added.map(\.id) == ["waze"])
        #expect(Shelf.compose(installed: installed, preferences: prefs).map(\.id) == ["waze"])
    }

    @Test func anAddedAppIsNotListedTwice() {
        var prefs = Preferences()
        prefs.added = [Catalog.entry(id: "waze")!]
        #expect(Shelf.compose(installed: installed, preferences: prefs).map(\.id) == ["waze", "spotify"])
    }

    @Test func catalogUpdatesWinOverOldSaves() {
        var prefs = Preferences()
        var stale = Catalog.entry(id: "plugshare")!
        stale.web = "https://old.example.com/"
        prefs.added = [stale]
        let shelf = Shelf.compose(installed: [], preferences: prefs)
        #expect(shelf.first?.web == Catalog.entry(id: "plugshare")?.web)
    }

    @Test func customShortcutsKeepTheirOwnDetails() {
        var prefs = Preferences()
        let custom = AppEntry(id: "web-1", name: "My Radio", category: .audio, web: "https://radio.example.com/", isCustom: true)
        prefs.addApp(custom, installed: [])
        let shelf = Shelf.compose(installed: [], preferences: prefs)
        #expect(shelf == [custom])
    }

    @Test func sectionsFollowTheCategoryOrder() {
        let apps = ["spotify", "plugshare", "waze"].compactMap { Catalog.entry(id: $0) }
        let sections = Shelf.sections(apps)
        #expect(sections.map(\.category) == [.navigation, .audio, .charging])
        #expect(sections.map { $0.apps.map(\.id) } == [["waze"], ["spotify"], ["plugshare"]])
    }

    @Test func emptyCategoriesAreLeftOut() {
        #expect(Shelf.sections([]).isEmpty)
    }

    @Test func recentsOnlyShowAppsStillOnTheShelf() {
        let shelf = ["waze", "spotify"].compactMap { Catalog.entry(id: $0) }
        let recents = Shelf.recents(shelf, ids: ["gone", "spotify", "waze"])
        #expect(recents.map(\.id) == ["spotify", "waze"])
    }

    @Test func recentsShowAtMostFour() {
        let shelf = Array(Catalog.all.prefix(6))
        let recents = Shelf.recents(shelf, ids: shelf.map(\.id))
        #expect(recents.count == 4)
    }

    @Test func resetClearsTheShelfChoices() {
        var prefs = Preferences()
        prefs.autoDetect = false
        prefs.added = [Catalog.entry(id: "waze")!]
        prefs.hidden = ["spotify"]
        prefs.recent = ["waze"]
        prefs.resetApps()
        #expect(prefs.autoDetect)
        #expect(prefs.added.isEmpty)
        #expect(prefs.hidden.isEmpty)
        #expect(prefs.recent.isEmpty)
    }
}

@Suite struct WallpaperTests {
    @Test func everyWallpaperHasThreeHues() {
        for wallpaper in Wallpaper.allCases {
            #expect(wallpaper.hues.count == 3)
            #expect(wallpaper.hues.allSatisfy { $0 >= 0 && $0 <= 360 })
            #expect(!wallpaper.title.isEmpty)
        }
    }

    @Test func graphiteIsNearlyGrey() {
        #expect(Wallpaper.graphite.saturation < 0.2)
        #expect(Wallpaper.dusk.saturation > 0.5)
    }

    @Test func titlesAreCapitalised() {
        #expect(Wallpaper.dusk.title == "Dusk")
        #expect(Wallpaper.graphite.title == "Graphite")
    }
}

@Suite struct PlacesTests {
    @Test func appleMapsLinkEscapesTheAddress() {
        let url = NavApp.apple.directionsURL(to: "1 Main St & 2nd", appInstalled: false)
        #expect(url?.absoluteString == "https://maps.apple.com/?daddr=1%20Main%20St%20%26%202nd&dirflg=d")
    }

    @Test func googleUsesItsAppWhenInstalled() {
        let app = NavApp.google.directionsURL(to: "Dublin", appInstalled: true)?.absoluteString
        let web = NavApp.google.directionsURL(to: "Dublin", appInstalled: false)?.absoluteString
        #expect(app == "comgooglemaps://?daddr=Dublin&directionsmode=driving")
        #expect(web == "https://www.google.com/maps/dir/?api=1&destination=Dublin&travelmode=driving")
    }

    @Test func wazeUsesItsAppWhenInstalled() {
        #expect(NavApp.waze.directionsURL(to: "Cork", appInstalled: true)?.absoluteString == "waze://?q=Cork&navigate=yes")
        #expect(NavApp.waze.directionsURL(to: "Cork", appInstalled: false)?.absoluteString == "https://waze.com/ul?q=Cork&navigate=yes")
    }

    @Test func blankAddressesGiveNoLink() {
        for app in NavApp.allCases {
            #expect(app.directionsURL(to: "   ", appInstalled: true) == nil)
        }
    }

    @Test func schemesMatchTheCatalog() {
        #expect(NavApp.apple.scheme == nil)
        for app in NavApp.allCases {
            if let scheme = app.scheme { #expect(Catalog.schemes.contains(scheme)) }
        }
    }

    @Test func placesDecodeEvenWhenFieldsAreMissing() throws {
        let place = try JSONDecoder().decode(Place.self, from: Data(#"{"name":"Gym"}"#.utf8))
        #expect(place.name == "Gym")
        #expect(place.address.isEmpty)
        #expect(place.kind == .pin)
        let unknownKind = try JSONDecoder().decode(Place.self, from: Data(#"{"name":"Dock","kind":"boat"}"#.utf8))
        #expect(unknownKind.kind == .pin)
    }

    @Test func placeNeedsAnAddressToNavigate() {
        #expect(!Place(name: "Home").hasAddress)
        #expect(!Place(name: "Home", address: "  ").hasAddress)
        #expect(Place(name: "Home", address: "1 Main St").hasAddress)
    }

    @Test func webLinksAreCleanedUp() {
        #expect(WebLink.clean("spotify.com")?.absoluteString == "https://spotify.com")
        #expect(WebLink.clean("  https://open.spotify.com/x ")?.absoluteString == "https://open.spotify.com/x")
        #expect(WebLink.clean("http://example.com")?.scheme == "http")
        #expect(WebLink.clean("example.com:8080/path")?.host == "example.com")
    }

    @Test func appLinksGiveTheirScheme() {
        #expect(WebLink.appScheme(from: "myapp://open") == "myapp")
        #expect(WebLink.appScheme(from: " MyApp:// ") == "myapp")
        #expect(WebLink.appScheme(from: "com.example.app://") == "com.example.app")
    }

    @Test func webAndSystemLinksAreNotAppLinks() {
        #expect(WebLink.appScheme(from: "https://example.com") == nil)
        #expect(WebLink.appScheme(from: "example.com") == nil)
        #expect(WebLink.appScheme(from: "javascript://x") == nil)
        #expect(WebLink.appScheme(from: "://x") == nil)
        #expect(WebLink.appScheme(from: "my app://x") == nil)
        #expect(WebLink.appScheme(from: "1app://x") == nil)
    }

    @Test func tappedAppsTryTheirLinkThenTheFallback() {
        let waze = Catalog.entry(id: "waze")!
        #expect(waze.launchSequence.map(\.absoluteString) == ["waze://", "https://waze.com/ul"])
        let plugshare = Catalog.entry(id: "plugshare")!
        #expect(plugshare.launchSequence.map(\.absoluteString) == ["https://www.plugshare.com/"])
    }

    @Test func nonWebAddressesAreRejected() {
        #expect(WebLink.clean("") == nil)
        #expect(WebLink.clean("hello world") == nil)
        #expect(WebLink.clean("mailto:a@b.com") == nil)
        #expect(WebLink.clean("javascript:alert(1)") == nil)
        #expect(WebLink.clean("localhost") == nil)
        #expect(WebLink.clean("ftp://example.com") == nil)
        #expect(WebLink.clean("tel:123") == nil)
    }
}
