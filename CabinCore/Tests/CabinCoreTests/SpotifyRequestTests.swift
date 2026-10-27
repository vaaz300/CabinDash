import Foundation
import Testing
@testable import CabinCore

private func text(_ data: Data?) -> String { String(decoding: data ?? Data(), as: UTF8.self) }
private func pairs(_ request: SpotifyRequest) -> [String] { request.query.map { "\($0.name)=\($0.value ?? "")" } }

@Suite struct SpotifyEndpointTests {
    @Test func playerAsksForTracksAndEpisodes() {
        let request = SpotifyEndpoint.player()
        #expect(request.method == "GET")
        #expect(request.path == "/v1/me/player")
        #expect(pairs(request) == ["additional_types=track,episode"])
        #expect(request.body == nil)
    }

    @Test func resumeAndPause() {
        let resume = SpotifyEndpoint.resume()
        #expect(resume.method == "PUT")
        #expect(resume.path == "/v1/me/player/play")
        #expect(resume.query.isEmpty)
        #expect(resume.body == nil)
        #expect(pairs(SpotifyEndpoint.resume(deviceID: "d1")) == ["device_id=d1"])
        let pause = SpotifyEndpoint.pause()
        #expect(pause.method == "PUT")
        #expect(pause.path == "/v1/me/player/pause")
    }

    @Test func nextAndPreviousArePosts() {
        #expect(SpotifyEndpoint.next().method == "POST")
        #expect(SpotifyEndpoint.next().path == "/v1/me/player/next")
        #expect(SpotifyEndpoint.previous().method == "POST")
        #expect(SpotifyEndpoint.previous().path == "/v1/me/player/previous")
    }

    @Test func seekUsesMilliseconds() {
        let request = SpotifyEndpoint.seek(milliseconds: 61_500)
        #expect(request.method == "PUT")
        #expect(request.path == "/v1/me/player/seek")
        #expect(pairs(request) == ["position_ms=61500"])
    }

    @Test func playAContextAtATrack() {
        let request = SpotifyEndpoint.play(.context(uri: "spotify:playlist:p1", startAtURI: "spotify:track:t9"))
        #expect(request.method == "PUT")
        #expect(request.path == "/v1/me/player/play")
        #expect(text(request.body) == #"{"context_uri":"spotify:playlist:p1","offset":{"uri":"spotify:track:t9"}}"#)
    }

    @Test func playAContextFromItsStartHasNoOffset() {
        let request = SpotifyEndpoint.play(.context(uri: "spotify:album:a1", startAtURI: nil))
        #expect(text(request.body) == #"{"context_uri":"spotify:album:a1"}"#)
    }

    @Test func playTracksOnAChosenDevice() {
        let request = SpotifyEndpoint.play(.uris(["spotify:track:a", "spotify:track:b"]), deviceID: "d1")
        #expect(pairs(request) == ["device_id=d1"])
        #expect(text(request.body) == #"{"uris":["spotify:track:a","spotify:track:b"]}"#)
    }

    @Test func transferPlaybackToADevice() {
        let request = SpotifyEndpoint.transfer(to: "d1", play: true)
        #expect(request.method == "PUT")
        #expect(request.path == "/v1/me/player")
        #expect(text(request.body) == #"{"device_ids":["d1"],"play":true}"#)
        #expect(text(SpotifyEndpoint.transfer(to: "d1", play: false).body) == #"{"device_ids":["d1"],"play":false}"#)
    }

    @Test func shuffleAndRepeat() {
        #expect(SpotifyEndpoint.shuffle(true).path == "/v1/me/player/shuffle")
        #expect(SpotifyEndpoint.shuffle(true).method == "PUT")
        #expect(pairs(SpotifyEndpoint.shuffle(true)) == ["state=true"])
        #expect(pairs(SpotifyEndpoint.shuffle(false)) == ["state=false"])
        #expect(SpotifyEndpoint.setRepeat(.context).path == "/v1/me/player/repeat")
        #expect(pairs(SpotifyEndpoint.setRepeat(.context)) == ["state=context"])
        #expect(pairs(SpotifyEndpoint.setRepeat(.track)) == ["state=track"])
        #expect(pairs(SpotifyEndpoint.setRepeat(.off)) == ["state=off"])
    }

    @Test func queueDevicesAndProfile() {
        #expect(SpotifyEndpoint.queue().method == "GET")
        #expect(SpotifyEndpoint.queue().path == "/v1/me/player/queue")
        let add = SpotifyEndpoint.addToQueue(uri: "spotify:track:t1")
        #expect(add.method == "POST")
        #expect(add.path == "/v1/me/player/queue")
        #expect(pairs(add) == ["uri=spotify:track:t1"])
        #expect(SpotifyEndpoint.devices().path == "/v1/me/player/devices")
        #expect(SpotifyEndpoint.profile().path == "/v1/me")
    }

    @Test func listsArePagedFiftyAtATime() {
        let playlists = SpotifyEndpoint.playlists(offset: 100)
        #expect(playlists.path == "/v1/me/playlists")
        #expect(pairs(playlists) == ["limit=50", "offset=100"])
        let items = SpotifyEndpoint.playlistItems(id: "abc", offset: 0)
        #expect(items.path == "/v1/playlists/abc/items")
        #expect(pairs(items) == ["limit=50", "offset=0", "additional_types=track,episode"])
        let saved = SpotifyEndpoint.savedTracks(offset: 50)
        #expect(saved.path == "/v1/me/tracks")
        #expect(pairs(saved) == ["limit=50", "offset=50"])
    }

    @Test func aPlaylistIdIsEscapedInThePath() {
        #expect(SpotifyEndpoint.playlistItems(id: "a/b", offset: 0).path == "/v1/playlists/a%2Fb/items")
    }

    @Test func searchAsksForThreeKindsTenEach() {
        let request = SpotifyEndpoint.search("daft punk")
        #expect(request.method == "GET")
        #expect(request.path == "/v1/search")
        #expect(pairs(request) == ["q=daft punk", "type=track,album,playlist", "limit=10"])
        let address = request.url()?.absoluteString ?? ""
        #expect(address.contains("q=daft%20punk"))
        #expect(address.contains("type=track%2Calbum%2Cplaylist"))
    }

    @Test func libraryCallsTakeUrisJoinedByCommas() {
        let uris = ["spotify:track:t1", "spotify:track:t2"]
        let save = SpotifyEndpoint.save(uris: uris)
        #expect(save.method == "PUT")
        #expect(save.path == "/v1/me/library")
        #expect(pairs(save) == ["uris=spotify:track:t1,spotify:track:t2"])
        #expect(SpotifyEndpoint.remove(uris: uris).method == "DELETE")
        #expect(SpotifyEndpoint.remove(uris: uris).path == "/v1/me/library")
        let check = SpotifyEndpoint.contains(uris: uris)
        #expect(check.method == "GET")
        #expect(check.path == "/v1/me/library/contains")
        #expect(check.url()?.absoluteString.contains("uris=spotify%3Atrack%3At1%2Cspotify%3Atrack%3At2") == true)
    }

    @Test func libraryCallsAreCappedAtFortyUris() {
        let many = (0..<41).map { "spotify:track:t\($0)" }
        let value = SpotifyEndpoint.save(uris: many).query.first?.value ?? ""
        #expect(value.split(separator: ",").count == 40)
    }

    @Test func urlsAreEscapedAndComplete() {
        #expect(SpotifyEndpoint.player().url()?.absoluteString
                == "https://api.spotify.com/v1/me/player?additional_types=track%2Cepisode")
        #expect(SpotifyEndpoint.devices().url()?.absoluteString == "https://api.spotify.com/v1/me/player/devices")
    }
}

@Suite struct SpotifyPlayTargetTests {
    private let uris = (0..<5).map { "u\($0)" }

    @Test func aWindowStartsAtTheChosenTrack() {
        #expect(SpotifyPlayTarget.window(uris, startingAt: 2) == .uris(["u2", "u3", "u4"]))
    }

    @Test func anIndexOutsideTheListIsClamped() {
        #expect(SpotifyPlayTarget.window(uris, startingAt: 9) == .uris(["u4"]))
        #expect(SpotifyPlayTarget.window(uris, startingAt: -3) == .uris(uris))
    }

    @Test func aWindowIsCappedAtTheLimit() {
        let long = (0..<250).map { "u\($0)" }
        guard case .uris(let window) = SpotifyPlayTarget.window(long, startingAt: 10) else {
            Issue.record("expected a list of uris")
            return
        }
        #expect(window.count == 100)
        #expect(window.first == "u10")
        #expect(window.last == "u109")
    }

    @Test func anEmptyListGivesNothingToPlay() {
        #expect(SpotifyPlayTarget.window([], startingAt: 0) == .uris([]))
    }
}

@Suite struct SpotifyRepeatTests {
    @Test func cyclesOffContextTrackOff() {
        #expect(SpotifyRepeat.off.next == .context)
        #expect(SpotifyRepeat.context.next == .track)
        #expect(SpotifyRepeat.track.next == .off)
    }

    @Test func readsSpotifysWords() {
        #expect(SpotifyRepeat(spotifyValue: "track") == .track)
        #expect(SpotifyRepeat(spotifyValue: "context") == .context)
        #expect(SpotifyRepeat(spotifyValue: "off") == .off)
        #expect(SpotifyRepeat(spotifyValue: nil) == .off)
        #expect(SpotifyRepeat(spotifyValue: "bogus") == .off)
    }

    @Test func everyModeHasATitleAndASymbol() {
        let titles = SpotifyRepeat.allCases.map(\.title)
        #expect(!titles.contains(""))
        #expect(Set(titles).count == SpotifyRepeat.allCases.count)
        #expect(SpotifyRepeat.track.symbol == "repeat.1")
        #expect(SpotifyRepeat.off.symbol == "repeat")
    }
}
