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
/// What plays, the queue, the library and the device list all still go through the Web API. The one thing the connection is
/// used for besides staying awake is a second try at starting a song if the first one did not take.
@MainActor
final class SpotifyWake: NSObject, SPTAppRemoteDelegate {
    enum Outcome: Equatable {
        /// Spotify opened Cabin Dash again and said it went well.
        case returned
        /// Spotify opened Cabin Dash again with a complaint, in Spotify's words.
        case refused(String)
    }

    /// Told each step in plain words, for the Spotify log in Settings. Never given a token.
    var onEvent: ((String) -> Void)?

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

    /// Asks the Spotify app, through the connection, to play an address. False if there is no connection to ask through.
    /// Spotify answers later and the answer goes to the log.
    func play(_ uri: String) -> Bool {
        guard isConnected, !uri.isEmpty, let api = remote?.playerAPI else { return false }
        onEvent?("Asking Spotify directly to play \(uri)")
        api.play(uri) { [weak self] _, error in
            let problem = error?.localizedDescription
            Task { @MainActor in
                self?.onEvent?(problem.map { "Spotify would not play it directly: \($0)" } ?? "Spotify accepted the direct request")
            }
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
    }

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor [weak self] in
            self?.isConnected = true
            self?.connecting = false
            self?.expectingConnection = false
            self?.onEvent?("Connected to the Spotify app")
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let problem = error?.localizedDescription ?? "no reason given"
        Task { @MainActor [weak self] in
            self?.isConnected = false
            self?.connecting = false
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
            if let problem { self?.onEvent?("The Spotify app disconnected: \(problem)") }
        }
    }
}
