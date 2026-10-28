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

    private func web(
        uri: String = "spotify:track:t", art: URL? = URL(string: "https://i.scdn.co/image/a"), device: String = "Xiaomi TV Box",
        progress: TimeInterval = 100
    ) -> NowPlaying {
        NowPlaying(
            title: "Acquainted", subtitle: "The Weeknd", artworkURL: art, progress: progress, isPlaying: true, deviceName: device,
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

    // While Cabin Dash is connected to the Spotify app, the app knows better than the web service what this phone is doing:
    // the web service kept saying "playing" for a phone whose Spotify app had stopped, so the bar moved and nothing played.

    @Test func theAppIsRightAboutThePhoneWhenBothNameTheSameSong() throws {
        let shown = try #require(SpotifyPlayback.merged(
            web: web(device: "Evan's iPhone"), remote: remote(paused: true), phoneName: "Evan's iPhone", previous: nil
        ))
        #expect(!shown.isPlaying)
        #expect(shown.progress == 12)
        #expect(shown.artworkURL == web().artworkURL)
        #expect(shown.title == "Acquainted")
    }

    @Test func theAppIsRightWhenThePhoneHasMovedOnToAnotherSong() throws {
        let stale = web(uri: "spotify:track:old", device: "Evan's iPhone")
        let shown = try #require(SpotifyPlayback.merged(web: stale, remote: remote(), phoneName: "Evan's iPhone", previous: stale))
        #expect(shown.uri == "spotify:track:t")
        #expect(shown.deviceName == "Evan's iPhone")
        #expect(shown.artworkURL == nil)
    }

    @Test func theWebServiceKeepsItsWordWhenThePhoneIsNotKnown() {
        let onThePhone = web(device: "Evan's iPhone")
        #expect(SpotifyPlayback.merged(web: onThePhone, remote: remote(paused: true), phoneName: nil, previous: nil) == onThePhone)
    }

    @Test func theWebServiceKeepsItsWordWhenTheAppSaysNothing() {
        let onThePhone = web(device: "Evan's iPhone")
        #expect(SpotifyPlayback.merged(web: onThePhone, remote: nil, phoneName: "Evan's iPhone", previous: nil) == onThePhone)
        #expect(SpotifyPlayback.merged(web: onThePhone, remote: remote(uri: ""), phoneName: "Evan's iPhone", previous: nil) == onThePhone)
    }

    @Test func theWebServiceKeepsItsWordForMusicOnAnotherDeviceEvenIfTheAppHasAPausedSong() {
        #expect(SpotifyPlayback.merged(web: web(), remote: remote(paused: true), phoneName: "Evan's iPhone", previous: nil) == web())
    }
}

/// Play, pause, skip and seek go to the Spotify app when it is the better informed: connected, and either the only source or
/// the one Spotify's web service also names as playing on this phone. Music on a TV or speaker is never steered through the phone.
@Suite struct SpotifyControlRouteTests {
    private let song = RemotePlayback(uri: "spotify:track:t", title: "Acquainted")

    private func web(on device: String) -> NowPlaying {
        NowPlaying(title: "Acquainted", isPlaying: true, deviceName: device, uri: "spotify:track:t")
    }

    @Test func theAppAloneIsEnough() {
        #expect(SpotifyPlayback.controlsGoToApp(web: nil, remote: song, phoneName: "Evan's iPhone", connected: true))
    }

    @Test func theAppIsUsedWhenTheWebServiceNamesThePhone() {
        #expect(SpotifyPlayback.controlsGoToApp(web: web(on: "Evan's iPhone"), remote: song, phoneName: "Evan's iPhone", connected: true))
    }

    @Test func aTVOrSpeakerIsNeverSteeredThroughThePhone() {
        #expect(!SpotifyPlayback.controlsGoToApp(web: web(on: "Xiaomi TV Box"), remote: song, phoneName: "Evan's iPhone", connected: true))
    }

    @Test func withoutTheConnectionTheWebServiceIsUsed() {
        #expect(!SpotifyPlayback.controlsGoToApp(web: nil, remote: song, phoneName: "Evan's iPhone", connected: false))
    }

    @Test func withoutASongInTheAppTheWebServiceIsUsed() {
        #expect(!SpotifyPlayback.controlsGoToApp(web: nil, remote: nil, phoneName: "Evan's iPhone", connected: true))
        #expect(!SpotifyPlayback.controlsGoToApp(web: nil, remote: RemotePlayback(uri: "", title: ""), phoneName: "Evan's iPhone", connected: true))
    }

    @Test func aWebAnswerWithNoKnownPhoneIsNotGuessedAbout() {
        #expect(!SpotifyPlayback.controlsGoToApp(web: web(on: "Evan's iPhone"), remote: song, phoneName: nil, connected: true))
    }
}
