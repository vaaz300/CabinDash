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
    /// What Now Playing shows.
    ///
    /// Spotify's web service answers first because it knows the most (the picture, what may be skipped, repeat), unless the
    /// music is on this iPhone and the Spotify app, which Cabin Dash is connected to, says otherwise: the app is right about
    /// what it is doing. The web service kept saying "playing" for a phone whose app had stopped. For the same song only
    /// whether it is playing and where it is are taken from the app; for another song, the app's song is shown.
    ///
    /// When the web service says nothing is playing but the app has a song loaded, that song is shown, as playing on `phoneName`.
    ///
    /// `previous` is what was shown before: its picture and album are kept when it is the same song, since the app's word has none.
    /// Shuffle and repeat go through the web service, which does not know about this phone then, so they are marked off-limits.
    public static func merged(web: NowPlaying?, remote: RemotePlayback?, phoneName: String?, previous: NowPlaying?) -> NowPlaying? {
        let app = (remote?.uri.isEmpty ?? true) ? nil : remote
        if let web {
            guard let app, let phoneName, web.deviceName == phoneName else { return web }
            if web.uri == app.uri {
                var corrected = web
                corrected.isPlaying = !app.isPaused
                corrected.progress = app.position
                return corrected
            }
            return shown(from: app, on: phoneName, previous: previous)
        }
        guard let app else { return nil }
        return shown(from: app, on: phoneName ?? "This iPhone", previous: previous)
    }

    /// Whether play, pause, skip and seek should go to the Spotify app rather than the web service: Cabin Dash is connected
    /// to the app, the app has a song, and either nothing else is named by the web service or it names this phone.
    /// Music on a TV or speaker is never steered through the phone.
    public static func controlsGoToApp(web: NowPlaying?, remote: RemotePlayback?, phoneName: String?, connected: Bool) -> Bool {
        guard connected, let remote, !remote.uri.isEmpty else { return false }
        guard let web else { return true }
        guard let phoneName else { return false }
        return web.deviceName == phoneName
    }

    private static func shown(from app: RemotePlayback, on phoneName: String, previous: NowPlaying?) -> NowPlaying {
        let same = previous?.uri == app.uri ? previous : nil
        var blocked: Set<String> = ["toggling_shuffle", "toggling_repeat_context", "toggling_repeat_track"]
        if app.isAdvertisement { blocked.formUnion(["skipping_next", "skipping_prev", "seeking"]) }
        return NowPlaying(
            trackID: same?.trackID,
            title: app.title,
            subtitle: app.artist,
            album: app.album,
            artworkURL: same?.artworkURL,
            duration: app.duration,
            progress: app.position,
            isPlaying: !app.isPaused,
            deviceName: phoneName,
            uri: app.uri,
            albumURI: same?.albumURI,
            contextURI: app.contextURI,
            shuffle: app.isShuffling,
            repeatMode: .off,
            disallows: blocked
        )
    }
}
