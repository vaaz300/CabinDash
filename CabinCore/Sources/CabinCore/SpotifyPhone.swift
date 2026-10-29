import Foundation

/// What the Spotify app on this iPhone says it is playing, told over the connection to it (Spotify's iOS SDK, "App Remote").
/// Plain values, copied out of the SDK's player state at once.
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
    public var repeatMode: SpotifyRepeat
    /// The playlist, album or Liked Songs it is playing from.
    public var contextURI: String?
    public var isAdvertisement: Bool
    public var canSkipNext: Bool
    public var canSkipPrevious: Bool
    public var canSeek: Bool
    public var canToggleShuffle: Bool
    public var canRepeatTrack: Bool
    public var canRepeatContext: Bool

    public init(
        uri: String, title: String, artist: String = "", album: String = "", duration: TimeInterval = 0,
        position: TimeInterval = 0, isPaused: Bool = false, isShuffling: Bool = false, repeatMode: SpotifyRepeat = .off,
        contextURI: String? = nil, isAdvertisement: Bool = false, canSkipNext: Bool = true, canSkipPrevious: Bool = true,
        canSeek: Bool = true, canToggleShuffle: Bool = true, canRepeatTrack: Bool = true, canRepeatContext: Bool = true
    ) {
        self.uri = uri
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPaused = isPaused
        self.isShuffling = isShuffling
        self.repeatMode = repeatMode
        self.contextURI = contextURI
        self.isAdvertisement = isAdvertisement
        self.canSkipNext = canSkipNext
        self.canSkipPrevious = canSkipPrevious
        self.canSeek = canSeek
        self.canToggleShuffle = canToggleShuffle
        self.canRepeatTrack = canRepeatTrack
        self.canRepeatContext = canRepeatContext
    }
}

/// A song's album picture and album, read from Spotify's catalogue: the Spotify app's word on a song has no picture address.
public struct TrackArt: Equatable, Sendable {
    public var uri: String
    public var artworkURL: URL?
    public var albumURI: String?

    public init(uri: String, artworkURL: URL? = nil, albumURI: String? = nil) {
        self.uri = uri
        self.artworkURL = artworkURL
        self.albumURI = albumURI
    }
}

/// Music on this iPhone goes through one channel: the connection to the Spotify app. Spotify's web service is used for
/// browsing and for a TV or speaker the person picked. Earlier versions mixed the two for this phone, and every problem
/// lived in the gap between them.
public enum SpotifyPhone {
    /// Where Now Playing's song comes from.
    public enum Source: Equatable, Sendable {
        /// The Spotify app on this iPhone said so. `live` is false once the connection has ended: the song stays on screen,
        /// shown as paused, because Spotify ends the connection soon after a pause.
        case phone(RemotePlayback, live: Bool)
        /// Spotify's web service sees this phone playing while Cabin Dash is not connected to the Spotify app.
        case phoneByWeb(NowPlaying)
        /// Music on a TV, speaker or computer, as Spotify's web service reports it.
        case otherDevice(NowPlaying)
        case nothing
    }

    /// Which source Now Playing shows.
    ///
    /// With a TV or speaker picked, only the web service. Otherwise, in order: the connected Spotify app (unless it is paused
    /// while something plays on another device); music playing on another device; the web service's view of this phone;
    /// the last song the Spotify app named; a paused song on another device; nothing.
    public static func source(
        otherDeviceChosen: Bool, connected: Bool, app: RemotePlayback?, web: NowPlaying?, phoneName: String?
    ) -> Source {
        if otherDeviceChosen {
            return web.map { .otherDevice($0) } ?? .nothing
        }
        let song = (app?.uri.isEmpty ?? true) ? nil : app
        let elsewhere = web.flatMap { isThisPhone($0, phoneName: phoneName) ? nil : $0 }
        let here = web.flatMap { isThisPhone($0, phoneName: phoneName) ? $0 : nil }

        if connected, let song {
            if song.isPaused, let elsewhere, elsewhere.isPlaying { return .otherDevice(elsewhere) }
            return .phone(song, live: true)
        }
        if let elsewhere, elsewhere.isPlaying { return .otherDevice(elsewhere) }
        if let here { return .phoneByWeb(here) }
        if let song { return .phone(song, live: false) }
        if let elsewhere { return .otherDevice(elsewhere) }
        return .nothing
    }

    /// Whether the web service's answer is about this iPhone: a smartphone, with this phone's name once it is known.
    public static func isThisPhone(_ web: NowPlaying, phoneName: String?) -> Bool {
        guard web.deviceType == "Smartphone" else { return false }
        guard let phoneName else { return true }
        return web.deviceName == phoneName
    }

    /// True when the buttons go to the Spotify app on this iPhone, false when they go to the web service: the device whose
    /// music is on screen is the one steered, and a TV or speaker the person picked is always steered by the web service.
    /// The web service's view of this phone, with no connection to the Spotify app, is steered by the web service while the
    /// phone is playing (its Spotify app is awake then and answers). Paused, the app may be asleep, and only the Spotify app
    /// route can wake it.
    public static func steersPhone(_ source: Source, otherDeviceChosen: Bool, connected: Bool) -> Bool {
        if otherDeviceChosen { return false }
        switch source {
        case .otherDevice: return false
        case .phoneByWeb(let web): return connected || !web.isPlaying
        case .phone, .nothing: return true
        }
    }

    /// Now Playing from the Spotify app's word. The picture comes from Spotify's catalogue and is used only for its own song.
    public static func nowPlaying(from app: RemotePlayback, live: Bool, deviceName: String, art: TrackArt?) -> NowPlaying {
        let picture = art?.uri == app.uri ? art : nil
        var blocked = Set<String>()
        if !app.canSkipNext || app.isAdvertisement { blocked.insert("skipping_next") }
        if !app.canSkipPrevious || app.isAdvertisement { blocked.insert("skipping_prev") }
        if !app.canSeek || app.isAdvertisement { blocked.insert("seeking") }
        if !app.canToggleShuffle { blocked.insert("toggling_shuffle") }
        if !app.canRepeatTrack { blocked.insert("toggling_repeat_track") }
        if !app.canRepeatContext { blocked.insert("toggling_repeat_context") }
        let parts = app.uri.split(separator: ":", omittingEmptySubsequences: false)
        let trackID = parts.count == 3 && parts[1] == "track" ? String(parts[2]) : nil
        return NowPlaying(
            trackID: trackID,
            title: app.title,
            subtitle: app.artist,
            album: app.album,
            artworkURL: picture?.artworkURL,
            duration: app.duration,
            progress: app.position,
            isPlaying: live && !app.isPaused,
            deviceName: deviceName,
            deviceType: "Smartphone",
            uri: app.uri,
            albumURI: picture?.albumURI,
            contextURI: app.contextURI,
            shuffle: app.isShuffling,
            repeatMode: app.repeatMode,
            disallows: blocked
        )
    }

    /// What a tap on Play asks the Spotify app on this iPhone to do.
    public struct PlayPlan: Equatable, Sendable {
        public enum Start: Equatable, Sendable {
            /// A playlist or album from its start, or one song on its own.
            case uri(String)
            /// A playlist, album or Liked Songs, from the tapped song at `index`.
            case item(context: String, index: Int, song: String)
            /// An album from the tapped song, whose place in the album is looked up first.
            case lookUp(context: String, song: String)
        }

        public var start: Start
        /// Shuffle is switched to this before playing. Nil leaves it as it is.
        public var shuffle: Bool?
        /// What Spotify's SDK is asked to play when the Spotify app has to be started: the tapped song itself, so the right
        /// music starts at once.
        public var handOverURI: String
        /// Other addresses of the same list, tried in order when the Spotify app does not accept the one in `start`.
        /// Liked Songs has two.
        public var otherContexts: [String]
        /// The songs, from the tapped one on, that Cabin Dash plays one after another itself when the Spotify app accepts
        /// none of the list's addresses (see `SongRun`). Empty for a playlist or album, which the Spotify app always takes.
        public var songs: [String]

        public init(start: Start, shuffle: Bool?, handOverURI: String, otherContexts: [String] = [], songs: [String] = []) {
            self.start = start
            self.shuffle = shuffle
            self.handOverURI = handOverURI
            self.otherContexts = otherContexts
            self.songs = songs
        }

        /// What is still to be done once the started Spotify app is connected: playing the song inside its playlist, album
        /// or Liked Songs (the song starts again, once, in its place). Nil when the hand-over already played everything.
        public var afterHandOver: Start? {
            if case .uri = start { return nil }
            return start
        }
    }

    /// The request for a tap on Play. `index` is the tapped song's place in the list it was tapped in, when known;
    /// `likedCollection` is the person's own Liked Songs address (with their account id), used for a list tapped in Liked
    /// Songs together with Liked Songs' general address. Nil when there is nothing to play.
    public static func plan(for target: SpotifyPlayTarget, shuffled: Bool, index: Int?, likedCollection: String?) -> PlayPlan? {
        switch target {
        case .context(let uri, let startAt):
            guard let song = startAt else {
                // The Play and Shuffle buttons: Play means in order, so shuffle is set either way.
                return PlayPlan(start: .uri(uri), shuffle: shuffled, handOverURI: uri)
            }
            let start: PlayPlan.Start = index.map { .item(context: uri, index: $0, song: song) } ?? .lookUp(context: uri, song: song)
            return PlayPlan(start: start, shuffle: shuffled ? true : nil, handOverURI: song)
        case .uris(let uris):
            guard let first = uris.first else { return nil }
            let shuffle: Bool? = shuffled ? true : nil
            guard uris.count > 1 else { return PlayPlan(start: .uri(first), shuffle: shuffle, handOverURI: first) }
            guard let index else { return PlayPlan(start: .uri(first), shuffle: shuffle, handOverURI: first, songs: uris) }
            let addresses = [likedCollection, likedSongsAddress].compactMap { $0 }
            return PlayPlan(
                start: .item(context: addresses[0], index: index, song: first), shuffle: shuffle, handOverURI: first,
                otherContexts: Array(addresses.dropFirst()), songs: uris
            )
        }
    }

    /// Liked Songs' general address, which the Spotify app opens as the signed-in person's Liked Songs.
    public static let likedSongsAddress = "spotify:collection:tracks"

    /// The address of the person's Liked Songs, which the Spotify app plays like a playlist.
    public static func likedCollectionURI(userID: String) -> String {
        "spotify:user:\(userID):collection"
    }
}

/// Songs Cabin Dash plays one after another itself, for a list the Spotify app will not play as a whole (Liked Songs, when
/// neither of its addresses is accepted). Cabin Dash watches the Spotify app: when it moves past the run's song to one of
/// its own picks (the song ended, or was skipped from the lock screen or the car), the run's next song is played. It works
/// only while Cabin Dash is on screen to see that happen.
public struct SongRun: Equatable, Sendable {
    /// The songs in the order they will play.
    public private(set) var songs: [String]
    /// Where playback is in `songs`.
    public private(set) var index: Int
    /// Repeat all: after the last song comes the first.
    public var repeatsAll = false
    /// The order before shuffling.
    private var inOrder: [String]

    public init?(songs: [String], start: Int = 0) {
        guard songs.indices.contains(start) else { return nil }
        self.songs = songs
        self.index = start
        self.inOrder = songs
    }

    public var current: String { songs[index] }

    public enum Step: Equatable, Sendable {
        /// Nothing to do.
        case keep
        /// Play this song.
        case play(String)
        /// The run is over; Spotify carries on with its own picks.
        case stop
    }

    /// The Spotify app, watched live, moved to `uri`. Inside the run that is simply where playback is now; anything else
    /// means the run's song is over, and its next song should play.
    public mutating func spotifyMoved(to uri: String) -> Step {
        if let found = songs.firstIndex(of: uri) {
            index = found
            return .keep
        }
        return advance().map { .play($0) } ?? .stop
    }

    /// The next song (the Next button, or the end of a song). Nil after the last one, unless repeating all.
    public mutating func advance() -> String? {
        if index + 1 < songs.count {
            index += 1
            return songs[index]
        }
        guard repeatsAll else { return nil }
        index = 0
        return songs[0]
    }

    public enum Back: Equatable, Sendable {
        case restart
        case play(String)
    }

    /// The Previous button: the song starts again once it has played for more than three seconds, as in Spotify;
    /// earlier than that it goes to the song before. The first song starts again.
    public mutating func back(position: TimeInterval) -> Back {
        guard position <= 3, index > 0 else { return .restart }
        index -= 1
        return .play(songs[index])
    }

    /// Shuffles the songs that have not played yet, or puts the list back in its order. The song playing stays playing.
    public mutating func shuffle(_ on: Bool) {
        var generator = SystemRandomNumberGenerator()
        shuffle(on, using: &generator)
    }

    public mutating func shuffle<Generator: RandomNumberGenerator>(_ on: Bool, using generator: inout Generator) {
        let playing = current
        if on {
            let played = songs[...index]
            let rest = songs[(index + 1)...].shuffled(using: &generator)
            songs = Array(played) + rest
        } else {
            songs = inOrder
            index = songs.firstIndex(of: playing) ?? 0
        }
    }
}
