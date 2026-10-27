import Foundation
import Testing
@testable import CabinCore

private let trackJSON = """
{
  "device": { "name": "Test iPhone" },
  "is_playing": true,
  "progress_ms": 61500,
  "item": {
    "id": "abc123",
    "name": "Song Title",
    "duration_ms": 200000,
    "artists": [ { "name": "First Artist" }, { "name": "Second Artist" } ],
    "album": {
      "name": "Album Name",
      "images": [
        { "url": "https://example.com/small.jpg", "width": 64, "height": 64 },
        { "url": "https://example.com/large.jpg", "width": 640, "height": 640 },
        { "url": "https://example.com/medium.jpg", "width": 300, "height": 300 }
      ]
    }
  }
}
"""

private let episodeJSON = """
{
  "is_playing": false,
  "progress_ms": 1000,
  "item": {
    "id": "ep1",
    "name": "Episode Title",
    "duration_ms": 3600000,
    "show": { "name": "The Show", "images": [ { "url": "https://example.com/show.jpg", "width": 300 } ] },
    "images": [ { "url": "https://example.com/episode.jpg", "width": 640 } ]
  }
}
"""

@Suite struct SpotifyPlaybackTests {
    @Test func readsATrack() throws {
        let playing = try #require(SpotifyPlayback.parse(Data(trackJSON.utf8)))
        #expect(playing.title == "Song Title")
        #expect(playing.subtitle == "First Artist, Second Artist")
        #expect(playing.album == "Album Name")
        #expect(playing.trackID == "abc123")
        #expect(playing.isPlaying)
        #expect(playing.deviceName == "Test iPhone")
        #expect(abs(playing.duration - 200) < 0.0001)
        #expect(abs(playing.progress - 61.5) < 0.0001)
    }

    @Test func picksTheLargestPicture() throws {
        let playing = try #require(SpotifyPlayback.parse(Data(trackJSON.utf8)))
        #expect(playing.artworkURL?.absoluteString == "https://example.com/large.jpg")
    }

    @Test func readsAPodcastEpisode() throws {
        let playing = try #require(SpotifyPlayback.parse(Data(episodeJSON.utf8)))
        #expect(playing.title == "Episode Title")
        #expect(playing.subtitle == "The Show")
        #expect(playing.album == "")
        #expect(!playing.isPlaying)
        #expect(playing.artworkURL?.absoluteString == "https://example.com/episode.jpg")
        #expect(playing.deviceName == nil)
    }

    @Test func nothingPlayingGivesNil() {
        #expect(SpotifyPlayback.parse(Data()) == nil)
        #expect(SpotifyPlayback.parse(Data("not json".utf8)) == nil)
        #expect(SpotifyPlayback.parse(Data(#"{"is_playing":false,"item":null}"#.utf8)) == nil)
        #expect(SpotifyPlayback.parse(Data("[]".utf8)) == nil)
    }

    @Test func aTrackWithoutPicturesStillParses() throws {
        let json = #"{"is_playing":true,"progress_ms":0,"item":{"name":"Bare","duration_ms":1000,"artists":[],"album":{"name":"A","images":[]}}}"#
        let playing = try #require(SpotifyPlayback.parse(Data(json.utf8)))
        #expect(playing.artworkURL == nil)
        #expect(playing.subtitle == "")
    }

    @Test func fractionStaysBetweenZeroAndOne() {
        #expect(NowPlaying(title: "x", duration: 100, progress: 25).fraction == 0.25)
        #expect(NowPlaying(title: "x", duration: 100, progress: 500).fraction == 1)
        #expect(NowPlaying(title: "x", duration: 100, progress: -5).fraction == 0)
        #expect(NowPlaying(title: "x", duration: 0, progress: 10).fraction == 0)
    }
}

private func playerJSON(
    shuffle: String = #""shuffle_state": true,"#,
    repeatState: String = #""repeat_state": "context","#,
    context: String = #""context": { "uri": "spotify:playlist:p1", "type": "playlist" },"#,
    actions: String = #""actions": { "disallows": { "skipping_prev": true, "resuming": true } },"#
) -> Data {
    Data("""
    {
      "device": { "name": "Test iPhone" },
      "is_playing": true,
      \(shuffle)
      \(repeatState)
      \(context)
      \(actions)
      "progress_ms": 1000,
      "item": {
        "id": "abc123",
        "uri": "spotify:track:abc123",
        "name": "Song Title",
        "duration_ms": 200000,
        "artists": [ { "name": "First Artist" } ],
        "album": { "name": "Album Name", "uri": "spotify:album:alb1", "images": [] }
      }
    }
    """.utf8)
}

@Suite struct SpotifyPlaybackStateTests {
    @Test func readsShuffleRepeatAndContext() throws {
        let playing = try #require(SpotifyPlayback.parse(playerJSON()))
        #expect(playing.shuffle)
        #expect(playing.repeatMode == .context)
        #expect(playing.contextURI == "spotify:playlist:p1")
    }

    @Test func readsTheTrackAndAlbumURIs() throws {
        let playing = try #require(SpotifyPlayback.parse(playerJSON()))
        #expect(playing.uri == "spotify:track:abc123")
        #expect(playing.albumURI == "spotify:album:alb1")
    }

    @Test func readsDisallowedActions() throws {
        let playing = try #require(SpotifyPlayback.parse(playerJSON()))
        #expect(playing.disallows == ["skipping_prev", "resuming"])
        #expect(!playing.canSkipPrevious)
        #expect(playing.canSkipNext)
        #expect(playing.canSeek)
        #expect(playing.canShuffle)
        #expect(playing.canRepeat)
    }

    @Test func aFalseDisallowDoesNotDisable() throws {
        let actions = #""actions": { "disallows": { "skipping_next": false, "seeking": false, "toggling_shuffle": false } },"#
        let playing = try #require(SpotifyPlayback.parse(playerJSON(actions: actions)))
        #expect(playing.disallows.isEmpty)
        #expect(playing.canSkipNext)
        #expect(playing.canSeek)
        #expect(playing.canShuffle)
    }

    @Test func eachDisallowTurnsOffItsOwnControl() throws {
        func parsed(_ keys: String) throws -> NowPlaying {
            let actions = "\"actions\": { \"disallows\": { \(keys) } },"
            return try #require(SpotifyPlayback.parse(playerJSON(actions: actions)))
        }
        #expect(try !parsed(#""skipping_next": true"#).canSkipNext)
        #expect(try !parsed(#""seeking": true"#).canSeek)
        #expect(try !parsed(#""toggling_shuffle": true"#).canShuffle)
    }

    @Test func repeatIsOffOnlyWhenBothRepeatTogglesAreDisallowed() throws {
        func parsed(_ keys: String) throws -> NowPlaying {
            let actions = "\"actions\": { \"disallows\": { \(keys) } },"
            return try #require(SpotifyPlayback.parse(playerJSON(actions: actions)))
        }
        #expect(try parsed(#""toggling_repeat_context": true"#).canRepeat)
        #expect(try parsed(#""toggling_repeat_track": true"#).canRepeat)
        #expect(try !parsed(#""toggling_repeat_context": true, "toggling_repeat_track": true"#).canRepeat)
    }

    @Test func missingFieldsDefaultSafely() throws {
        let playing = try #require(SpotifyPlayback.parse(Data(trackJSON.utf8)))
        #expect(!playing.shuffle)
        #expect(playing.repeatMode == .off)
        #expect(playing.disallows.isEmpty)
        #expect(playing.contextURI == nil)
        #expect(playing.canSkipNext)
        #expect(playing.canSkipPrevious)
        #expect(playing.canSeek)
        #expect(playing.canShuffle)
        #expect(playing.canRepeat)
    }

    @Test func aNullContextOrActionsIsNone() throws {
        let playing = try #require(SpotifyPlayback.parse(playerJSON(context: #""context": null,"#, actions: #""actions": null,"#)))
        #expect(playing.contextURI == nil)
        #expect(playing.disallows.isEmpty)
    }

    @Test func anUnknownRepeatWordCountsAsOff() throws {
        let playing = try #require(SpotifyPlayback.parse(playerJSON(repeatState: #""repeat_state": "sideways","#)))
        #expect(playing.repeatMode == .off)
    }

    @Test func aTrackWithoutAnAlbumURIHasNone() throws {
        let playing = try #require(SpotifyPlayback.parse(Data(trackJSON.utf8)))
        #expect(playing.uri == nil)
        #expect(playing.albumURI == nil)
    }

    @Test func episodeKeepsItsURI() throws {
        let json = #"{"is_playing":true,"progress_ms":0,"item":{"id":"ep1","uri":"spotify:episode:ep1","name":"Episode","duration_ms":1000,"show":{"name":"The Show"}}}"#
        let playing = try #require(SpotifyPlayback.parse(Data(json.utf8)))
        #expect(playing.uri == "spotify:episode:ep1")
        #expect(playing.albumURI == nil)
    }

    @Test func aHandBuiltNowPlayingCanDoEverything() {
        let playing = NowPlaying(title: "x")
        #expect(playing.canSkipNext && playing.canSkipPrevious && playing.canSeek && playing.canShuffle && playing.canRepeat)
        #expect(!playing.shuffle)
        #expect(playing.repeatMode == .off)
    }
}

@Suite struct SpotifyFailureTests {
    private func body(reason: String) -> Data {
        Data(#"{"error":{"status":404,"message":"Player command failed","reason":"\#(reason)"}}"#.utf8)
    }

    @Test func noActiveDevice() {
        #expect(SpotifyFailure.classify(status: 404, body: body(reason: "NO_ACTIVE_DEVICE")) == .noActiveDevice)
    }

    @Test func premiumRequired() {
        #expect(SpotifyFailure.classify(status: 403, body: body(reason: "PREMIUM_REQUIRED")) == .premiumRequired)
    }

    @Test func otherForbiddenMeansNotAllowed() {
        #expect(SpotifyFailure.classify(status: 403, body: Data()) == .notAllowed)
    }

    @Test func unauthorizedMeansSignInAgain() {
        #expect(SpotifyFailure.classify(status: 401, body: Data()) == .notSignedIn)
    }

    @Test func rateLimitUsesRetryAfter() {
        #expect(SpotifyFailure.classify(status: 429, body: Data(), retryAfter: "7") == .rateLimited(retryAfter: 7))
        #expect(SpotifyFailure.classify(status: 429, body: Data(), retryAfter: nil) == .rateLimited(retryAfter: 3))
    }

    @Test func anythingElseKeepsItsStatus() {
        #expect(SpotifyFailure.classify(status: 500, body: Data()) == .http(500))
        #expect(SpotifyFailure.classify(status: 404, body: Data("garbage".utf8)) == .http(404))
    }

    @Test func noActiveDeviceSendsThemToTheDevicePicker() {
        #expect(SpotifyFailure.noActiveDevice.message
                == "Spotify has no device ready to play. Choose one under Devices, or open Spotify once.")
    }

    @Test func everyFailureHasAMessage() {
        let all: [SpotifyFailure] = [
            .notSignedIn, .noActiveDevice, .premiumRequired, .notAllowed, .rateLimited(retryAfter: 1), .http(500), .offline
        ]
        for failure in all {
            #expect(!failure.message.isEmpty)
        }
    }
}
