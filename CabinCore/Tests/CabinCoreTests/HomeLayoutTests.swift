import Foundation
import Testing
@testable import CabinCore

@Suite struct HomeLayoutTests {
    private func shelf(_ ids: [String]) -> [AppEntry] {
        ids.compactMap { Catalog.entry(id: $0) }
    }

    @Test func builtInTilesAreAlwaysThere() {
        let ids = HomeLayout.items(shelf: []).map(\.id)
        #expect(ids == ["phone", "maps", "messages", "now-playing", "drive", "settings", "add-apps"])
    }

    @Test func shelfAppsTakeTheirPinnedPlaces() {
        let ids = HomeLayout.items(shelf: shelf(["waze", "spotify", "google-maps", "apple-podcasts"])).map(\.id)
        #expect(ids == [
            "phone", "spotify", "maps", "messages", "now-playing", "google-maps", "drive", "settings",
            "waze", "apple-podcasts", "add-apps"
        ])
    }

    @Test func missingPinnedAppsAreFilledByTheNextApps() {
        let items = HomeLayout.items(shelf: shelf(["waze", "tidal"]))
        let firstPage = HomeLayout.pages(items)[0].map(\.id)
        #expect(firstPage == ["phone", "maps", "messages", "now-playing", "drive", "settings", "waze", "tidal"])
    }

    @Test func appleMapsAppGetsNoSecondTile() {
        let ids = HomeLayout.items(shelf: shelf(["apple-maps", "waze"])).map(\.id)
        #expect(!ids.contains("apple-maps"))
        #expect(ids.contains("waze"))
    }

    @Test func addAppsIsAlwaysLast() {
        let every = HomeLayout.items(shelf: Catalog.all)
        #expect(every.last?.id == "add-apps")
        #expect(every.filter { $0.id == "add-apps" }.count == 1)
    }

    @Test func noTileAppearsTwice() {
        let ids = HomeLayout.items(shelf: Catalog.all).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func mapsTileShowsAppleMapsArtworkButOpensAScreen() {
        let maps = HomeLayout.builtIn["maps"]
        #expect(maps?.screen == .maps)
        #expect(maps?.artwork?.id == "apple-maps")
        #expect(HomeLayout.builtIn["now-playing"]?.screen == .nowPlaying)
        #expect(HomeLayout.builtIn["drive"]?.screen == .drive)
    }

    @Test func phoneAndMessagesAreSystemLinks() {
        let phone = HomeLayout.builtIn["phone"]
        let messages = HomeLayout.builtIn["messages"]
        #expect(phone != nil)
        #expect(messages != nil)
        if case .url(let url)? = phone?.kind {
            #expect(url.scheme == "tel")
        } else {
            Issue.record("The Phone tile is not a link")
        }
        if case .url(let url)? = messages?.kind {
            #expect(url.scheme == "sms")
        } else {
            Issue.record("The Messages tile is not a link")
        }
    }

    @Test func pagesHoldEightTiles() {
        let items = (0..<20).map { HomeItem(id: "t\($0)", title: "T", kind: .settings, symbol: "gearshape") }
        #expect(HomeLayout.pages(items).map(\.count) == [8, 8, 4])
        #expect(HomeLayout.pages([]).isEmpty)
        #expect(HomeLayout.pages(items, perPage: 0).isEmpty)
    }

    @Test func exactlyFullPageMakesOnePage() {
        let items = (0..<8).map { HomeItem(id: "t\($0)", title: "T", kind: .settings, symbol: "gearshape") }
        #expect(HomeLayout.pages(items).count == 1)
    }

    @Test func dockStartsWithTheDefaults() {
        let items = HomeLayout.items(shelf: [])
        #expect(HomeLayout.dock(items: items, recent: []).map(\.id) == ["maps", "now-playing", "drive"])
    }

    @Test func dockPutsRecentsFirstWithoutRepeats() {
        let items = HomeLayout.items(shelf: shelf(["spotify", "waze"]))
        let ids = HomeLayout.dock(items: items, recent: ["waze", "maps", "waze", "gone"]).map(\.id)
        #expect(ids == ["waze", "maps", "now-playing"])
    }

    @Test func dockSkipsSettingsAndAddApps() {
        let items = HomeLayout.items(shelf: [])
        let ids = HomeLayout.dock(items: items, recent: ["settings", "add-apps", "drive"], limit: 2).map(\.id)
        #expect(ids == ["drive", "maps"])
    }

    @Test func dockRespectsTheLimit() {
        let items = HomeLayout.items(shelf: [])
        #expect(HomeLayout.dock(items: items, recent: [], limit: 0).isEmpty)
        #expect(HomeLayout.dock(items: items, recent: [], limit: 1).map(\.id) == ["maps"])
    }

    @Test func screenIdsMatchTileIds() {
        for screen in AppScreen.allCases {
            #expect(HomeLayout.builtIn[screen.rawValue]?.screen == screen)
        }
    }
}
