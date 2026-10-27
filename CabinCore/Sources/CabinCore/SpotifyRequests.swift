import Foundation

/// One call to Spotify's Web API, described as plain values so the paths, queries and bodies can be tested without the network.
public struct SpotifyRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?

    public init(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }

    /// The full address, with every query name and value percent-escaped.
    public func url() -> URL? {
        var address = "https://api.spotify.com" + path
        if !query.isEmpty {
            address += "?" + FormEncoding.encode(query.map { ($0.name, $0.value ?? "") })
        }
        return URL(string: address)
    }
}

/// Spotify's three repeat settings.
public enum SpotifyRepeat: String, CaseIterable, Sendable {
    case off
    case context
    case track

    /// Anything Spotify sends that is not one of the three words counts as off.
    public init(spotifyValue: String?) {
        self = SpotifyRepeat(rawValue: spotifyValue ?? "") ?? .off
    }

    /// What one tap of the repeat button changes it to.
    public var next: SpotifyRepeat {
        switch self {
        case .off: return .context
        case .context: return .track
        case .track: return .off
        }
    }

    public var title: String {
        switch self {
        case .off: return "Repeat off"
        case .context: return "Repeat all"
        case .track: return "Repeat one"
        }
    }

    /// An SF Symbol name.
    public var symbol: String {
        self == .track ? "repeat.1" : "repeat"
    }
}

/// What to start playing.
public enum SpotifyPlayTarget: Equatable, Sendable {
    /// An album or playlist, optionally starting at one of its tracks.
    case context(uri: String, startAtURI: String?)
    /// A list of tracks, played in order.
    case uris([String])

    /// Up to `limit` tracks from `index` on, so a long list can start at the track that was tapped.
    /// An index outside the list is moved to its nearest end.
    public static func window(_ uris: [String], startingAt index: Int, limit: Int = 100) -> SpotifyPlayTarget {
        guard !uris.isEmpty, limit > 0 else { return .uris([]) }
        let start = min(max(0, index), uris.count - 1)
        return .uris(Array(uris[start..<min(uris.count, start + limit)]))
    }
}

/// Every Web API call Cabin Dash makes.
public enum SpotifyEndpoint {
    /// Lists are read this many at a time.
    public static let pageSize = 50
    /// Spotify's cap for search in development mode (February 2026).
    public static let searchLimit = 10
    /// Spotify accepts at most this many items in one library call.
    public static let libraryLimit = 40

    // MARK: Player

    public static func player() -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/me/player", query: [URLQueryItem(name: "additional_types", value: "track,episode")])
    }

    public static func resume(deviceID: String? = nil) -> SpotifyRequest {
        SpotifyRequest(method: "PUT", path: "/v1/me/player/play", query: device(deviceID))
    }

    public static func pause() -> SpotifyRequest {
        SpotifyRequest(method: "PUT", path: "/v1/me/player/pause")
    }

    public static func play(_ target: SpotifyPlayTarget, deviceID: String? = nil) -> SpotifyRequest {
        var object: [String: Any]
        switch target {
        case .context(let uri, let startAtURI):
            object = ["context_uri": uri]
            if let startAtURI { object["offset"] = ["uri": startAtURI] }
        case .uris(let uris):
            object = ["uris": uris]
        }
        return SpotifyRequest(method: "PUT", path: "/v1/me/player/play", query: device(deviceID), body: json(object))
    }

    public static func next() -> SpotifyRequest {
        SpotifyRequest(method: "POST", path: "/v1/me/player/next")
    }

    public static func previous() -> SpotifyRequest {
        SpotifyRequest(method: "POST", path: "/v1/me/player/previous")
    }

    public static func seek(milliseconds: Int) -> SpotifyRequest {
        SpotifyRequest(method: "PUT", path: "/v1/me/player/seek", query: [URLQueryItem(name: "position_ms", value: String(milliseconds))])
    }

    public static func shuffle(_ on: Bool) -> SpotifyRequest {
        SpotifyRequest(method: "PUT", path: "/v1/me/player/shuffle", query: [URLQueryItem(name: "state", value: on ? "true" : "false")])
    }

    public static func setRepeat(_ mode: SpotifyRepeat) -> SpotifyRequest {
        SpotifyRequest(method: "PUT", path: "/v1/me/player/repeat", query: [URLQueryItem(name: "state", value: mode.rawValue)])
    }

    public static func queue() -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/me/player/queue")
    }

    public static func addToQueue(uri: String) -> SpotifyRequest {
        SpotifyRequest(method: "POST", path: "/v1/me/player/queue", query: [URLQueryItem(name: "uri", value: uri)])
    }

    public static func devices() -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/me/player/devices")
    }

    public static func transfer(to deviceID: String, play: Bool) -> SpotifyRequest {
        SpotifyRequest(method: "PUT", path: "/v1/me/player", body: json(["device_ids": [deviceID], "play": play]))
    }

    // MARK: The person's library

    public static func profile() -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/me")
    }

    public static func playlists(offset: Int) -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/me/playlists", query: page(offset))
    }

    public static func playlistItems(id: String, offset: Int) -> SpotifyRequest {
        SpotifyRequest(
            method: "GET",
            path: "/v1/playlists/" + FormEncoding.escape(id) + "/items",
            query: page(offset) + [URLQueryItem(name: "additional_types", value: "track,episode")]
        )
    }

    public static func savedTracks(offset: Int) -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/me/tracks", query: page(offset))
    }

    public static func search(_ text: String) -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/search", query: [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "type", value: "track,album,playlist"),
            URLQueryItem(name: "limit", value: String(searchLimit))
        ])
    }

    public static func save(uris: [String]) -> SpotifyRequest {
        SpotifyRequest(method: "PUT", path: "/v1/me/library", query: library(uris))
    }

    public static func remove(uris: [String]) -> SpotifyRequest {
        SpotifyRequest(method: "DELETE", path: "/v1/me/library", query: library(uris))
    }

    public static func contains(uris: [String]) -> SpotifyRequest {
        SpotifyRequest(method: "GET", path: "/v1/me/library/contains", query: library(uris))
    }

    // MARK: Helpers

    private static func device(_ id: String?) -> [URLQueryItem] {
        id.map { [URLQueryItem(name: "device_id", value: $0)] } ?? []
    }

    private static func page(_ offset: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(pageSize)), URLQueryItem(name: "offset", value: String(max(0, offset)))]
    }

    private static func library(_ uris: [String]) -> [URLQueryItem] {
        [URLQueryItem(name: "uris", value: uris.prefix(libraryLimit).joined(separator: ","))]
    }

    /// Keys sorted so the same request always produces the same bytes.
    private static func json(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
