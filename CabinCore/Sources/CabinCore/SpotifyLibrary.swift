import Foundation

// MARK: - Models

/// A song or podcast episode in a list.
public struct SpotifyTrack: Equatable, Sendable, Identifiable {
    public var uri: String
    public var name: String
    /// The artists, or the show for a podcast episode.
    public var subtitle: String
    public var albumName: String
    public var albumURI: String?
    public var artworkURL: URL?
    /// Seconds.
    public var duration: TimeInterval
    /// False for local files and for anything Spotify marks as not playable.
    public var isPlayable: Bool

    public var id: String { uri }

    public init(
        uri: String, name: String, subtitle: String = "", albumName: String = "", albumURI: String? = nil,
        artworkURL: URL? = nil, duration: TimeInterval = 0, isPlayable: Bool = true
    ) {
        self.uri = uri
        self.name = name
        self.subtitle = subtitle
        self.albumName = albumName
        self.albumURI = albumURI
        self.artworkURL = artworkURL
        self.duration = duration
        self.isPlayable = isPlayable
    }

    /// Plays the track inside its album, so what follows it is the rest of the album. Without an album it plays alone.
    public var playTarget: SpotifyPlayTarget {
        if let albumURI { return .context(uri: albumURI, startAtURI: uri) }
        return .uris([uri])
    }
}

public struct SpotifyPlaylist: Equatable, Sendable, Identifiable {
    public var uri: String
    public var name: String
    public var artworkURL: URL?
    public var ownerID: String?
    public var ownerName: String
    /// Nil when Spotify does not say (it leaves the count out of playlists the person does not own).
    public var trackCount: Int?
    public var isCollaborative: Bool

    public var id: String { uri }

    /// The id inside the URI (`spotify:playlist:<id>`), which is what the playlist calls take in their path.
    public var spotifyID: String {
        uri.split(separator: ":").last.map(String.init) ?? uri
    }

    public init(
        uri: String, name: String, artworkURL: URL? = nil, ownerID: String? = nil, ownerName: String = "",
        trackCount: Int? = nil, isCollaborative: Bool = false
    ) {
        self.uri = uri
        self.name = name
        self.artworkURL = artworkURL
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.trackCount = trackCount
        self.isCollaborative = isCollaborative
    }

    /// Since February 2026 Spotify only lists the tracks of playlists the person owns or can edit together with others.
    public func canListItems(profileID: String?) -> Bool {
        if isCollaborative { return true }
        guard let profileID, let owner = ownerID else { return false }
        return owner == profileID
    }
}

public struct SpotifyAlbum: Equatable, Sendable, Identifiable {
    public var uri: String
    public var name: String
    public var artist: String
    public var artworkURL: URL?

    public var id: String { uri }

    public init(uri: String, name: String, artist: String = "", artworkURL: URL? = nil) {
        self.uri = uri
        self.name = name
        self.artist = artist
        self.artworkURL = artworkURL
    }
}

/// Somewhere Spotify can play: a phone, a speaker, a computer.
public struct SpotifyDevice: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var type: String
    public var isActive: Bool
    /// A restricted device (some speakers and TVs) accepts no commands from other apps.
    public var isRestricted: Bool

    public init(id: String, name: String, type: String = "", isActive: Bool = false, isRestricted: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.isActive = isActive
        self.isRestricted = isRestricted
    }
}

public struct SpotifyQueue: Equatable, Sendable {
    public var current: SpotifyTrack?
    public var upNext: [SpotifyTrack]

    public init(current: SpotifyTrack? = nil, upNext: [SpotifyTrack] = []) {
        self.current = current
        self.upNext = upNext
    }
}

public struct SpotifySearchResults: Equatable, Sendable {
    public var tracks: [SpotifyTrack]
    public var albums: [SpotifyAlbum]
    public var playlists: [SpotifyPlaylist]

    public init(tracks: [SpotifyTrack] = [], albums: [SpotifyAlbum] = [], playlists: [SpotifyPlaylist] = []) {
        self.tracks = tracks
        self.albums = albums
        self.playlists = playlists
    }
}

public struct SpotifyProfile: Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One page of a long list.
public struct SpotifyPage<Item: Equatable & Sendable>: Equatable, Sendable {
    public var items: [Item]
    /// Where the next page starts, or nil on the last one.
    public var nextOffset: Int?
    public var total: Int?

    public init(items: [Item], nextOffset: Int? = nil, total: Int? = nil) {
        self.items = items
        self.nextOffset = nextOffset
        self.total = total
    }
}

// MARK: - Devices and links

public enum SpotifyDevices {
    /// True when Spotify lists a phone that takes commands. Spotify lists a phone only while its Spotify app is running,
    /// so a list without one means the Spotify app on this iPhone has not been opened lately.
    public static func hasPhone(in devices: [SpotifyDevice]) -> Bool {
        devices.contains { $0.type == "Smartphone" && !$0.isRestricted }
    }

    /// The list as the picker shows it: phones first, then everything else, each group in Spotify's order.
    /// Cabin Dash never picks a device itself. Which one plays is always the person's choice.
    public static func phonesFirst(_ devices: [SpotifyDevice]) -> [SpotifyDevice] {
        devices.filter { $0.type == "Smartphone" } + devices.filter { $0.type != "Smartphone" }
    }

    /// Where to retry a play command that failed. Spotify only treats a device as active once it has something to play, so a
    /// phone the person picked while nothing was playing still answers "no active device" on the next tap. Only that failure
    /// is retried, and only on the device the person picked in the list. Never on one Cabin Dash chose, and never over a
    /// device that is active (a play command with no device already goes to the active one).
    public static func retryDeviceID(after failure: SpotifyFailure, chosenID: String?) -> String? {
        failure == .noActiveDevice ? chosenID : nil
    }

    /// The line beside the speaker symbol: the device that is playing, else the one the person picked, else this iPhone,
    /// which is where Play goes when nothing else is picked.
    public static func lineText(playingOn: String?, chosenName: String?) -> String {
        if let name = playingOn, !name.isEmpty { return "Playing on \(name)" }
        if let name = chosenName, !name.isEmpty { return "Ready on \(name)" }
        return "This iPhone"
    }

    /// Where a tap on Play sends the music.
    public enum Route: Equatable, Sendable {
        /// Send the play command to this device by its id. That works for a device Spotify does not yet count as active.
        case device(SpotifyDevice)
        /// No phone is listed, so the Spotify app on this iPhone is not running. It has to be started first.
        case wakeThisPhone
        /// The device list could not be read. Send the command with no device and let Spotify decide, as before.
        case spotifyDecides
    }

    /// The device a tap on Play uses: the one the person picked in the list while it is still listed and takes commands,
    /// otherwise the phone. A device being active is not a pick, and Cabin Dash never falls back to a TV or speaker the
    /// person did not choose. With no usable phone the Spotify app on this iPhone has to be started.
    public static func route(devices: [SpotifyDevice]?, chosenID: String?) -> Route {
        guard let devices else { return .spotifyDecides }
        if let chosenID, let picked = devices.first(where: { $0.id == chosenID && !$0.isRestricted }) {
            return .device(picked)
        }
        if let phone = devices.first(where: { $0.type == "Smartphone" && !$0.isRestricted }) {
            return .device(phone)
        }
        return .wakeThisPhone
    }

    /// What to ask Spotify's iOS SDK to play when it starts the Spotify app, and whether the request then has to be sent
    /// again through the Web API. The SDK takes one address and no shuffle, so a song inside a playlist, a list of songs and
    /// a shuffled playlist are each sent again once Spotify has opened Cabin Dash and the phone is listed.
    public struct WakePlan: Equatable, Sendable {
        public var uri: String
        public var needsResend: Bool

        public init(uri: String, needsResend: Bool) {
            self.uri = uri
            self.needsResend = needsResend
        }
    }

    public static func wakePlan(for target: SpotifyPlayTarget, shuffled: Bool) -> WakePlan {
        switch target {
        case .context(let uri, let startAtURI):
            if let startAtURI { return WakePlan(uri: startAtURI, needsResend: true) }
            return WakePlan(uri: uri, needsResend: shuffled)
        case .uris(let uris):
            guard let first = uris.first else { return WakePlan(uri: "", needsResend: false) }
            return WakePlan(uri: first, needsResend: uris.count > 1 || shuffled)
        }
    }

    /// Whether the player shows the music on `device`, which is how a command that Spotify merely accepted is told apart from
    /// one that started playing. A phone whose app is asleep accepts the command and then plays nothing.
    public static func startedOn(_ device: SpotifyDevice, playingOn deviceName: String?) -> Bool {
        deviceName == device.name
    }

    /// What to say once Spotify has accepted a move to `deviceName`. With nothing playing there is nothing to move, so the
    /// device is only ready, and saying "Playing" would be untrue.
    public static func movedNotice(deviceName: String, somethingIsPlaying: Bool) -> String {
        somethingIsPlaying ? "Playing on \(deviceName)" : "Ready on \(deviceName). Pick something to play."
    }
}

/// Ways into the Spotify app.
public enum SpotifyLink {
    /// Spotify's required wording for a link back to its app.
    public static let label = "Open Spotify"

    private static let kinds: Set<String> = ["track", "album", "playlist", "episode", "show", "artist"]

    /// Addresses to try in order: the Spotify app's own link, then the web page that hands over to it.
    /// A missing, local-file or unrecognised URI opens Spotify's home instead.
    public static func openURLs(forURI uri: String?) -> [URL] {
        let home = [URL(string: "spotify://"), URL(string: "https://open.spotify.com")].compactMap { $0 }
        guard let uri else { return home }
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "spotify", kinds.contains(parts[1]),
              !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return home }
        let links = [URL(string: uri), URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")].compactMap { $0 }
        return links.isEmpty ? home : links
    }
}

// MARK: - Parsers

/// Reads Spotify's answers. Each returns nil when the body is empty or is not the kind of JSON expected,
/// and quietly skips the single entries that are null or malformed, because Spotify does send those.
/// Paging objects are read for `next`, `offset`, `limit` and `total`.
public enum SpotifyLibrary {
    public static func parsePlaylists(_ data: Data) -> SpotifyPage<SpotifyPlaylist>? {
        guard let root = object(data) else { return nil }
        return page(root) { playlist($0) }
    }

    /// Playlist entries hold the track under `item` since February 2026 and under `track` before that. Both are read.
    public static func parsePlaylistItems(_ data: Data) -> SpotifyPage<SpotifyTrack>? {
        guard let root = object(data) else { return nil }
        return page(root) { entry in track(wrappedIn: entry) }
    }

    public static func parseSavedTracks(_ data: Data) -> SpotifyPage<SpotifyTrack>? {
        guard let root = object(data) else { return nil }
        return page(root) { entry in track(wrappedIn: entry) }
    }

    public static func parseSearch(_ data: Data) -> SpotifySearchResults? {
        guard let root = object(data) else { return nil }
        func section(_ name: String) -> [[String: Any]] {
            let entries = (root[name] as? [String: Any])?["items"] as? [Any] ?? []
            return entries.compactMap { $0 as? [String: Any] }
        }
        return SpotifySearchResults(
            tracks: section("tracks").compactMap { track($0) },
            albums: section("albums").compactMap { album($0) },
            playlists: section("playlists").compactMap { playlist($0) }
        )
    }

    public static func parseQueue(_ data: Data) -> SpotifyQueue? {
        guard let root = object(data) else { return nil }
        let current = (root["currently_playing"] as? [String: Any]).flatMap { track($0) }
        let upNext = ((root["queue"] as? [Any]) ?? []).compactMap { entry -> SpotifyTrack? in
            guard let dictionary = entry as? [String: Any] else { return nil }
            return track(dictionary)
        }
        return SpotifyQueue(current: current, upNext: upNext)
    }

    /// A device Spotify lists without an id cannot be targeted, so it is left out.
    public static func parseDevices(_ data: Data) -> [SpotifyDevice]? {
        guard let root = object(data) else { return nil }
        return ((root["devices"] as? [Any]) ?? []).compactMap { entry -> SpotifyDevice? in
            guard let device = entry as? [String: Any], let id = device["id"] as? String, !id.isEmpty else { return nil }
            return SpotifyDevice(
                id: id,
                name: (device["name"] as? String) ?? "Unknown device",
                type: (device["type"] as? String) ?? "",
                isActive: (device["is_active"] as? Bool) ?? false,
                isRestricted: (device["is_restricted"] as? Bool) ?? false
            )
        }
    }

    /// The answer of the "is this saved?" call: one true or false per item asked about.
    public static func parseContains(_ data: Data) -> [Bool]? {
        guard !data.isEmpty,
              let value = try? JSONSerialization.jsonObject(with: data),
              let array = value as? [Any] else { return nil }
        let flags = array.compactMap { $0 as? Bool }
        return flags.count == array.count ? flags : nil
    }

    public static func parseProfile(_ data: Data) -> SpotifyProfile? {
        guard let root = object(data), let id = root["id"] as? String, !id.isEmpty else { return nil }
        let shown = (root["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return SpotifyProfile(id: id, name: shown ?? id)
    }

    // MARK: Pieces

    private static func object(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty, let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return value as? [String: Any]
    }

    private static func whole(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// Reads the entries of a paging object. `nextOffset` is only set when Spotify says there is more
    /// and gave the numbers to work it out, so a missing field can never make a loader ask for ever.
    private static func page<Item: Equatable & Sendable>(
        _ root: [String: Any], _ read: ([String: Any]) -> Item?
    ) -> SpotifyPage<Item> {
        let entries = (root["items"] as? [Any]) ?? []
        let items = entries.compactMap { entry -> Item? in
            guard let dictionary = entry as? [String: Any] else { return nil }
            return read(dictionary)
        }
        var nextOffset: Int?
        if let next = root["next"] as? String, !next.isEmpty,
           let offset = whole(root["offset"]), let limit = whole(root["limit"]), limit > 0 {
            nextOffset = offset + limit
        }
        return SpotifyPage(items: items, nextOffset: nextOffset, total: whole(root["total"]))
    }

    private static func pictures(_ value: Any?) -> [[String: Any]] {
        (value as? [[String: Any]]) ?? []
    }

    private static func names(of value: Any?) -> [String] {
        ((value as? [Any]) ?? []).compactMap { ($0 as? [String: Any])?["name"] as? String }
    }

    private static func playlist(_ dictionary: [String: Any]) -> SpotifyPlaylist? {
        guard let uri = dictionary["uri"] as? String, !uri.isEmpty,
              let name = dictionary["name"] as? String else { return nil }
        let owner = dictionary["owner"] as? [String: Any]
        let ownerID = owner?["id"] as? String
        // Spotify renamed the playlist's `tracks` summary to `items` in February 2026. Both are read.
        let total = whole((dictionary["items"] as? [String: Any])?["total"])
            ?? whole((dictionary["tracks"] as? [String: Any])?["total"])
        return SpotifyPlaylist(
            uri: uri,
            name: name,
            artworkURL: SpotifyPlayback.thumbnail(in: pictures(dictionary["images"])),
            ownerID: ownerID,
            ownerName: (owner?["display_name"] as? String) ?? ownerID ?? "",
            trackCount: total,
            isCollaborative: (dictionary["collaborative"] as? Bool) ?? false
        )
    }

    private static func album(_ dictionary: [String: Any]) -> SpotifyAlbum? {
        guard let uri = dictionary["uri"] as? String, !uri.isEmpty,
              let name = dictionary["name"] as? String else { return nil }
        return SpotifyAlbum(
            uri: uri,
            name: name,
            artist: names(of: dictionary["artists"]).joined(separator: ", "),
            artworkURL: SpotifyPlayback.thumbnail(in: pictures(dictionary["images"]))
        )
    }

    /// An entry of a playlist or of the saved songs: the track sits under `item` or `track`.
    private static func track(wrappedIn entry: [String: Any]) -> SpotifyTrack? {
        guard let inner = (entry["item"] as? [String: Any]) ?? (entry["track"] as? [String: Any]) else { return nil }
        return track(inner, entryIsLocal: (entry["is_local"] as? Bool) == true)
    }

    private static func track(_ dictionary: [String: Any], entryIsLocal: Bool = false) -> SpotifyTrack? {
        guard let uri = dictionary["uri"] as? String, !uri.isEmpty,
              let name = dictionary["name"] as? String else { return nil }
        let artists = names(of: dictionary["artists"])
        let show = dictionary["show"] as? [String: Any]
        let album = dictionary["album"] as? [String: Any]
        let subtitle = artists.isEmpty ? ((show?["name"] as? String) ?? "") : artists.joined(separator: ", ")

        // Tracks keep their pictures on the album, episodes on the episode or the show.
        var images = pictures(album?["images"])
        if images.isEmpty { images = pictures(dictionary["images"]) }
        if images.isEmpty { images = pictures(show?["images"]) }

        let isLocal = entryIsLocal || uri.hasPrefix("spotify:local:") || (dictionary["is_local"] as? Bool) == true
        let playable = !isLocal && ((dictionary["is_playable"] as? Bool) ?? true)

        return SpotifyTrack(
            uri: uri,
            name: name,
            subtitle: subtitle,
            albumName: (album?["name"] as? String) ?? "",
            albumURI: album?["uri"] as? String,
            artworkURL: SpotifyPlayback.thumbnail(in: images),
            duration: SpotifyPlayback.number(dictionary["duration_ms"]) / 1000,
            isPlayable: playable
        )
    }
}
