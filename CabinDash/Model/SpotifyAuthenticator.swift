import AuthenticationServices
import UIKit

/// Opens Spotify's sign-in page in the system's secure web sheet and waits for it to hand control back.
/// No password ever passes through Cabin Dash: the person signs in on Spotify's own page.
final class SpotifyAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Shows the page at `url` and returns the address it finishes on (which starts with `callbackScheme`).
    /// Throws if the person cancels.
    @MainActor
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cancelled))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: URLError(.cannotOpenFile))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap { $0.windows }
            if let key = windows.first(where: { $0.isKeyWindow }) { return key }
            return windows.first ?? ASPresentationAnchor()
        }
    }
}
