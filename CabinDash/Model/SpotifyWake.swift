import CabinCore
import Foundation
import SpotifyiOS

/// Starts the Spotify app on this iPhone and brings the person straight back, using Spotify's iOS SDK.
///
/// Spotify lists this iPhone as a place to play only while its own app is running, and the Web API cannot start it.
/// The SDK's `authorizeAndPlayURI` can: it opens Spotify, Spotify plays (a blank address means the last song), and Spotify
/// then opens Cabin Dash again by itself, so nobody has to switch apps by hand.
///
/// That is the only thing the SDK is used for. What plays, the queue, the library and the device list all still go
/// through the Web API, and the SDK's own connection ("App Remote") is never opened.
@MainActor
final class SpotifyWake {
    enum Outcome: Equatable {
        /// Spotify opened Cabin Dash again and said it went well.
        case returned
        /// Spotify opened Cabin Dash again with a complaint, in Spotify's words.
        case refused(String)
    }

    /// Kept alive until Spotify answers, since the SDK object is what understands the answer.
    private var remote: SPTAppRemote?
    private var waiting = false

    /// Opens Spotify and asks it to play. `onNotInstalled` runs if there is no Spotify app on this iPhone to open.
    func start(clientID: String, onNotInstalled: @escaping () -> Void) {
        guard let redirect = URL(string: SpotifyAuth.redirectURI) else { return }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirect)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .error)
        self.remote = remote
        waiting = true
        remote.authorizeAndPlayURI("", asRadio: false, additionalScopes: nil) { [weak self] installed in
            guard !installed else { return }
            Task { @MainActor in
                self?.waiting = false
                onNotInstalled()
            }
        }
    }

    /// Reads the address Spotify opens Cabin Dash with. Nil when it is not the answer to `start`, such as any other link.
    func finish(with url: URL) -> Outcome? {
        guard waiting, let remote, let answer = remote.authorizationParameters(from: url) else { return nil }
        waiting = false
        if let text = answer[SPTAppRemoteErrorDescriptionKey] ?? answer[SPTAppRemoteErrorKey], !text.isEmpty {
            return .refused(text)
        }
        return .returned
    }
}
