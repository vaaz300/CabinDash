import Foundation
import Testing
@testable import CabinCore

@Suite struct CatalogTests {
    @Test func idsAreUnique() {
        let ids = Catalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func appStoreIDsAreUnique() {
        let ids = Catalog.all.compactMap(\.trackID)
        #expect(Set(ids).count == ids.count)
    }

    @Test func schemesFitTheInfoPlistLimit() {
        #expect(Catalog.schemes.count <= 50)
        #expect(!Catalog.schemes.isEmpty)
    }

    @Test func schemesAreBareNames() {
        for scheme in Catalog.schemes {
            #expect(!scheme.contains(":"), "\(scheme) should not contain a colon")
            #expect(!scheme.contains("/"), "\(scheme) should not contain a slash")
            #expect(!scheme.isEmpty)
        }
    }

    @Test func everyCategoryHasAtLeastOneApp() {
        for category in AppCategory.allCases where category != .more {
            #expect(!Catalog.apps(in: category).isEmpty, "\(category.title) is empty")
        }
    }

    @Test func everyAppHasAMatchName() {
        for app in Catalog.all {
            #expect(!app.match.isEmpty)
            #expect(app.match == app.match.lowercased())
            if let vendor = app.vendor { #expect(vendor == vendor.lowercased()) }
        }
    }

    @Test func notInstalledAppsAlwaysHaveAWebAddress() {
        for app in Catalog.all {
            let url = app.launchURL(installed: false)
            #expect(url.scheme == "https", "\(app.name) falls back to \(url)")
        }
    }

    @Test func lookupByIDAndTrackID() {
        #expect(Catalog.entry(id: "spotify")?.trackID == 324684580)
        #expect(Catalog.entry(trackID: 324684580)?.id == "spotify")
        #expect(Catalog.entry(id: "nope") == nil)
    }

    @Test func schemesAreDeduplicatedInOrder() {
        let schemes = Catalog.schemes
        #expect(Set(schemes).count == schemes.count)
        #expect(schemes.first == "maps")
    }
}

@Suite struct AppEntryTests {
    @Test func installedAppOpensItsScheme() {
        let spotify = Catalog.entry(id: "spotify")!
        #expect(spotify.launchURL(installed: true).absoluteString == "spotify://")
        #expect(spotify.launchURL(installed: false).absoluteString == "https://open.spotify.com/")
    }

    @Test func appWithoutSchemeFallsBackToTheStoreOrSearch() {
        let withID = AppEntry(id: "a", name: "Alpha", category: .more, trackID: 42)
        #expect(withID.launchURL(installed: true).absoluteString == "https://apps.apple.com/app/id42")
        let bare = AppEntry(id: "b", name: "Beta Max", category: .more)
        #expect(bare.launchURL(installed: false).absoluteString == "https://apps.apple.com/search?term=Beta%20Max")
    }

    @Test func iconKeyPrefersTheStoreID() {
        #expect(AppEntry(id: "a", name: "Alpha", category: .more, trackID: 42).iconKey == "t42")
        #expect(AppEntry(id: "b", name: "Beta", category: .more).iconKey == "n:beta")
    }

    @Test func matchAndVendorAreLowercased() {
        let entry = AppEntry(id: "a", name: "Alpha", category: .more, match: "ALPHA Two", vendor: "ACME")
        #expect(entry.match == "alpha two")
        #expect(entry.vendor == "acme")
    }

    @Test func decodingToleratesMissingFields() throws {
        let entry = try JSONDecoder().decode(AppEntry.self, from: Data(#"{"id":"x","name":"X"}"#.utf8))
        #expect(entry.category == .more)
        #expect(entry.match == "x")
        #expect(entry.isCustom == false)
        #expect(entry.scheme == nil)
    }

    @Test func unknownCategoryBecomesMore() throws {
        let entry = try JSONDecoder().decode(AppEntry.self, from: Data(#"{"id":"x","name":"X","category":"flying"}"#.utf8))
        #expect(entry.category == .more)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = Catalog.entry(id: "waze")!
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(AppEntry.self, from: data) == original)
    }

    @Test func detectionNeedsAScheme() {
        #expect(Catalog.entry(id: "waze")!.canBeDetected)
        #expect(!Catalog.entry(id: "plugshare")!.canBeDetected)
    }
}
