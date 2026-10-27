import Foundation
import Testing
@testable import CabinCore

@Suite struct MusicSectionTests {
    @Test func fiveSectionsInOrder() {
        #expect(MusicSection.allCases == [.nowPlaying, .playlists, .liked, .search, .queue])
    }

    @Test func titlesAndSymbolsAreDistinctAndNotEmpty() {
        let titles = MusicSection.allCases.map(\.title)
        let symbols = MusicSection.allCases.map(\.symbol)
        #expect(!titles.contains(""))
        #expect(!symbols.contains(""))
        #expect(Set(titles).count == MusicSection.allCases.count)
        #expect(Set(symbols).count == MusicSection.allCases.count)
    }

    @Test func titlesAndSymbolsMatchTheDesign() {
        #expect(MusicSection.allCases.map(\.title) == ["Now Playing", "Playlists", "Liked", "Search", "Queue"])
        #expect(MusicSection.allCases.map(\.symbol) == ["play.circle.fill", "music.note.list", "heart.fill", "magnifyingglass", "list.bullet"])
    }
}

@Suite struct SpotifyPlaylistIDTests {
    @Test func theIDComesFromTheURI() {
        #expect(SpotifyPlaylist(uri: "spotify:playlist:37i9dQZF1DX", name: "x").spotifyID == "37i9dQZF1DX")
    }

    @Test func aURIWithoutColonsIsItsOwnID() {
        #expect(SpotifyPlaylist(uri: "abc123", name: "x").spotifyID == "abc123")
    }
}
