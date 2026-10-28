import CabinCore
import Foundation
import SpotifyiOS
import UIKit

/// Starts the Spotify app on this iPhone, brings the person straight back, and stays connected to it, using Spotify's iOS SDK.
///
/// Spotify lists this iPhone as a place to play only while its own app is running, and the Web API cannot start it.
/// The SDK's `authorizeAndPlayURI` can: it opens Spotify, Spotify plays the address it was given (a blank address means the
/// last song), and Spotify then opens Cabin Dash again by itself, so nobody has to switch apps by hand.
///
/// Spotify's documentation asks for one more step, and skipping it is what made every hop ask for permission again: once
/// Spotify has handed back a token, connect to it ("App Remote"). A connected Spotify app stays awake, and Spotify then
/// remembers the app for 24 hours instead of asking again. The connection is dropped when Cabin Dash leaves the screen and
/// made again when it returns, as Spotify's sample app does.
///
/// What plays, the queue, the library and the device list all still go through the Web API. The connection is also used for
/// two things the Web API cannot be relied on for on this phone: it is the app's own word on what is playing (the web
/// service has answered "nothing is playing" while the app was playing), and it carries play, pause, skip and seek for that case.
@MainActor
final class SpotifyWake: NSObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    enum Outcome: Equatable {
        /// Spotify opened Cabin Dash again and said it went well.
        case returned
        /// Spotify opened Cabin Dash again with a complaint, in Spotify's words.
        case refused(String)
    }

    /// Told each step in plain words, for the Spotify log in Settings. Never given a token.
    var onEvent: ((String) -> Void)?
    /// Told what the Spotify app is playing whenever that changes, and nil when the connection is gone.
    var onPlayback: ((RemotePlayback?) -> Void)?

    /// True while the connection to the Spotify app is up: Spotify is running and will answer.
    private(set) var isConnected = false

    /// Kept for as long as the app runs, so Spotify sees the same app each time and the connection can be remade.
    private var remote: SPTAppRemote?
    private var clientID = ""
    private var accessToken: String?
    /// True from the moment Spotify is asked to start until it answers.
    private var waiting = false
    /// True from asking for a connection until it succeeds or fails, so a second ask is not sent on top of the first.
    private var connecting = false
    /// Failures to connect are only worth a log line when one was expected, not every time the app comes back to the screen.
    private var expectingConnection = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    private func makeRemote(for clientID: String) -> SPTAppRemote? {
        if let remote, self.clientID == clientID { return remote }
        guard let redirect = URL(string: SpotifyAuth.redirectURI) else { return nil }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirect)
        let made = SPTAppRemote(configuration: configuration, logLevel: .error)
        made.delegate = self
        made.connectionParameters.accessToken = accessToken
        remote = made
        self.clientID = clientID
        return made
    }

    /// Opens Spotify and asks it to play `uri` (a song, album or playlist address; blank for the last song).
    /// `onNotInstalled` runs if there is no Spotify app on this iPhone to open.
    func start(clientID: String, uri: String = "", onNotInstalled: @escaping () -> Void) {
        guard let remote = makeRemote(for: clientID) else { return }
        waiting = true
        onEvent?("Opening Spotify to play \(uri.isEmpty ? "your last song" : uri)")
        remote.authorizeAndPlayURI(uri, asRadio: false, additionalScopes: nil) { [weak self] installed in
            guard !installed else { return }
            Task { @MainActor in
                self?.waiting = false
                self?.onEvent?("The Spotify app is not installed")
                onNotInstalled()
            }
        }
    }

    /// Reads the address Spotify opens Cabin Dash with. Nil when it is not the answer to `start`, such as any other link.
    /// A token in the answer is used at once to connect to the Spotify app.
    func finish(with url: URL) -> Outcome? {
        guard waiting, let remote, let answer = remote.authorizationParameters(from: url) else { return nil }
        waiting = false
        if let text = answer[SPTAppRemoteErrorDescriptionKey] ?? answer[SPTAppRemoteErrorKey], !text.isEmpty {
            onEvent?("Spotify came back with a refusal: \(text)")
            return .refused(text)
        }
        guard let token = answer[SPTAppRemoteAccessTokenKey], !token.isEmpty else {
            onEvent?("Spotify came back without a token")
            return .returned
        }
        accessToken = token
        remote.connectionParameters.accessToken = token
        onEvent?("Spotify came back; connecting to it")
        expectingConnection = true
        connect()
        return .returned
    }

    /// Waits until the connection is up. False if it is not up after `seconds`.
    func waitUntilConnected(seconds: Double) async -> Bool {
        let step = 0.25
        var waited = 0.0
        while !isConnected, waited < seconds {
            try? await Task.sleep(for: .seconds(step))
            waited += step
        }
        return isConnected
    }

    // MARK: Controls through the connection

    /// Each of these asks the Spotify app directly and returns false when there is no connection to ask through. The result
    /// arrives as a change in what the app says is playing, so there is nothing to wait for.

    func resume() -> Bool { send("resume") { $0.resume($1) } }

    func pause() -> Bool { send("pause") { $0.pause($1) } }

    func skipNext() -> Bool { send("skip to the next song") { $0.skip(toNext: $1) } }

    func skipPrevious() -> Bool { send("skip to the previous song") { $0.skip(toPrevious: $1) } }

    func seek(toSeconds seconds: Double) -> Bool {
        let milliseconds = Int(max(0, seconds) * 1000)
        return send("seek") { $0.seek(toPosition: milliseconds, callback: $1) }
    }

    private func send(_ what: String, _ command: (SPTAppRemotePlayerAPI, @escaping SPTAppRemoteCallback) -> Void) -> Bool {
        guard isConnected, let api = remote?.playerAPI else { return false }
        command(api) { [weak self] _, error in
            guard let problem = error?.localizedDescription else { return }
            Task { @MainActor in self?.onEvent?("Spotify would not \(what) directly: \(problem)") }
        }
        return true
    }

    // MARK: Connection

    private func connect() {
        guard let remote, accessToken != nil, !connecting, !remote.isConnected else { return }
        connecting = true
        remote.connect()
    }

    @objc private func appBecameActive() {
        // While waiting for Spotify's answer the token in hand is the old one; the answer brings a new one and connects with it.
        guard !waiting else { return }
        connect()
    }

    @objc private func appWillResignActive() {
        guard let remote, remote.isConnected else { return }
        remote.disconnect()
        isConnected = false
        connecting = false
        onPlayback?(nil)
    }

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.connecting = false
            self.expectingConnection = false
            self.onEvent?("Connected to the Spotify app")
            self.listenToPlayer(of: appRemote)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let problem = error?.localizedDescription ?? "no reason given"
        Task { @MainActor [weak self] in
            self?.isConnected = false
            self?.connecting = false
            self?.onPlayback?(nil)
            if self?.expectingConnection == true {
                self?.onEvent?("Could not connect to the Spotify app: \(problem)")
                self?.expectingConnection = false
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let problem = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.isConnected = false
            self?.connecting = false
            self?.onPlayback?(nil)
            if let problem { self?.onEvent?("The Spotify app disconnected: \(problem)") }
        }
    }

    // MARK: What the Spotify app is playing

    /// Asks to be told when the Spotify app's player changes, and reads it once now so the screen does not wait for a change.
    private func listenToPlayer(of appRemote: SPTAppRemote) {
        guard let api = appRemote.playerAPI else { return }
        api.delegate = self
        api.subscribe(toPlayerState: { [weak self] _, error in
            guard let problem = error?.localizedDescription else { return }
            Task { @MainActor in self?.onEvent?("Could not follow the Spotify app's player: \(problem)") }
        })
        api.getPlayerState { [weak self] result, error in
            guard error == nil, let state = result as? SPTAppRemotePlayerState else { return }
            let snapshot = Self.snapshot(of: state)
            Task { @MainActor in self?.report(snapshot) }
        }
    }

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let snapshot = Self.snapshot(of: playerState)
        Task { @MainActor [weak self] in self?.report(snapshot) }
    }

    private func report(_ snapshot: RemotePlayback) {
        onEvent?("Spotify app says: \(snapshot.isPaused ? "paused" : "playing") \(snapshot.title.isEmpty ? snapshot.uri : snapshot.title)")
        onPlayback?(snapshot)
    }

    /// Plain values out of the Spotify app's player state, taken at once because the state itself is not safe to pass around.
    nonisolated private static func snapshot(of state: SPTAppRemotePlayerState) -> RemotePlayback {
        let track = state.track
        return RemotePlayback(
            uri: track.uri,
            title: track.name,
            artist: track.artist.name,
            album: track.album.name,
            duration: TimeInterval(track.duration) / 1000,
            position: TimeInterval(state.playbackPosition) / 1000,
            isPaused: state.isPaused,
            isShuffling: state.playbackOptions.isShuffling,
            isAdvertisement: track.isAdvertisement
        )
    }
}
