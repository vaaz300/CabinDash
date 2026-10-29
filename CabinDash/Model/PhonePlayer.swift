import CabinCore
import Foundation
import SpotifyiOS
import UIKit

/// Lets the first of several answers through and turns the rest away, so a request with a time limit is finished exactly once.
@MainActor
private final class Once {
    private var done = false

    func claim() -> Bool {
        guard !done else { return false }
        done = true
        return true
    }
}

/// Plays and steers music on this iPhone through the Spotify app itself, with Spotify's iOS SDK ("App Remote").
///
/// This is the only way Cabin Dash talks to the Spotify app on this phone. Spotify's web service is used for browsing and
/// for a TV or speaker the person picked, never to start or steer music here: it treats this phone as a remote device, and
/// the Spotify app in the background did not reliably answer it. Earlier versions mixed the two, and the bugs lived in between.
///
/// How it behaves, following Spotify's documentation for the SDK:
/// * With a connection to the Spotify app, every request goes straight to it, with no app switch.
/// * Without one, the Spotify app may be asleep, and only Spotify's SDK can wake it: it opens Spotify with the song that was
///   tapped (so the right music starts at once), and Spotify opens Cabin Dash again by itself with a token for the connection.
///   Whatever the SDK could not express (the rest of the playlist, a shuffle) is then done through the connection.
/// * The connection is dropped when Cabin Dash leaves the screen and made again when it returns. Spotify ends it about 30
///   seconds after a pause; pressing Play then starts Spotify again, which is Spotify's documented way back.
/// * The token is kept in the keychain for most of its hour, so the connection can be made again after Cabin Dash restarts.
/// * What the app last said is playing is kept after the connection ends, so the song stays on screen (paused).
@MainActor
final class PhonePlayer: NSObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    enum Control: Equatable {
        case resume
        case pause
        case next
        case previous
        case seek(Double)
        case shuffle(Bool)
        case repeatMode(SpotifyRepeat)
        case enqueue(String)
    }

    /// What to finish once Spotify has opened Cabin Dash again and the connection is up.
    private enum AfterReturn {
        case plan(SpotifyPhone.PlayPlan)
        case control(Control)
    }

    /// Each step in plain words, for the Spotify log in Settings. Never given a token.
    var onEvent: ((String) -> Void)?
    /// Called whenever `state`, `art` or `isConnected` changes.
    var onChange: (() -> Void)?
    /// What Now Playing should say while a request is under way; nil when none is.
    var onStarting: ((String?) -> Void)?
    /// A short message worth a toast.
    var onProblem: ((String) -> Void)?
    /// Looks up a song's album picture in Spotify's catalogue.
    var lookUpArt: ((String) async -> TrackArt?)?

    /// True while the connection to the Spotify app is up.
    private(set) var isConnected = false
    /// What the Spotify app last said it is playing. Kept after the connection ends.
    private(set) var state: RemotePlayback?
    /// When `state` was last told, so the position can count on from there.
    private(set) var stateObservedAt = Date()
    /// The album picture of the song in `state`, once looked up.
    private(set) var art: TrackArt?

    /// What Now Playing shows: the Spotify app's word, adjusted while Cabin Dash plays a list itself (`run`): skipping is
    /// possible, and shuffle and repeat all are the list's own. The Spotify app only ever sees one song of that list, and
    /// starting each song resets its shuffle, which is why the button went dark on the next song.
    var shownState: RemotePlayback? {
        guard var shown = state else { return nil }
        if let run {
            shown.canSkipNext = true
            shown.canSkipPrevious = true
            shown.canToggleShuffle = true
            shown.isShuffling = run.isShuffled
            if run.repeatsAll, shown.repeatMode == .off { shown.repeatMode = .context }
        }
        return shown
    }

    private var remote: SPTAppRemote?
    private var clientID = ""
    private var token: String?
    /// True from opening Spotify until it answers (or the person comes back without an answer).
    private var waitingForSpotify = false
    private var connecting = false
    private var connectAttempt = 0
    /// Connection failures are only worth a log line when a connection was asked for, not on every return to the screen.
    private var expectingConnection = false
    private var afterReturn: AfterReturn?
    private var lookingUpArtFor: String?
    private var startingToken = 0
    /// A list Cabin Dash is playing itself because the Spotify app would not play it as a whole (see `SongRun`).
    private var run: SongRun?
    /// True once the Spotify app has spoken on the current connection, so a change of song is one seen as it happened.
    private var watchingLive = false
    /// True when the Spotify app is known to be asleep (it ended the connection, or would not take one). A press then opens
    /// Spotify at once instead of first trying to reconnect.
    private var asleep = false

    private static let tokenAccount = "spotify-app-remote-token"
    /// Spotify's tokens for its app last an hour. A saved one is trusted for a little less.
    private static let tokenLifetime: TimeInterval = 55 * 60

    private struct SavedToken: Codable {
        var value: String
        var savedAt: Date
    }

    override init() {
        super.init()
        if let data = KeychainStore.read(account: Self.tokenAccount),
           let saved = try? JSONDecoder().decode(SavedToken.self, from: data),
           Date().timeIntervalSince(saved.savedAt) < Self.tokenLifetime {
            token = saved.value
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    func configure(clientID: String) {
        self.clientID = clientID
    }

    // MARK: Playing

    /// Plays what was tapped: straight away when connected, otherwise by starting Spotify with the tapped song.
    func play(_ plan: SpotifyPhone.PlayPlan) {
        run = nil
        if isConnected {
            Task { await self.run(plan, afterHandOver: false) }
        } else {
            handOver(uri: plan.handOverURI, then: .plan(plan))
        }
    }

    /// The "This iPhone" row: plays here. Connected, the Spotify app resumes; otherwise Spotify is started with its last song.
    func startHere() {
        run = nil
        if isConnected {
            send(.resume)
        } else {
            handOver(uri: "", then: nil)
        }
    }

    private func run(_ plan: SpotifyPhone.PlayPlan, afterHandOver: Bool) async {
        showStarting(afterHandOver ? "Finishing in Spotify\u{2026}" : "Starting playback\u{2026}")
        if let shuffle = plan.shuffle { send(.shuffle(shuffle)) }
        if afterHandOver {
            if let start = plan.afterHandOver {
                await begin(start, plan: plan)
            } else {
                startRun(plan.songs)
            }
        } else {
            await begin(plan.start, plan: plan)
        }
        await confirmPlaying()
    }

    private func begin(_ start: SpotifyPhone.PlayPlan.Start, plan: SpotifyPhone.PlayPlan) async {
        switch start {
        case .uri(let uri):
            _ = await playAddress(uri)
            startRun(plan.songs)
        case .item(let context, let index, let song):
            await playInside([context] + plan.otherContexts, index: index, song: song, songs: plan.songs)
        case .lookUp(let context, let song):
            await playInside([context], index: nil, song: song, songs: [])
        }
    }

    /// Plays a playlist, album or Liked Songs from the tapped song, trying each of the list's addresses in turn. The song's
    /// place is checked: if Spotify starts another song (its list in another order, a removed song), no other address is
    /// tried. When no address works, Cabin Dash plays `songs` itself if it has them, otherwise the tapped song on its own.
    private func playInside(_ contexts: [String], index: Int?, song: String, songs: [String]) async {
        for context in contexts {
            let asked = Date()
            guard await playItem(context, index: index, song: song) else { continue }
            if await waitForSong(song, after: asked, seconds: 4) {
                log("Playing \(context) from the tapped song")
                return
            }
            log("Spotify did not start \(context) on the tapped song")
            break
        }
        if state?.uri == song {
            // Typically after Spotify was started with the song: it is already playing.
            log("Leaving the tapped song playing")
        } else {
            _ = await playAddress(song)
        }
        startRun(songs)
    }

    /// Cabin Dash takes over playing the rest of `songs` (the first is the one playing). Nothing happens for an empty list.
    private func startRun(_ songs: [String]) {
        guard let started = SongRun(songs: songs) else { return }
        run = started
        log("Cabin Dash plays the rest of the list itself (\(songs.count) songs) while it is on screen")
    }

    /// Asks the Spotify app to play an address. True when it accepted.
    private func playAddress(_ uri: String) async -> Bool {
        guard isConnected, let player = remote?.playerAPI else { return false }
        log("Asking the Spotify app to play \(uri)")
        let once = Once()
        return await withCheckedContinuation { continuation in
            player.play(uri) { [weak self] _, error in
                let problem = error?.localizedDescription
                Task { @MainActor in
                    if let problem { self?.log("The Spotify app would not play \(uri): \(problem)") }
                    if once.claim() { continuation.resume(returning: problem == nil) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                if once.claim() { continuation.resume(returning: false) }
            }
        }
    }

    /// Asks the Spotify app to play `context` from song number `index`, looking the song's place up when it is not known.
    /// True when it accepted.
    private func playItem(_ context: String, index: Int?, song: String) async -> Bool {
        guard isConnected, let content = remote?.contentAPI, let player = remote?.playerAPI else { return false }
        log("Asking the Spotify app to play \(context) from \(index.map { "song \($0 + 1)" } ?? song)")
        let once = Once()
        return await withCheckedContinuation { continuation in
            let finish: @Sendable (Bool, String?) -> Void = { [weak self] accepted, note in
                Task { @MainActor in
                    if let note { self?.log(note) }
                    if once.claim() { continuation.resume(returning: accepted) }
                }
            }
            content.fetchContentItem(forURI: context) { result, error in
                guard let item = result as? SPTAppRemoteContentItem else {
                    finish(false, "Spotify could not open \(context): \(error?.localizedDescription ?? "no reason given")")
                    return
                }
                let startAt: (Int) -> Void = { position in
                    player.play(item, skipToTrackIndex: position) { _, error in
                        finish(error == nil, error.map { "The Spotify app would not play \(context): \($0.localizedDescription)" })
                    }
                }
                if let index {
                    startAt(index)
                    return
                }
                content.fetchChildren(of: item) { children, error in
                    let songs = (children as? [SPTAppRemoteContentItem]) ?? []
                    guard let position = songs.firstIndex(where: { $0.uri == song }) else {
                        finish(false, "The song's place in \(context) was not found\(error.map { ": \($0.localizedDescription)" } ?? "")")
                        return
                    }
                    startAt(position)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                if once.claim() { continuation.resume(returning: false) }
            }
        }
    }

    /// Waits until the Spotify app says, after `moment`, that it is on `uri`. Its word from before the request does not count.
    private func waitForSong(_ uri: String, after moment: Date, seconds: Double) async -> Bool {
        var waited = 0.0
        while waited < seconds {
            if state?.uri == uri, stateObservedAt > moment { return true }
            try? await Task.sleep(for: .milliseconds(250))
            waited += 0.25
        }
        return false
    }

    /// Waits a few seconds for the Spotify app to say it is playing, and says so if it does not.
    private func confirmPlaying() async {
        var waited = 0.0
        while waited < 6 {
            if isConnected, let state, !state.isPaused {
                endStarting()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            waited += 0.25
        }
        endStarting()
        log("Nothing is playing after the request")
        onProblem?("Spotify didn't start playing. Try again.")
    }

    // MARK: Controls

    /// Sends a control to the Spotify app. Without a connection it is made again first. If that is not possible the Spotify
    /// app is asleep: Play starts it again (Spotify's way back after a pause), skipping does the same and then skips, and a
    /// pause has nothing to do.
    func control(_ control: Control) {
        if isConnected {
            if !steerRun(control) { send(control) }
            return
        }
        Task { await self.controlWithoutConnection(control) }
    }

    /// While Cabin Dash plays a list itself, Next and Previous move through that list, and shuffle and repeat all apply to
    /// it. True when the control was dealt with here; false when it should go to the Spotify app as usual.
    private func steerRun(_ control: Control) -> Bool {
        guard var current = run else { return false }
        switch control {
        case .next:
            guard let song = current.advance() else {
                run = nil
                return false
            }
            run = current
            log("Next song of the list")
            Task { _ = await self.playAddress(song) }
            return true
        case .previous:
            switch current.back(position: currentPosition) {
            case .restart:
                run = current
                send(.seek(0))
            case .play(let song):
                run = current
                log("Previous song of the list")
                Task { _ = await self.playAddress(song) }
            }
            return true
        case .shuffle(let on):
            // The list is shuffled here; the Spotify app, playing one song of it at a time, is not told.
            current.shuffle(on)
            run = current
            log("Shuffle \(on ? "on" : "off") for the list")
            onChange?()
            return true
        case .repeatMode(let mode):
            current.repeatsAll = mode == .context
            run = current
            // The Spotify app plays one song of the list at a time; told to repeat "the list", it would repeat that song.
            if mode == .context {
                send(.repeatMode(.off))
                onChange?()
                return true
            }
            return false
        case .resume, .pause, .seek, .enqueue:
            return false
        }
    }

    /// Where the song is now, counting on from the Spotify app's last word while it plays.
    private var currentPosition: TimeInterval {
        guard let state else { return 0 }
        return state.position + (state.isPaused ? 0 : Date().timeIntervalSince(stateObservedAt))
    }

    private func controlWithoutConnection(_ control: Control) async {
        // Known to be asleep: trying to reconnect first would only add a wait before Spotify has to be opened anyway.
        if !asleep {
            connect(expecting: true)
            if await waitUntilConnected(seconds: 1.5) {
                self.control(control)
                return
            }
        }
        switch control {
        case .pause:
            if var paused = state, !paused.isPaused {
                paused.isPaused = true
                state = paused
                onChange?()
            }
        case .resume:
            handOver(uri: "", then: nil)
        case .next, .previous:
            handOver(uri: "", then: .control(control))
        case .seek, .shuffle, .repeatMode, .enqueue:
            onProblem?("Spotify is asleep. Press play first.")
        }
    }

    /// Sends a control through the connection and shows its effect at once; the Spotify app's next word corrects it if
    /// the control did not take.
    private func send(_ control: Control) {
        guard isConnected, let api = remote?.playerAPI else { return }
        var shown = state
        switch control {
        case .resume:
            api.resume(reply("resume"))
            shown?.isPaused = false
        case .pause:
            api.pause(reply("pause"))
            shown?.isPaused = true
        case .next:
            api.skip(toNext: reply("skip to the next song"))
        case .previous:
            api.skip(toPrevious: reply("go back a song"))
        case .seek(let seconds):
            api.seek(toPosition: Int(max(0, seconds) * 1000), callback: reply("seek"))
            shown?.position = max(0, seconds)
        case .shuffle(let on):
            api.setShuffle(on, callback: reply("switch shuffle \(on ? "on" : "off")"))
            shown?.isShuffling = on
        case .repeatMode(let mode):
            api.setRepeatMode(Self.sdkRepeat(mode), callback: reply("change repeat"))
            shown?.repeatMode = mode
        case .enqueue(let uri):
            api.enqueueTrackUri(uri, callback: reply("add the song to the queue"))
        }
        if shown != state {
            state = shown
            stateObservedAt = Date()
            onChange?()
        }
    }

    /// Logs a refusal, and reads the player again so what was shown at once is put right.
    private func reply(_ what: String) -> SPTAppRemoteCallback {
        { [weak self] _, error in
            guard let problem = error?.localizedDescription else { return }
            Task { @MainActor in
                self?.log("The Spotify app would not \(what): \(problem)")
                self?.readPlayer()
            }
        }
    }

    private static func sdkRepeat(_ mode: SpotifyRepeat) -> SPTAppRemotePlaybackOptionsRepeatMode {
        switch mode {
        case .off: return .off
        case .track: return .track
        case .context: return .context
        }
    }

    // MARK: Starting Spotify

    private func makeRemote() -> SPTAppRemote? {
        if let remote { return remote }
        guard !clientID.isEmpty, let redirect = URL(string: SpotifyAuth.redirectURI) else { return nil }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirect)
        let made = SPTAppRemote(configuration: configuration, logLevel: .error)
        made.delegate = self
        made.connectionParameters.accessToken = token
        remote = made
        return made
    }

    /// Opens Spotify and asks it to play `uri` (blank for the last song). Spotify opens Cabin Dash again by itself.
    private func handOver(uri: String, then next: AfterReturn?) {
        guard let remote = makeRemote() else {
            onProblem?("Spotify isn't set up in this build")
            return
        }
        afterReturn = next
        waitingForSpotify = true
        showStarting("Opening Spotify\u{2026}")
        log("Opening Spotify to play \(uri.isEmpty ? "your last song" : uri)")
        remote.authorizeAndPlayURI(uri, asRadio: false, additionalScopes: nil) { [weak self] installed in
            guard !installed else { return }
            Task { @MainActor in
                guard let self else { return }
                self.waitingForSpotify = false
                self.afterReturn = nil
                self.endStarting()
                self.log("The Spotify app is not installed")
                self.onProblem?("The Spotify app isn't installed on this iPhone")
            }
        }
    }

    /// Reads the address Spotify opens Cabin Dash with. False when it is not Spotify's answer.
    func handleIncoming(_ url: URL) -> Bool {
        guard url.scheme == SpotifyAuth.redirectScheme, let remote = makeRemote(),
              let answer = remote.authorizationParameters(from: url) else { return false }
        waitingForSpotify = false
        if let text = answer[SPTAppRemoteErrorDescriptionKey] ?? answer[SPTAppRemoteErrorKey], !text.isEmpty {
            afterReturn = nil
            endStarting()
            log("Spotify came back with a refusal: \(text)")
            onProblem?("Spotify declined: \(text)")
            return true
        }
        if let value = answer[SPTAppRemoteAccessTokenKey], !value.isEmpty {
            save(token: value)
            log("Spotify came back; connecting to it")
        } else {
            log("Spotify came back without a token")
        }
        connect(expecting: true)
        Task { await self.finishReturn() }
        return true
    }

    /// Spotify is back: wait for the connection, then finish what the hand-over could not do.
    private func finishReturn() async {
        let job = afterReturn
        afterReturn = nil
        showStarting("Connecting to Spotify\u{2026}")
        guard await waitUntilConnected(seconds: 5) else {
            endStarting()
            log("No connection to the Spotify app after it came back")
            if job != nil { onProblem?("Couldn't connect to Spotify. Settings \u{203A} Spotify log shows why.") }
            return
        }
        switch job {
        case .plan(let plan):
            await run(plan, afterHandOver: true)
        case .control(let control):
            self.control(control)
            endStarting()
        case nil:
            endStarting()
        }
    }

    private func save(token value: String) {
        token = value
        remote?.connectionParameters.accessToken = value
        if let data = try? JSONEncoder().encode(SavedToken(value: value, savedAt: Date())) {
            _ = KeychainStore.write(data, account: Self.tokenAccount)
        }
    }

    // MARK: Connection

    private func connect(expecting: Bool) {
        guard let remote = makeRemote(), let token, !connecting, !remote.isConnected else { return }
        if expecting {
            expectingConnection = true
            log("Connecting to the Spotify app")
        }
        remote.connectionParameters.accessToken = token
        connecting = true
        connectAttempt += 1
        let attempt = connectAttempt
        remote.connect()
        // An attempt that is never answered must not block the next one.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.connectAttempt == attempt, self.connecting, !self.isConnected else { return }
            self.connecting = false
            self.asleep = true
            if self.expectingConnection { self.log("The Spotify app did not answer the connection") }
        }
    }

    private func waitUntilConnected(seconds: Double) async -> Bool {
        var waited = 0.0
        while !isConnected, waited < seconds {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 0.25
        }
        return isConnected
    }

    private func setConnected(_ value: Bool) {
        if value { asleep = false } else { watchingLive = false }
        guard isConnected != value else { return }
        isConnected = value
        onChange?()
    }

    @objc private func appBecameActive() {
        guard waitingForSpotify else {
            connect(expecting: false)
            return
        }
        // Spotify normally opens Cabin Dash with its answer. If the person came back some other way, stop waiting.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.waitingForSpotify else { return }
            self.waitingForSpotify = false
            self.log("Back from Spotify without its answer")
            self.connect(expecting: true)
            await self.finishReturn()
        }
    }

    @objc private func appWillResignActive() {
        guard let remote, remote.isConnected else { return }
        remote.disconnect()
        connecting = false
        setConnected(false)
    }

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connecting = false
            self.expectingConnection = false
            self.log("Connected to the Spotify app")
            self.setConnected(true)
            self.listenToPlayer()
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let problem = error?.localizedDescription ?? "no reason given"
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connecting = false
            self.asleep = true
            if self.expectingConnection {
                self.log("Could not connect to the Spotify app: \(problem)")
                self.expectingConnection = false
            }
            self.setConnected(false)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let problem = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connecting = false
            if let problem {
                // The Spotify app ended it (after a pause it goes to sleep), as opposed to Cabin Dash leaving the screen.
                self.asleep = true
                self.log("The Spotify app ended the connection: \(problem)")
            }
            self.setConnected(false)
        }
    }

    // MARK: What the Spotify app is playing

    private func listenToPlayer() {
        guard let api = remote?.playerAPI else { return }
        api.delegate = self
        api.subscribe(toPlayerState: { [weak self] _, error in
            guard let problem = error?.localizedDescription else { return }
            Task { @MainActor in self?.log("Could not follow the Spotify app's player: \(problem)") }
        })
        readPlayer()
    }

    /// Asks the Spotify app what it is playing now.
    private func readPlayer() {
        guard isConnected, let api = remote?.playerAPI else { return }
        api.getPlayerState { [weak self] result, error in
            guard error == nil, let state = result as? SPTAppRemotePlayerState else { return }
            let snapshot = Self.snapshot(of: state)
            Task { @MainActor in self?.receive(snapshot) }
        }
    }

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let snapshot = Self.snapshot(of: playerState)
        Task { @MainActor [weak self] in self?.receive(snapshot) }
    }

    private func receive(_ snapshot: RemotePlayback) {
        let newSong = snapshot.uri != state?.uri
        if newSong || snapshot.isPaused != state?.isPaused {
            log("Spotify app: \(snapshot.isPaused ? "paused" : "playing") \(snapshot.title.isEmpty ? snapshot.uri : snapshot.title)")
        }
        let firstWordOnThisConnection = !watchingLive
        watchingLive = true
        state = snapshot
        stateObservedAt = Date()
        if !snapshot.uri.isEmpty {
            if firstWordOnThisConnection {
                checkRunAfterReconnecting(to: snapshot.uri)
            } else if newSong {
                followRun(to: snapshot.uri)
            }
        }
        onChange?()
        if newSong { fetchArt(for: snapshot.uri) }
    }

    /// On reconnecting, the Spotify app may have moved on while Cabin Dash was away. Its song then is not a change Cabin Dash
    /// saw happen, so it is not acted on: the list goes on if the song is one of its own, and ends otherwise.
    private func checkRunAfterReconnecting(to uri: String) {
        guard var current = run else { return }
        if current.songs.contains(uri) {
            _ = current.spotifyMoved(to: uri)
            run = current
        } else {
            run = nil
            log("Spotify moved on while Cabin Dash was away; Cabin Dash stops playing its list")
        }
    }

    /// Keeps a list Cabin Dash plays itself going: when the Spotify app, watched live, moves from the list's song to one of
    /// its own picks, the list's next song is played.
    private func followRun(to uri: String) {
        guard var current = run else { return }
        switch current.spotifyMoved(to: uri) {
        case .keep:
            run = current
        case .play(let next):
            run = current
            log("The list's song ended; playing its next song")
            Task { _ = await self.playAddress(next) }
        case .stop:
            run = nil
            log("End of the list")
        }
    }

    private func fetchArt(for uri: String) {
        guard art?.uri != uri, lookingUpArtFor != uri, uri.hasPrefix("spotify:track:"), let lookUpArt else { return }
        lookingUpArtFor = uri
        Task { [weak self] in
            let found = await lookUpArt(uri)
            guard let self, self.lookingUpArtFor == uri else { return }
            self.lookingUpArtFor = nil
            if let found {
                self.art = found
                self.onChange?()
            }
        }
    }

    /// Plain values out of the Spotify app's player state, taken at once because the state itself is not safe to pass around.
    nonisolated private static func snapshot(of state: SPTAppRemotePlayerState) -> RemotePlayback {
        let track = state.track
        let options = state.playbackOptions
        let rules = state.playbackRestrictions
        let repeatMode: SpotifyRepeat
        switch options.repeatMode {
        case .track: repeatMode = .track
        case .context: repeatMode = .context
        default: repeatMode = .off
        }
        return RemotePlayback(
            uri: track.uri,
            title: track.name,
            artist: track.artist.name,
            album: track.album.name,
            duration: TimeInterval(track.duration) / 1000,
            position: TimeInterval(state.playbackPosition) / 1000,
            isPaused: state.isPaused,
            isShuffling: options.isShuffling,
            repeatMode: repeatMode,
            isAdvertisement: track.isAdvertisement,
            canSkipNext: rules.canSkipNext,
            canSkipPrevious: rules.canSkipPrevious,
            canSeek: rules.canSeek,
            canToggleShuffle: rules.canToggleShuffle,
            canRepeatTrack: rules.canRepeatTrack,
            canRepeatContext: rules.canRepeatContext
        )
    }

    // MARK: Signing out and messages

    /// Forgets what was playing, for a sign-out.
    func forget() {
        state = nil
        art = nil
        run = nil
        afterReturn = nil
        endStarting()
        onChange?()
    }

    private func log(_ text: String) {
        onEvent?(text)
    }

    private func showStarting(_ text: String) {
        startingToken += 1
        let token = startingToken
        onStarting?(text)
        // Whatever goes wrong, the message does not stay up for good.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, self.startingToken == token else { return }
            self.onStarting?(nil)
        }
    }

    private func endStarting() {
        startingToken += 1
        onStarting?(nil)
    }
}
