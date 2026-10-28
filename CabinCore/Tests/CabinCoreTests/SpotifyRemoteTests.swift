import Foundation
import Testing
@testable import CabinCore

/// Spotify's web service sometimes answers "nothing is playing" while the Spotify app on this iPhone is playing (it did, right
/// after the hand-over). While Cabin Dash is connected to that app, the app's own word is used for what is playing here.
@Suite struct SpotifyRemotePlaybackTests {
    private func remote(
        uri: String = "spotify:track:t", title: String = "Acquainted", artist: String = "The Weeknd", paused: Bool = false,
        advertisement: Bool = false
    ) -> RemotePlayback {
        RemotePlayback(
            uri: uri, title: title, artist: artist, album: "Beauty Behind the Madness", duration: 347, position: 12,
            isPaused: paused, isShuffling: true, contextURI: "spotify:playlist:p", isAdvertisement: advertisement
        )
    }

    private func web(uri: String = "spotify:track:t", art: URL? = URL(string: "https://i.scdn.co/image/a")) -> NowPlaying {
        NowPlaying(
            title: "Acquainted", subtitle: "The Weeknd", artworkURL: art, isPlaying: true, deviceName: "Xiaomi TV Box",
            uri: uri, albumURI: "spotify:album:a"
        )
    }

    @Test func theWebServicesAnswerWinsWhenItHasOne() {
        let shown = SpotifyPlayback.merged(web: web(), remote: remote(), phoneName: "Evan's iPhone", previous: nil)
        #expect(shown == web())
    }

    @Test func nothingFromEitherIsNothing() {
        #expect(SpotifyPlayback.merged(web: nil, remote: nil, phoneName: "Evan's iPhone", previous: nil) == nil)
    }

    @Test func aSpotifyAppWithNothingLoadedIsNothing() {
        let empty = remote(uri: "")
        #expect(SpotifyPlayback.merged(web: nil, remote: empty, phoneName: "Evan's iPhone", previous: nil) == nil)
    }

    @Test func theSpotifyAppFillsInWhenTheWebServiceSaysNothing() throws {
        let shown = try #require(SpotifyPlayback.merged(web: nil, remote: remote(), phoneName: "Evan's iPhone", previous: nil))
        #expect(shown.title == "Acquainted")
        #expect(shown.subtitle == "The Weeknd")
        #expect(shown.album == "Beauty Behind the Madness")
        #expect(shown.uri == "spotify:track:t")
        #expect(shown.contextURI == "spotify:playlist:p")
        #expect(shown.duration == 347)
        #expect(shown.progress == 12)
        #expect(shown.isPlaying)
        #expect(shown.shuffle)
        #expect(shown.deviceName == "Evan's iPhone")
    }

    @Test func aPausedSpotifyAppShowsAPausedSong() throws {
        let shown = try #require(SpotifyPlayback.merged(web: nil, remote: remote(paused: true), phoneName: nil, previous: nil))
        #expect(!shown.isPlaying)
    }

    @Test func withoutAPhoneNameItIsThisIPhone() throws {
        let shown = try #require(SpotifyPlayback.merged(web: nil, remote: remote(), phoneName: nil, previous: nil))
        #expect(shown.deviceName == "This iPhone")
    }

    @Test func thePictureAlreadyKnownForTheSameSongIsKept() throws {
        let known = web()
        let shown = try #require(SpotifyPlayback.merged(web: nil, remote: remote(), phoneName: nil, previous: known))
        #expect(shown.artworkURL == known.artworkURL)
        #expect(shown.albumURI == "spotify:album:a")
    }

    @Test func aPictureForAnotherSongIsNotBorrowed() throws {
        let other = web(uri: "spotify:track:other")
        let shown = try #require(SpotifyPlayback.merged(web: nil, remote: remote(), phoneName: nil, previous: other))
        #expect(shown.artworkURL == nil)
        #expect(shown.albumURI == nil)
    }

    @Test func shuffleAndRepeatAreOffLimitsBecauseTheyGoThroughTheWebService() throws {
        let shown = try #require(SpotifyPlayback.merged(web: nil, remote: remote(), phoneName: nil, previous: nil))
        #expect(!shown.canShuffle)
        #expect(!shown.canRepeat)
        #expect(shown.canSkipNext)
        #expect(shown.canSkipPrevious)
        #expect(shown.canSeek)
    }

    @Test func anAdvertisementCannotBeSkippedOrSoughtThrough() throws {
        let shown = try #require(SpotifyPlayback.merged(web: nil, remote: remote(advertisement: true), phoneName: nil, previous: nil))
        #expect(!shown.canSkipNext)
        #expect(!shown.canSkipPrevious)
        #expect(!shown.canSeek)
    }
}
