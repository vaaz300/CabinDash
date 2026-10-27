import Foundation
import Testing
@testable import CabinCore

private func data(_ text: String) -> Data { Data(text.utf8) }

private let nextURL = #""https://api.spotify.com/v1/next""#

/// A track as Spotify sends it. `extra` is appended inside the object, e.g. `, "is_local": true`.
private func trackObject(uri: String = "spotify:track:t1", name: String = "Song One", extra: String = "") -> String {
    """
    { "type": "track", "uri": "\(uri)", "name": "\(name)", "duration_ms": 200000,
      "artists": [ { "name": "Artist A" }, { "name": "Artist B" } ],
      "album": { "name": "Album One", "uri": "spotify:album:alb1",
        "images": [ { "url": "https://example.com/a-small.jpg", "width": 64 },
                    { "url": "https://example.com/a-mid.jpg", "width": 300 },
                    { "url": "https://example.com/a-big.jpg", "width": 640 } ] }\(extra) }
    """
}

/// A playlist-items or saved-tracks entry holding a track under `key`: "item" in Spotify's new answers, "track" in the old ones.
/// `before` is extra fields written ahead of it, e.g. `"is_local": true, `.
private func wrapped(_ key: String, _ object: String, before: String = "") -> String {
    "{ \(before)\"\(key)\": \(object) }"
}

private func playlistObject(
    uri: String = "spotify:playlist:p1",
    name: String = "Road trip",
    collaborative: Bool = false,
    images: String = #"[ { "url": "https://example.com/pl-small.jpg", "width": 64 }, { "url": "https://example.com/pl-big.jpg", "width": 640 } ]"#,
    owner: String = #"{ "id": "me", "display_name": "Evan" }"#,
    count: String = #""items": { "total": 12 }"#
) -> String {
    """
    { "uri": "\(uri)", "name": "\(name)", "collaborative": \(collaborative), "images": \(images), "owner": \(owner), \(count) }
    """
}

private func pageJSON(_ items: String, offset: Int = 0, limit: Int = 50, next: String = "null", total: Int = 1) -> Data {
    data("""
    { "limit": \(limit), "offset": \(offset), "next": \(next), "total": \(total), "items": [ \(items) ] }
    """)
}

@Suite struct SpotifyPlaylistParsingTests {
    @Test func playlistsReadNewItemsTotal() throws {
        let page = try #require(SpotifyLibrary.parsePlaylists(pageJSON(playlistObject())))
        let playlist = try #require(page.items.first)
        #expect(playlist.uri == "spotify:playlist:p1")
        #expect(playlist.id == "spotify:playlist:p1")
        #expect(playlist.name == "Road trip")
        #expect(playlist.trackCount == 12)
        #expect(playlist.ownerID == "me")
        #expect(playlist.ownerName == "Evan")
        #expect(!playlist.isCollaborative)
        #expect(playlist.artworkURL?.absoluteString == "https://example.com/pl-big.jpg")
    }

    @Test func playlistsReadOldTracksTotal() throws {
        let page = try #require(SpotifyLibrary.parsePlaylists(pageJSON(playlistObject(count: #""tracks": { "total": 7 }"#))))
        #expect(page.items.first?.trackCount == 7)
    }

    @Test func playlistWithoutPicturesOrCountStillParses() throws {
        let bare = #"{ "uri": "spotify:playlist:p2", "name": "Bare", "images": null }"#
        let page = try #require(SpotifyLibrary.parsePlaylists(pageJSON(bare)))
        let playlist = try #require(page.items.first)
        #expect(playlist.artworkURL == nil)
        #expect(playlist.trackCount == nil)
        #expect(playlist.ownerID == nil)
        #expect(playlist.ownerName == "")
        #expect(!playlist.isCollaborative)
    }

    @Test func aPlaylistWithoutAnURIOrNameIsSkipped() throws {
        let items = [#"{ "name": "No uri" }"#, #"{ "uri": "spotify:playlist:p3" }"#, "null", "7", playlistObject()].joined(separator: ",")
        let page = try #require(SpotifyLibrary.parsePlaylists(pageJSON(items)))
        #expect(page.items.map(\.uri) == ["spotify:playlist:p1"])
    }

    @Test func anOwnerWithoutADisplayNameShowsItsId() throws {
        let page = try #require(SpotifyLibrary.parsePlaylists(pageJSON(playlistObject(owner: #"{ "id": "spotify" }"#))))
        #expect(page.items.first?.ownerName == "spotify")
    }

    @Test func playlistsKeepTheNextOffset() throws {
        let more = try #require(SpotifyLibrary.parsePlaylists(pageJSON(playlistObject(), offset: 0, limit: 50, next: nextURL, total: 120)))
        #expect(more.nextOffset == 50)
        #expect(more.total == 120)
        let last = try #require(SpotifyLibrary.parsePlaylists(pageJSON(playlistObject(), offset: 100, limit: 50, next: "null", total: 120)))
        #expect(last.nextOffset == nil)
    }

    @Test func aNextLinkWithoutPagingNumbersEndsThePaging() throws {
        let json = data(#"{ "next": "https://api.spotify.com/v1/next", "items": [] }"#)
        let page = try #require(SpotifyLibrary.parsePlaylists(json))
        #expect(page.nextOffset == nil)
        let empty = data(#"{ "next": "", "offset": 0, "limit": 50, "items": [] }"#)
        #expect(SpotifyLibrary.parsePlaylists(empty)?.nextOffset == nil)
    }

    @Test func canListItemsForOwnCollaborativeAndNotOthers() {
        let mine = SpotifyPlaylist(uri: "spotify:playlist:a", name: "Mine", ownerID: "me")
        let shared = SpotifyPlaylist(uri: "spotify:playlist:b", name: "Shared", ownerID: "someone", isCollaborative: true)
        let theirs = SpotifyPlaylist(uri: "spotify:playlist:c", name: "Theirs", ownerID: "someone")
        let unknownOwner = SpotifyPlaylist(uri: "spotify:playlist:d", name: "Odd")
        #expect(mine.canListItems(profileID: "me"))
        #expect(shared.canListItems(profileID: "me"))
        #expect(!theirs.canListItems(profileID: "me"))
        #expect(!mine.canListItems(profileID: nil))
        #expect(!theirs.canListItems(profileID: nil))
        #expect(shared.canListItems(profileID: nil))
        #expect(!unknownOwner.canListItems(profileID: "me"))
    }
}

@Suite struct SpotifyTrackParsingTests {
    @Test func playlistItemsReadItemKey() throws {
        let page = try #require(SpotifyLibrary.parsePlaylistItems(pageJSON(wrapped("item", trackObject()))))
        let track = try #require(page.items.first)
        #expect(track.uri == "spotify:track:t1")
        #expect(track.id == "spotify:track:t1")
        #expect(track.name == "Song One")
        #expect(track.subtitle == "Artist A, Artist B")
        #expect(track.albumName == "Album One")
        #expect(track.albumURI == "spotify:album:alb1")
        #expect(track.artworkURL?.absoluteString == "https://example.com/a-mid.jpg")
        #expect(abs(track.duration - 200) < 0.0001)
        #expect(track.isPlayable)
    }

    @Test func playlistItemsReadTrackKey() throws {
        let page = try #require(SpotifyLibrary.parsePlaylistItems(pageJSON(wrapped("track", trackObject()))))
        #expect(page.items.map(\.name) == ["Song One"])
    }

    @Test func aNullItemFallsBackToTheTrackKey() throws {
        let entry = wrapped("track", trackObject(), before: "\"item\": null, ")
        let page = try #require(SpotifyLibrary.parsePlaylistItems(pageJSON(entry)))
        #expect(page.items.map(\.name) == ["Song One"])
    }

    @Test func playlistItemsSkipNullAndMalformedEntries() throws {
        let entries = [
            #"{ "item": null }"#,
            #"{ "track": null }"#,
            "{}",
            "null",
            "5",
            #"{ "item": { "name": "No uri" } }"#,
            #"{ "item": { "uri": "spotify:track:nameless" } }"#,
            wrapped("item", trackObject(uri: "spotify:track:ok", name: "Keeper"))
        ]
        let page = try #require(SpotifyLibrary.parsePlaylistItems(pageJSON(entries.joined(separator: ","))))
        #expect(page.items.map(\.name) == ["Keeper"])
    }

    @Test func localFilesAreNotPlayable() throws {
        let local = wrapped("item", trackObject(uri: "spotify:local:::Demo:180", name: "Demo"), before: "\"is_local\": true, ")
        let flagged = wrapped("item", trackObject(uri: "spotify:track:x", name: "Flagged", extra: ", \"is_local\": true"))
        let blocked = wrapped("item", trackObject(uri: "spotify:track:y", name: "Blocked", extra: ", \"is_playable\": false"))
        let page = try #require(SpotifyLibrary.parsePlaylistItems(pageJSON([local, flagged, blocked].joined(separator: ","))))
        #expect(page.items.map(\.isPlayable) == [false, false, false])
    }

    @Test func episodesUseTheShowAsSubtitle() throws {
        let episode = """
        { "item": { "type": "episode", "uri": "spotify:episode:e1", "name": "Episode One", "duration_ms": 1800000,
          "show": { "name": "The Show" },
          "images": [ { "url": "https://example.com/e.jpg", "width": 300 } ] } }
        """
        let page = try #require(SpotifyLibrary.parsePlaylistItems(pageJSON(episode)))
        let track = try #require(page.items.first)
        #expect(track.subtitle == "The Show")
        #expect(track.albumName == "")
        #expect(track.albumURI == nil)
        #expect(track.artworkURL?.absoluteString == "https://example.com/e.jpg")
        #expect(track.playTarget == .uris(["spotify:episode:e1"]))
    }

    @Test func savedTracksReadTheTrackKey() throws {
        let entry = wrapped("track", trackObject(), before: "\"added_at\": \"2026-01-01\", ")
        let page = try #require(SpotifyLibrary.parseSavedTracks(pageJSON(entry, offset: 0, limit: 50, next: nextURL, total: 120)))
        #expect(page.items.map(\.uri) == ["spotify:track:t1"])
        #expect(page.nextOffset == 50)
        #expect(page.total == 120)
    }

    @Test func trackPlayTargetUsesTheAlbumAsContext() throws {
        let page = try #require(SpotifyLibrary.parseSavedTracks(pageJSON(wrapped("track", trackObject()))))
        let track = try #require(page.items.first)
        #expect(track.playTarget == .context(uri: "spotify:album:alb1", startAtURI: "spotify:track:t1"))
    }

    @Test func trackWithoutAnAlbumPlaysItselfAlone() {
        let track = SpotifyTrack(uri: "spotify:track:solo", name: "Solo")
        #expect(track.albumURI == nil)
        #expect(track.playTarget == .uris(["spotify:track:solo"]))
        #expect(track.isPlayable)
    }
}

@Suite struct SpotifySearchParsingTests {
    private let albumObject = """
    { "uri": "spotify:album:alb1", "name": "Album One", "artists": [ { "name": "Artist A" }, { "name": "Artist B" } ],
      "images": [ { "url": "https://example.com/al.jpg", "width": 300 } ] }
    """

    @Test func searchReadsThreeSections() throws {
        let json = data("""
        { "tracks": { "items": [ \(trackObject()) ] },
          "albums": { "items": [ \(albumObject) ] },
          "playlists": { "items": [ \(playlistObject()) ] } }
        """)
        let results = try #require(SpotifyLibrary.parseSearch(json))
        #expect(results.tracks.map(\.name) == ["Song One"])
        #expect(results.albums.map(\.name) == ["Album One"])
        #expect(results.albums.first?.uri == "spotify:album:alb1")
        #expect(results.albums.first?.id == "spotify:album:alb1")
        #expect(results.albums.first?.artist == "Artist A, Artist B")
        #expect(results.albums.first?.artworkURL?.absoluteString == "https://example.com/al.jpg")
        #expect(results.playlists.map(\.name) == ["Road trip"])
    }

    @Test func searchSkipsNullPlaylists() throws {
        let json = data("""
        { "playlists": { "items": [ null, \(playlistObject()), null, { "name": "no uri" } ] } }
        """)
        let results = try #require(SpotifyLibrary.parseSearch(json))
        #expect(results.playlists.map(\.uri) == ["spotify:playlist:p1"])
    }

    @Test func searchWithAMissingSectionGivesEmptyArray() throws {
        let json = data("""
        { "tracks": { "items": [ \(trackObject()) ] } }
        """)
        let results = try #require(SpotifyLibrary.parseSearch(json))
        #expect(results.tracks.count == 1)
        #expect(results.albums.isEmpty)
        #expect(results.playlists.isEmpty)
    }

    @Test func searchWithNothingFoundIsEmptyNotNil() throws {
        let results = try #require(SpotifyLibrary.parseSearch(data("{}")))
        #expect(results.tracks.isEmpty && results.albums.isEmpty && results.playlists.isEmpty)
    }
}

@Suite struct SpotifyPlayerStateParsingTests {
    @Test func queueReadsCurrentAndUpNext() throws {
        let json = data("""
        { "currently_playing": \(trackObject(uri: "spotify:track:now", name: "Now")),
          "queue": [ \(trackObject(uri: "spotify:track:n1", name: "Next One")), null, \(trackObject(uri: "spotify:track:n2", name: "Next Two")) ] }
        """)
        let queue = try #require(SpotifyLibrary.parseQueue(json))
        #expect(queue.current?.name == "Now")
        #expect(queue.upNext.map(\.name) == ["Next One", "Next Two"])
    }

    @Test func queueWithNothingPlayingHasNoCurrent() throws {
        let queue = try #require(SpotifyLibrary.parseQueue(data(#"{ "currently_playing": null, "queue": [] }"#)))
        #expect(queue.current == nil)
        #expect(queue.upNext.isEmpty)
    }

    @Test func devicesReadsTypeAndActive() throws {
        let json = data("""
        { "devices": [
          { "id": "d1", "is_active": true, "is_restricted": false, "name": "Evan's iPhone", "type": "Smartphone" },
          { "id": null, "is_active": false, "is_restricted": true, "name": "Ghost", "type": "Speaker" },
          { "id": "d2", "is_active": false, "is_restricted": true, "name": "Kitchen", "type": "Speaker" }
        ] }
        """)
        let devices = try #require(SpotifyLibrary.parseDevices(json))
        #expect(devices.map(\.id) == ["d1", "d2"])
        #expect(devices[0].name == "Evan's iPhone")
        #expect(devices[0].type == "Smartphone")
        #expect(devices[0].isActive)
        #expect(!devices[0].isRestricted)
        #expect(!devices[1].isActive)
        #expect(devices[1].isRestricted)
    }

    @Test func noDevicesIsAnEmptyListNotNil() throws {
        let devices = try #require(SpotifyLibrary.parseDevices(data(#"{ "devices": [] }"#)))
        #expect(devices.isEmpty)
    }

    @Test func containsReadsBooleans() throws {
        #expect(SpotifyLibrary.parseContains(data("[true, false, true]")) == [true, false, true])
        #expect(SpotifyLibrary.parseContains(data("[]")) == [])
    }

    @Test func containsRejectsAnythingButBooleans() {
        #expect(SpotifyLibrary.parseContains(data("[true, null]")) == nil)
        #expect(SpotifyLibrary.parseContains(data(#"{ "a": true }"#)) == nil)
        #expect(SpotifyLibrary.parseContains(data(#"["yes"]"#)) == nil)
    }

    @Test func profileReadsIdAndName() throws {
        let profile = try #require(SpotifyLibrary.parseProfile(data(#"{ "id": "me", "display_name": "Evan" }"#)))
        #expect(profile.id == "me")
        #expect(profile.name == "Evan")
        let unnamed = try #require(SpotifyLibrary.parseProfile(data(#"{ "id": "me", "display_name": null }"#)))
        #expect(unnamed.name == "me")
        #expect(SpotifyLibrary.parseProfile(data(#"{ "display_name": "No id" }"#)) == nil)
    }
}

@Suite struct SpotifyThumbnailTests {
    private func pictures(_ widths: [Int]) -> [[String: Any]] {
        widths.map { ["url": "https://example.com/\($0).jpg", "width": $0] }
    }

    @Test func thumbnailPrefersASmallEnoughPicture() {
        let url = SpotifyPlayback.thumbnail(in: pictures([64, 300, 640]))
        #expect(url?.absoluteString == "https://example.com/300.jpg")
        #expect(SpotifyPlayback.thumbnail(in: pictures([640, 300, 64]))?.absoluteString == "https://example.com/300.jpg")
    }

    @Test func whenEveryPictureIsSmallTheLargestIsUsed() {
        #expect(SpotifyPlayback.thumbnail(in: pictures([40, 100, 64]))?.absoluteString == "https://example.com/100.jpg")
    }

    @Test func noPicturesGivesNil() {
        #expect(SpotifyPlayback.thumbnail(in: []) == nil)
    }

    @Test func picturesWithoutSizesStillGiveOne() {
        let unsized: [[String: Any]] = [["url": "https://example.com/first.jpg"], ["url": "https://example.com/second.jpg"]]
        #expect(SpotifyPlayback.thumbnail(in: unsized) != nil)
    }
}

@Suite struct SpotifyParserSafetyTests {
    @Test func everyParserReturnsNilForEmptyData() {
        for bad in [Data(), data("not json")] {
            #expect(SpotifyLibrary.parsePlaylists(bad) == nil)
            #expect(SpotifyLibrary.parsePlaylistItems(bad) == nil)
            #expect(SpotifyLibrary.parseSavedTracks(bad) == nil)
            #expect(SpotifyLibrary.parseSearch(bad) == nil)
            #expect(SpotifyLibrary.parseQueue(bad) == nil)
            #expect(SpotifyLibrary.parseDevices(bad) == nil)
            #expect(SpotifyLibrary.parseContains(bad) == nil)
            #expect(SpotifyLibrary.parseProfile(bad) == nil)
        }
    }

    @Test func parsersThatNeedAnObjectRejectAnArray() {
        let array = data("[]")
        #expect(SpotifyLibrary.parsePlaylists(array) == nil)
        #expect(SpotifyLibrary.parsePlaylistItems(array) == nil)
        #expect(SpotifyLibrary.parseSavedTracks(array) == nil)
        #expect(SpotifyLibrary.parseSearch(array) == nil)
        #expect(SpotifyLibrary.parseQueue(array) == nil)
        #expect(SpotifyLibrary.parseDevices(array) == nil)
        #expect(SpotifyLibrary.parseProfile(array) == nil)
    }
}
