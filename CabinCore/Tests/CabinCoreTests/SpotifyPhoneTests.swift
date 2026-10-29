import Foundation
import Testing
@testable import CabinCore

// Music on this iPhone goes through one channel: the connection to the Spotify app (Spotify's iOS SDK). Spotify's web
// service is used for browsing, and for a TV or speaker the person picked. These tests pin down which of the two Now Playing
// shows, where the buttons send their commands, how the Spotify app's word becomes Now Playing, and what a tap on Play asks
// the Spotify app to do.

private func app(
    uri: String = "spotify:track:t", paused: Bool = false, repeatMode: SpotifyRepeat = .off
) -> RemotePlayback {
    RemotePlayback(
        uri: uri, title: "Acquainted", artist: "The Weeknd", album: "Beauty Behind the Madness", duration: 347, position: 12,
        isPaused: paused, isShuffling: true, repeatMode: repeatMode, contextURI: "spotify:playlist:p"
    )
}

private func web(on device: String, type: String, playing: Bool = true, uri: String = "spotify:track:w") -> NowPlaying {
    NowPlaying(title: "Elsewhere", isPlaying: playing, deviceName: device, deviceType: type, uri: uri)
}

private let phoneName = "Evan's iPhone"

@Suite struct SpotifyPhoneSourceTests {
    @Test func theConnectedSpotifyAppIsTheSource() {
        let source = SpotifyPhone.source(otherDeviceChosen: false, connected: true, app: app(), web: nil, phoneName: phoneName)
        #expect(source == .phone(app(), live: true))
    }

    @Test func theConnectedAppWinsOverTheWebServiceAboutThisPhone() {
        let stale = web(on: phoneName, type: "Smartphone")
        let source = SpotifyPhone.source(otherDeviceChosen: false, connected: true, app: app(), web: stale, phoneName: phoneName)
        #expect(source == .phone(app(), live: true))
    }

    @Test func musicPlayingOnAnotherDeviceWinsOverAPausedPhone() {
        let tv = web(on: "Xiaomi TV Box", type: "TV")
        let source = SpotifyPhone.source(otherDeviceChosen: false, connected: true, app: app(paused: true), web: tv, phoneName: phoneName)
        #expect(source == .otherDevice(tv))
    }

    @Test func musicPlayingOnAnotherDeviceIsShownWhenNotConnected() {
        let tv = web(on: "Xiaomi TV Box", type: "TV")
        let source = SpotifyPhone.source(otherDeviceChosen: false, connected: false, app: app(), web: tv, phoneName: phoneName)
        #expect(source == .otherDevice(tv))
    }

    @Test func theWebServicesViewOfThisPhoneIsShownWhenNotConnected() {
        let here = web(on: phoneName, type: "Smartphone")
        let source = SpotifyPhone.source(otherDeviceChosen: false, connected: false, app: app(), web: here, phoneName: phoneName)
        #expect(source == .phoneByWeb(here))
    }

    @Test func theLastSongStaysOnScreenAfterTheConnectionEnds() {
        // Spotify ends the connection soon after a pause; the song used to vanish into "Nothing is playing".
        let source = SpotifyPhone.source(otherDeviceChosen: false, connected: false, app: app(paused: true), web: nil, phoneName: phoneName)
        #expect(source == .phone(app(paused: true), live: false))
    }

    @Test func aPausedSongElsewhereIsShownOnlyWhenThePhoneHasNone() {
        let pausedTV = web(on: "Xiaomi TV Box", type: "TV", playing: false)
        let withSong = SpotifyPhone.source(otherDeviceChosen: false, connected: false, app: app(), web: pausedTV, phoneName: phoneName)
        #expect(withSong == .phone(app(), live: false))
        let withoutSong = SpotifyPhone.source(otherDeviceChosen: false, connected: false, app: nil, web: pausedTV, phoneName: phoneName)
        #expect(withoutSong == .otherDevice(pausedTV))
    }

    @Test func nothingAnywhereIsNothing() {
        #expect(SpotifyPhone.source(otherDeviceChosen: false, connected: true, app: nil, web: nil, phoneName: phoneName) == .nothing)
    }

    @Test func aSpotifyAppWithNoSongLoadedDoesNotCount() {
        let empty = RemotePlayback(uri: "", title: "")
        #expect(SpotifyPhone.source(otherDeviceChosen: false, connected: true, app: empty, web: nil, phoneName: phoneName) == .nothing)
    }

    @Test func aChosenTVOrSpeakerOnlyListensToTheWebService() {
        let tv = web(on: "Xiaomi TV Box", type: "TV")
        #expect(SpotifyPhone.source(otherDeviceChosen: true, connected: true, app: app(), web: tv, phoneName: phoneName) == .otherDevice(tv))
        #expect(SpotifyPhone.source(otherDeviceChosen: true, connected: true, app: app(), web: nil, phoneName: phoneName) == .nothing)
    }

    @Test func aSmartphoneIsThisPhoneWhenItsNameIsNotKnownYet() {
        #expect(SpotifyPhone.isThisPhone(web(on: "iPhone", type: "Smartphone"), phoneName: nil))
    }

    @Test func anotherNamedPhoneIsNotThisOne() {
        #expect(!SpotifyPhone.isThisPhone(web(on: "Someone's iPhone", type: "Smartphone"), phoneName: phoneName))
    }

    @Test func aTVIsNeverThisPhone() {
        #expect(!SpotifyPhone.isThisPhone(web(on: phoneName, type: "TV"), phoneName: phoneName))
    }
}

/// The buttons go to the device whose music is on screen: the Spotify app for this phone, the web service for anything else.
@Suite struct SpotifyPhoneSteeringTests {
    @Test func thePhonesOwnSongIsSteeredThroughTheSpotifyAppEvenAfterTheConnectionEnded() {
        // A press then makes the connection again, or starts Spotify, which is Spotify's way back after a pause.
        #expect(SpotifyPhone.steersPhone(.phone(app(), live: false), otherDeviceChosen: false, connected: false))
        #expect(SpotifyPhone.steersPhone(.phone(app(), live: true), otherDeviceChosen: false, connected: true))
    }

    @Test func aPlayingPhoneSeenOnlyByTheWebServiceIsSteeredByIt() {
        let here = web(on: phoneName, type: "Smartphone")
        #expect(SpotifyPhone.steersPhone(.phoneByWeb(here), otherDeviceChosen: false, connected: true))
        #expect(!SpotifyPhone.steersPhone(.phoneByWeb(here), otherDeviceChosen: false, connected: false))
    }

    @Test func aPausedPhoneSeenOnlyByTheWebServiceIsWokenThroughTheSpotifyApp() {
        // Paused, the Spotify app goes to sleep and the web service cannot wake it; only starting the app can.
        let pausedHere = web(on: phoneName, type: "Smartphone", playing: false)
        #expect(SpotifyPhone.steersPhone(.phoneByWeb(pausedHere), otherDeviceChosen: false, connected: false))
    }

    @Test func musicOnAnotherDeviceIsSteeredByTheWebService() {
        #expect(!SpotifyPhone.steersPhone(.otherDevice(web(on: "Xiaomi TV Box", type: "TV")), otherDeviceChosen: false, connected: true))
    }

    @Test func aChosenDeviceIsAlwaysSteeredByTheWebService() {
        #expect(!SpotifyPhone.steersPhone(.nothing, otherDeviceChosen: true, connected: true))
        #expect(!SpotifyPhone.steersPhone(.phone(app(), live: true), otherDeviceChosen: true, connected: true))
    }
}

@Suite struct SpotifyPhoneNowPlayingTests {
    private let art = TrackArt(uri: "spotify:track:t", artworkURL: URL(string: "https://i.scdn.co/image/a"), albumURI: "spotify:album:a")

    @Test func aLiveSongShowsWhatTheAppSays() {
        let shown = SpotifyPhone.nowPlaying(from: app(repeatMode: .context), live: true, deviceName: phoneName, art: art)
        #expect(shown.title == "Acquainted")
        #expect(shown.subtitle == "The Weeknd")
        #expect(shown.album == "Beauty Behind the Madness")
        #expect(shown.uri == "spotify:track:t")
        #expect(shown.trackID == "t")
        #expect(shown.duration == 347)
        #expect(shown.progress == 12)
        #expect(shown.isPlaying)
        #expect(shown.shuffle)
        #expect(shown.repeatMode == .context)
        #expect(shown.deviceName == phoneName)
        #expect(shown.contextURI == "spotify:playlist:p")
        #expect(shown.artworkURL == art.artworkURL)
        #expect(shown.albumURI == "spotify:album:a")
    }

    @Test func aSongWhoseConnectionHasEndedIsShownPaused() {
        #expect(!SpotifyPhone.nowPlaying(from: app(), live: false, deviceName: phoneName, art: nil).isPlaying)
        #expect(!SpotifyPhone.nowPlaying(from: app(paused: true), live: true, deviceName: phoneName, art: nil).isPlaying)
    }

    @Test func thePictureIsOnlyUsedForTheSongItBelongsTo() {
        let other = TrackArt(uri: "spotify:track:other", artworkURL: URL(string: "https://i.scdn.co/image/b"), albumURI: nil)
        let shown = SpotifyPhone.nowPlaying(from: app(), live: true, deviceName: phoneName, art: other)
        #expect(shown.artworkURL == nil)
        #expect(shown.albumURI == nil)
    }

    @Test func whatTheAppAllowsIsAllowed() {
        let shown = SpotifyPhone.nowPlaying(from: app(), live: true, deviceName: phoneName, art: nil)
        #expect(shown.canSkipNext && shown.canSkipPrevious && shown.canSeek && shown.canShuffle && shown.canRepeat)
    }

    @Test func whatTheAppForbidsIsDimmed() {
        var limited = app()
        limited.canSkipNext = false
        limited.canSkipPrevious = false
        limited.canSeek = false
        limited.canToggleShuffle = false
        limited.canRepeatTrack = false
        limited.canRepeatContext = false
        let shown = SpotifyPhone.nowPlaying(from: limited, live: true, deviceName: phoneName, art: nil)
        #expect(!shown.canSkipNext)
        #expect(!shown.canSkipPrevious)
        #expect(!shown.canSeek)
        #expect(!shown.canShuffle)
        #expect(!shown.canRepeat)
    }

    @Test func anAdvertisementCannotBeSkippedOrSought() {
        var ad = app()
        ad.isAdvertisement = true
        let shown = SpotifyPhone.nowPlaying(from: ad, live: true, deviceName: phoneName, art: nil)
        #expect(!shown.canSkipNext)
        #expect(!shown.canSkipPrevious)
        #expect(!shown.canSeek)
    }

    @Test func anEpisodeHasNoTrackID() {
        let episode = SpotifyPhone.nowPlaying(from: app(uri: "spotify:episode:e"), live: true, deviceName: phoneName, art: nil)
        #expect(episode.trackID == nil)
    }
}

/// A tap on Play becomes one request to the Spotify app. When the app has to be started first, Spotify's SDK can only be
/// given one address, so it is given the tapped song (the right music starts at once) and the rest is done through the
/// connection once Spotify is back.
@Suite struct SpotifyPhonePlanTests {
    @Test func aPlaylistsPlayButtonPlaysItFromTheStartInOrder() throws {
        let plan = try #require(SpotifyPhone.plan(for: .context(uri: "spotify:playlist:p", startAtURI: nil), shuffled: false, index: nil, likedCollection: nil))
        #expect(plan.start == .uri("spotify:playlist:p"))
        #expect(plan.shuffle == false)
        #expect(plan.handOverURI == "spotify:playlist:p")
        #expect(plan.afterHandOver == nil)
    }

    @Test func theShuffleButtonSwitchesShuffleOn() throws {
        let plan = try #require(SpotifyPhone.plan(for: .context(uri: "spotify:playlist:p", startAtURI: nil), shuffled: true, index: nil, likedCollection: nil))
        #expect(plan.shuffle == true)
    }

    @Test func aSongInAPlaylistPlaysThePlaylistFromThatSong() throws {
        let plan = try #require(SpotifyPhone.plan(for: .context(uri: "spotify:playlist:p", startAtURI: "spotify:track:t"), shuffled: false, index: 4, likedCollection: nil))
        #expect(plan.start == .item(context: "spotify:playlist:p", index: 4, song: "spotify:track:t"))
        #expect(plan.shuffle == nil)
        #expect(plan.handOverURI == "spotify:track:t")
        #expect(plan.afterHandOver == .item(context: "spotify:playlist:p", index: 4, song: "spotify:track:t"))
    }

    @Test func aSongInAnAlbumHasItsPlaceLookedUp() throws {
        let plan = try #require(SpotifyPhone.plan(for: .context(uri: "spotify:album:a", startAtURI: "spotify:track:t"), shuffled: false, index: nil, likedCollection: nil))
        #expect(plan.start == .lookUp(context: "spotify:album:a", song: "spotify:track:t"))
        #expect(plan.handOverURI == "spotify:track:t")
    }

    // Your test: skipping a Liked song played Spotify's own picks, so the Spotify app did not play Liked Songs as a list.
    // Liked Songs has two addresses; both are tried, and if neither is accepted Cabin Dash plays the list itself.

    @Test func aLikedSongTriesBothLikedSongsAddressesAndKeepsTheListAsTheLastResort() throws {
        let plan = try #require(SpotifyPhone.plan(
            for: .uris(["spotify:track:t", "spotify:track:u"]), shuffled: false, index: 7, likedCollection: "spotify:user:evan:collection"
        ))
        #expect(plan.start == .item(context: "spotify:user:evan:collection", index: 7, song: "spotify:track:t"))
        #expect(plan.otherContexts == ["spotify:collection:tracks"])
        #expect(plan.songs == ["spotify:track:t", "spotify:track:u"])
        #expect(plan.handOverURI == "spotify:track:t")
    }

    @Test func withoutTheAccountsAddressLikedSongsGeneralAddressIsTried() throws {
        let plan = try #require(SpotifyPhone.plan(for: .uris(["spotify:track:t", "spotify:track:u"]), shuffled: false, index: 7, likedCollection: nil))
        #expect(plan.start == .item(context: SpotifyPhone.likedSongsAddress, index: 7, song: "spotify:track:t"))
        #expect(plan.otherContexts.isEmpty)
        #expect(plan.songs == ["spotify:track:t", "spotify:track:u"])
    }

    @Test func aListWithoutAKnownPlaceIsPlayedByCabinDashItself() throws {
        let plan = try #require(SpotifyPhone.plan(for: .uris(["spotify:track:t", "spotify:track:u"]), shuffled: false, index: nil, likedCollection: nil))
        #expect(plan.start == .uri("spotify:track:t"))
        #expect(plan.songs == ["spotify:track:t", "spotify:track:u"])
    }

    @Test func aSingleSongPlaysAlone() throws {
        let plan = try #require(SpotifyPhone.plan(for: .uris(["spotify:track:t"]), shuffled: false, index: nil, likedCollection: nil))
        #expect(plan.start == .uri("spotify:track:t"))
        #expect(plan.shuffle == nil)
        #expect(plan.songs.isEmpty)
    }

    @Test func playlistsAndAlbumsNeedNoOtherAddressOrList() throws {
        let plan = try #require(SpotifyPhone.plan(for: .context(uri: "spotify:playlist:p", startAtURI: "spotify:track:t"), shuffled: false, index: 2, likedCollection: nil))
        #expect(plan.otherContexts.isEmpty)
        #expect(plan.songs.isEmpty)
    }

    @Test func nothingToPlayIsNoPlan() {
        #expect(SpotifyPhone.plan(for: .uris([]), shuffled: false, index: nil, likedCollection: nil) == nil)
    }

    @Test func likedSongsHaveTheirOwnAddresses() {
        #expect(SpotifyPhone.likedCollectionURI(userID: "evan") == "spotify:user:evan:collection")
        #expect(SpotifyPhone.likedSongsAddress == "spotify:collection:tracks")
    }
}

@Suite struct SpotifyTrackArtTests {
    @Test func theCatalogueLookupAsksForOneTrack() {
        let request = SpotifyEndpoint.track(id: "abc123")
        #expect(request.method == "GET")
        #expect(request.path == "/v1/tracks/abc123")
    }

    @Test func readsTheLargestAlbumPictureAndTheAlbum() throws {
        let json = """
        { "uri": "spotify:track:abc123", "album": { "uri": "spotify:album:a",
          "images": [ { "url": "https://example.com/small.jpg", "width": 64 }, { "url": "https://example.com/large.jpg", "width": 640 } ] } }
        """
        let art = try #require(SpotifyLibrary.parseTrackArt(Data(json.utf8)))
        #expect(art.uri == "spotify:track:abc123")
        #expect(art.artworkURL == URL(string: "https://example.com/large.jpg"))
        #expect(art.albumURI == "spotify:album:a")
    }

    @Test func aTrackWithoutPicturesHasNone() throws {
        let art = try #require(SpotifyLibrary.parseTrackArt(Data(#"{ "uri": "spotify:track:abc123" }"#.utf8)))
        #expect(art.artworkURL == nil)
    }

    @Test func somethingElseIsNotRead() {
        #expect(SpotifyLibrary.parseTrackArt(Data("nope".utf8)) == nil)
    }
}

@Suite struct SpotifyPlaybackDeviceTypeTests {
    @Test func theDeviceTypeIsRead() throws {
        let json = #"{ "device": { "name": "Evan's iPhone", "type": "Smartphone" }, "is_playing": true, "item": { "name": "Song", "uri": "spotify:track:t" } }"#
        let playing = try #require(SpotifyPlayback.parse(Data(json.utf8)))
        #expect(playing.deviceType == "Smartphone")
    }
}

/// A list Cabin Dash plays itself, one song after another, when the Spotify app will not play it as a whole. Cabin Dash
/// watches the Spotify app: when it moves past the run's song to one of its own picks, the run's next song is played.
@Suite struct SongRunTests {
    private let a = "spotify:track:a", b = "spotify:track:b", c = "spotify:track:c"

    @Test func aRunNeedsASongToStartFrom() {
        #expect(SongRun(songs: [], start: 0) == nil)
        #expect(SongRun(songs: [a], start: 3) == nil)
    }

    @Test func itStartsAtTheGivenSong() throws {
        let run = try #require(SongRun(songs: [a, b, c], start: 1))
        #expect(run.current == b)
        #expect(!run.isShuffled)
    }

    @Test func stayingOnTheSongChangesNothing() throws {
        var run = try #require(SongRun(songs: [a, b, c]))
        #expect(run.spotifyMoved(to: a) == .keep)
        #expect(run.current == a)
    }

    @Test func movingToAnotherSongOfTheRunIsFollowed() throws {
        var run = try #require(SongRun(songs: [a, b, c]))
        #expect(run.spotifyMoved(to: c) == .keep)
        #expect(run.current == c)
    }

    @Test func whenSpotifyMovesOnToItsOwnPickTheNextSongOfTheRunPlays() throws {
        var run = try #require(SongRun(songs: [a, b, c]))
        #expect(run.spotifyMoved(to: "spotify:track:radio") == .play(b))
        #expect(run.current == b)
    }

    @Test func pastTheLastSongTheRunEnds() throws {
        var run = try #require(SongRun(songs: [a, b], start: 1))
        #expect(run.spotifyMoved(to: "spotify:track:radio") == .stop)
    }

    @Test func repeatAllGoesBackToTheFirstSong() throws {
        var run = try #require(SongRun(songs: [a, b], start: 1))
        run.repeatsAll = true
        #expect(run.spotifyMoved(to: "spotify:track:radio") == .play(a))
        #expect(run.advance() == b)
    }

    @Test func nextGoesThroughTheRunAndEndsAfterTheLastSong() throws {
        var run = try #require(SongRun(songs: [a, b]))
        #expect(run.advance() == b)
        #expect(run.advance() == nil)
        #expect(run.current == b)
    }

    @Test func previousRestartsASongThatHasPlayedForMoreThanThreeSeconds() throws {
        var run = try #require(SongRun(songs: [a, b], start: 1))
        #expect(run.back(position: 12) == .restart)
        #expect(run.current == b)
    }

    @Test func previousEarlyInASongGoesToTheOneBefore() throws {
        var run = try #require(SongRun(songs: [a, b], start: 1))
        #expect(run.back(position: 1) == .play(a))
        #expect(run.current == a)
    }

    @Test func previousOnTheFirstSongRestartsIt() throws {
        var run = try #require(SongRun(songs: [a, b]))
        #expect(run.back(position: 1) == .restart)
    }

    @Test func shufflingKeepsWhatHasPlayedAndMixesTheRest() throws {
        let songs = (0..<30).map { "spotify:track:\($0)" }
        var run = try #require(SongRun(songs: songs, start: 4))
        run.shuffle(true)
        // Your retest: the shuffle button lit, then went dark on the next song. In Liked Songs played by Cabin Dash itself,
        // shuffle belongs to the list, which says so, rather than to the Spotify app.
        #expect(run.isShuffled)
        #expect(run.current == songs[4])
        #expect(Array(run.songs.prefix(5)) == Array(songs.prefix(5)))
        #expect(Set(run.songs) == Set(songs))
        #expect(run.songs.count == songs.count)
    }

    @Test func unshufflingPutsTheListBackInOrderFromTheCurrentSong() throws {
        let songs = (0..<30).map { "spotify:track:\($0)" }
        var run = try #require(SongRun(songs: songs, start: 4))
        run.shuffle(true)
        _ = run.advance()
        let playing = run.current
        run.shuffle(false)
        #expect(!run.isShuffled)
        #expect(run.songs == songs)
        #expect(run.current == playing)
    }
}
