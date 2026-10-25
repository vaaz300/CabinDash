import Foundation
import Testing
@testable import CabinCore

@Suite struct StoreAPITests {
    @Test func countryFollowsTheRegion() {
        #expect(StoreAPI.country(forRegion: "IE") == "ie")
        #expect(StoreAPI.country(forRegion: nil) == "us")
        #expect(StoreAPI.country(forRegion: "USA") == "us")
    }

    @Test func lookupURLListsTheIDs() {
        #expect(StoreAPI.lookupURL(ids: [1, 2], country: "us")?.absoluteString == "https://itunes.apple.com/lookup?id=1,2&country=us")
        #expect(StoreAPI.lookupURL(ids: [], country: "us") == nil)
    }

    @Test func searchURLEscapesTheTerm() {
        let url = StoreAPI.searchURL(term: "Q & A", country: "gb")?.absoluteString ?? ""
        #expect(url.contains("term=Q%20%26%20A"))
        #expect(url.contains("country=gb"))
        #expect(url.contains("entity=software"))
        #expect(StoreAPI.searchURL(term: "   ", country: "gb") == nil)
    }

    @Test func decodesResultsWithMissingFields() throws {
        let json = #"{"results":[{"trackId":1,"trackName":"A","artworkUrl512":"https://x/512.png","artworkUrl100":"https://x/100.png"},{"trackName":"No id"}]}"#
        let response = try JSONDecoder().decode(StoreResponse.self, from: Data(json.utf8))
        #expect(response.results.count == 2)
        #expect(response.results[0].artworkURL?.absoluteString == "https://x/512.png")
        #expect(response.results[1].trackId == nil)
        #expect(response.results[1].artworkURL == nil)
    }

    @Test func artworkMustBeHTTPS() {
        let insecure = StoreResult(artworkUrl512: "http://x/a.png")
        #expect(insecure.artworkURL == nil)
        let fallback = StoreResult(artworkUrl512: "http://x/a.png", artworkUrl100: "https://x/b.png")
        #expect(fallback.artworkURL?.absoluteString == "https://x/b.png")
    }
}

@Suite struct IconMatcherTests {
    @Test func wholeWordsOnly() {
        #expect(IconMatcher.containsWord("Mine - Notes", "mine"))
        #expect(!IconMatcher.containsWord("Minecraft", "mine"))
        #expect(!IconMatcher.containsWord("Spotify2", "spotify"))
        #expect(IconMatcher.containsWord("My Spotify: Music", "spotify"))
        #expect(IconMatcher.containsWord("Waze Navigation & Live Traffic", "waze"))
        #expect(IconMatcher.containsWord("Google Maps - Transit & Food", "google maps"))
    }

    @Test func emptyInputsNeverMatch() {
        #expect(!IconMatcher.containsWord("", "x"))
        #expect(!IconMatcher.containsWord("abc", ""))
    }

    @Test func laterOccurrenceCanStillMatch() {
        #expect(IconMatcher.containsWord("Minecraft Mine", "mine"))
    }

    @Test func vendorStopsLookalikes() {
        let appleMaps = Catalog.entry(id: "apple-maps")!
        let google = StoreResult(trackId: 585027354, trackName: "Google Maps - Transit & Food", sellerName: "Google LLC")
        let apple = StoreResult(trackId: 915056765, trackName: "Maps", sellerName: "Apple")
        #expect(!IconMatcher.verify(appleMaps, google))
        #expect(IconMatcher.verify(appleMaps, apple))
    }

    @Test func nameMustAppearInTheResult() {
        let waze = Catalog.entry(id: "waze")!
        #expect(IconMatcher.verify(waze, StoreResult(trackName: "Waze Navigation & Live Traffic")))
        #expect(!IconMatcher.verify(waze, StoreResult(trackName: "Google Maps")))
        #expect(!IconMatcher.verify(waze, StoreResult()))
    }

    @Test func shortNameCutsAtTheFirstSeparator() {
        #expect(IconMatcher.shortName("Spotify: Music and Podcasts") == "Spotify")
        #expect(IconMatcher.shortName("Foo - Bar") == "Foo")
        #expect(IconMatcher.shortName("Foo \u{2014} Bar") == "Foo")
        #expect(IconMatcher.shortName("Plain Name") == "Plain Name")
        #expect(IconMatcher.shortName("Mid: dle - end") == "Mid")
    }

    @Test func genresMapToCategories() {
        #expect(IconMatcher.category(forGenre: "Navigation") == .navigation)
        #expect(IconMatcher.category(forGenre: "Music") == .audio)
        #expect(IconMatcher.category(forGenre: "Social Networking") == .messages)
        #expect(IconMatcher.category(forGenre: "Books") == .talk)
        #expect(IconMatcher.category(forGenre: "Games") == .more)
        #expect(IconMatcher.category(forGenre: nil) == .more)
    }

    @Test func knownAppsComeBackAsTheCatalogEntry() {
        let result = StoreResult(trackId: 324684580, trackName: "Spotify: Music and Podcasts", sellerName: "Spotify AB", primaryGenreName: "Music")
        let entry = IconMatcher.entry(from: result)
        #expect(entry?.id == "spotify")
        #expect(entry?.publisher == "Spotify AB")
        #expect(entry?.scheme == "spotify")
    }

    @Test func unknownAppsGetANewEntry() {
        let result = StoreResult(trackId: 1, trackName: "Foo App: Bar", sellerName: "Foo Inc", primaryGenreName: "Navigation")
        let entry = IconMatcher.entry(from: result)
        #expect(entry?.id == "t1")
        #expect(entry?.name == "Foo App")
        #expect(entry?.category == .navigation)
        #expect(entry?.trackID == 1)
        #expect(entry?.match == "foo app")
        #expect(entry?.scheme == nil)
    }

    @Test func resultsWithoutAnIDOrNameAreSkipped() {
        #expect(IconMatcher.entry(from: StoreResult(trackName: "x")) == nil)
        #expect(IconMatcher.entry(from: StoreResult(trackId: 5)) == nil)
    }
}

@Suite struct IconRecordTests {
    private let day: TimeInterval = 24 * 3600
    private let origin = Date(timeIntervalSince1970: 1_000_000)

    @Test func foundIconsStayFreshForThirtyDays() {
        let record = IconRecord(url: "https://x/a.png", fetchedAt: origin)
        #expect(record.isFresh(at: origin.addingTimeInterval(29 * day)))
        #expect(!record.isFresh(at: origin.addingTimeInterval(31 * day)))
    }

    @Test func missesAreRetriedAfterADay() {
        let record = IconRecord(url: nil, fetchedAt: origin)
        #expect(record.isFresh(at: origin.addingTimeInterval(23 * 3600)))
        #expect(!record.isFresh(at: origin.addingTimeInterval(25 * 3600)))
    }

    @Test func aClockSetBackwardsIsNotFresh() {
        let record = IconRecord(url: "https://x/a.png", fetchedAt: origin)
        #expect(!record.isFresh(at: origin.addingTimeInterval(-10)))
    }

    @Test func roundTripsThroughJSON() throws {
        let record = IconRecord(url: "https://x/a.png", fetchedAt: origin)
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(IconRecord.self, from: data) == record)
    }
}
