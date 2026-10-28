import Foundation

/// What the Spotify app on this iPhone says it is playing, told to Cabin Dash over the connection to it (Spotify's "App Remote").
/// It is the app's own word, not the web service's, so it is still right when the web service has lost track of the phone.
public struct RemotePlayback: Equatable, Sendable {
    /// The song's or episode's address. Empty when the app has nothing loaded.
    public var uri: String
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds.
    public var duration: TimeInterval
    /// Seconds into the song when the app said so.
    public var position: TimeInterval
    public var isPaused: Bool
    public var isShuffling: Bool
    public var contextURI: String?
    public var isAdvertisement: Bool

    public init(
        uri: String, title: String, artist: String = "", album: String = "", duration: TimeInterval = 0,
        position: TimeInterval = 0, isPaused: Bool = false, isShuffling: Bool = false, contextURI: String? = nil,
        isAdvertisement: Bool = false
    ) {
        self.uri = uri
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPaused = isPaused
        self.isShuffling = isShuffling
        self.contextURI = contextURI
        self.isAdvertisement = isAdvertisement
    }
}

extension SpotifyPlayback {
    /// What Now Playing shows. Spotify's web service answers first because it knows the most (the picture, what may be
    /// skipped, repeat). When it says nothing is playing but the Spotify app on this iPhone is connected and has a song loaded,
    /// that song is shown instead, as playing on `phoneName`.
    ///
    /// `previous` is what was shown before: its picture and album are kept when it is the same song, since the app's word has none.
    /// Shuffle and repeat go through the web service, which does not know about this phone then, so they are marked off-limits.
    public static func merged(web: NowPlaying?, remote: RemotePlayback?, phoneName: String?, previous: NowPlaying?) -> NowPlaying? {
        if let web { return web }
        guard let remote, !remote.uri.isEmpty else { return nil }
        let same = previous?.uri == remote.uri ? previous : nil
        var blocked: Set<String> = ["toggling_shuffle", "toggling_repeat_context", "toggling_repeat_track"]
        if remote.isAdvertisement { blocked.formUnion(["skipping_next", "skipping_prev", "seeking"]) }
        return NowPlaying(
            trackID: same?.trackID,
            title: remote.title,
            subtitle: remote.artist,
            album: remote.album,
            artworkURL: same?.artworkURL,
            duration: remote.duration,
            progress: remote.position,
            isPlaying: !remote.isPaused,
            deviceName: phoneName ?? "This iPhone",
            uri: remote.uri,
            albumURI: same?.albumURI,
            contextURI: remote.contextURI,
            shuffle: remote.isShuffling,
            repeatMode: .off,
            disallows: blocked
        )
    }
}
