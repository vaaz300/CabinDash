import Foundation
import Testing
@testable import CabinCore

@Suite struct SpotifyDevicePickTests {
    private func device(_ id: String, restricted: Bool = false, active: Bool = false) -> SpotifyDevice {
        SpotifyDevice(id: id, name: "Device \(id)", type: "Speaker", isActive: active, isRestricted: restricted)
    }

    @Test func noDevicesGivesNoTarget() {
        #expect(SpotifyDevices.autoTarget([]) == nil)
    }

    @Test func oneDeviceIsTheTarget() {
        #expect(SpotifyDevices.autoTarget([device("a")])?.id == "a")
    }

    @Test func twoDevicesGiveNoTarget() {
        // Never guess between a phone and a speaker: the person picks.
        #expect(SpotifyDevices.autoTarget([device("a"), device("b")]) == nil)
        #expect(SpotifyDevices.autoTarget([device("a"), device("b", active: true)]) == nil)
    }

    @Test func aRestrictedDeviceDoesNotCount() {
        #expect(SpotifyDevices.autoTarget([device("a", restricted: true), device("b")])?.id == "b")
    }

    @Test func onlyRestrictedGivesNone() {
        #expect(SpotifyDevices.autoTarget([device("a", restricted: true)]) == nil)
        #expect(SpotifyDevices.autoTarget([device("a", restricted: true), device("b", restricted: true)]) == nil)
    }
}

@Suite struct SpotifyLinkTests {
    private func addresses(_ uri: String?) -> [String] {
        SpotifyLink.openURLs(forURI: uri).map(\.absoluteString)
    }

    private let home = ["spotify://", "https://open.spotify.com"]

    @Test func theLabelIsSpotifysRequiredWording() {
        #expect(SpotifyLink.label == "Open Spotify")
    }

    @Test func trackLinkOpensTheTrack() {
        #expect(addresses("spotify:track:abc123") == ["spotify:track:abc123", "https://open.spotify.com/track/abc123"])
    }

    @Test func playlistLinkAndAlbumLink() {
        #expect(addresses("spotify:playlist:p1") == ["spotify:playlist:p1", "https://open.spotify.com/playlist/p1"])
        #expect(addresses("spotify:album:alb1") == ["spotify:album:alb1", "https://open.spotify.com/album/alb1"])
    }

    @Test func episodeShowAndArtistLinks() {
        #expect(addresses("spotify:episode:e1") == ["spotify:episode:e1", "https://open.spotify.com/episode/e1"])
        #expect(addresses("spotify:show:s1") == ["spotify:show:s1", "https://open.spotify.com/show/s1"])
        #expect(addresses("spotify:artist:ar1") == ["spotify:artist:ar1", "https://open.spotify.com/artist/ar1"])
    }

    @Test func unknownOrMissingURIOpensSpotifyItself() {
        #expect(addresses(nil) == home)
        #expect(addresses("") == home)
        #expect(addresses("not a uri") == home)
        #expect(addresses("spotify:user:someone") == home)
        #expect(addresses("spotify:track:") == home)
        #expect(addresses("spotify:track:a:b") == home)
        #expect(addresses("https://example.com/track/abc") == home)
    }

    @Test func aLocalFileURIOpensSpotifyItself() {
        #expect(addresses("spotify:local:::Demo:180") == home)
    }

    @Test func anIdWithOddCharactersOpensSpotifyItself() {
        #expect(addresses("spotify:track:ab/../cd") == home)
        #expect(addresses("spotify:track:ab cd") == home)
    }
}
