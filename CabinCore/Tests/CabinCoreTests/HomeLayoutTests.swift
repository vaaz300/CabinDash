import Foundation
import Testing
@testable import CabinCore

@Suite struct HomeLayoutTests {
    private func shelf(_ ids: [String]) -> [AppEntry] {
        ids.compactMap { Catalog.entry(id: $0) }
    }

    @Test func systemLinksComeFirstThenAddApps() {
        #expect(HomeLayout.items(shelf: []).map(\.id) == ["phone", "messages", "add-apps"])
    }

    @Test func shelfAppsFollowTheSystemLinksInShelfOrder() {
        let ids = HomeLayout.items(shelf: shelf(["waze", "spotify"])).map(\.id)
        #expect(ids == ["phone", "messages", "waze", "spotify", "add-apps"])
    }

    @Test func appleMapsAppGetsNoTile() {
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

    @Test func phoneAndMessagesAreSystemLinks() {
        let schemes = HomeLayout.systemLinks.map { item -> String? in
            if case .url(let url) = item.kind { return url.scheme }
            return nil
        }
        #expect(HomeLayout.systemLinks.map(\.id) == ["phone", "messages"])
        #expect(schemes == ["tel", "sms"])
    }

    @Test func pagesHoldEightTiles() {
        let items = (0..<20).map { HomeItem(id: "t\($0)", title: "T", kind: .addApps, symbol: "plus") }
        #expect(HomeLayout.pages(items).map(\.count) == [8, 8, 4])
        #expect(HomeLayout.pages([]).isEmpty)
        #expect(HomeLayout.pages(items, perPage: 0).isEmpty)
    }

    @Test func exactlyFullPageMakesOnePage() {
        let items = (0..<8).map { HomeItem(id: "t\($0)", title: "T", kind: .addApps, symbol: "plus") }
        #expect(HomeLayout.pages(items).count == 1)
    }
}
