import CryptoKit
import Foundation

/// Percent-encoding for query strings and form bodies. Everything except the RFC 3986 "unreserved" characters is escaped,
/// so a redirect address such as `cabindash://spotify-callback` survives intact.
public enum FormEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    public static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }
}

/// The two helpers "Proof Key for Code Exchange" needs (RFC 7636). It lets an app sign in to Spotify with no client secret.
public enum PKCE {
    /// Base64 with `-` and `_` instead of `+` and `/`, and no `=` padding.
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// SHA-256 of the verifier, base64url encoded.
    public static func challenge(forVerifier verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// A random URL-safe string. 64 bytes gives an 86-character verifier (RFC 7636 allows 43 to 128).
    public static func randomString(byteCount: Int = 64) -> String {
        var generator = SystemRandomNumberGenerator()
        var bytes: [UInt8] = []
        for _ in 0..<max(1, byteCount) {
            bytes.append(UInt8.random(in: UInt8.min...UInt8.max, using: &generator))
        }
        return base64URL(Data(bytes))
    }
}

/// What came back when the sign-in page handed control back to the app.
public enum SpotifyCallback: Equatable, Sendable {
    case code(String)
    /// The person tapped Cancel, or Spotify reported an error.
    case denied
    /// The `state` value did not match: not an answer to the request this app made.
    case mismatch
    case invalid
}

public struct SpotifyToken: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True when the token is expired, or will be within `margin` seconds.
    public func isExpired(at now: Date, margin: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(margin) >= expiresAt
    }

    /// Reads Spotify's token answer. A refresh answer often has no new refresh token; then the old one stays valid.
    public static func parse(_ data: Data, now: Date, previousRefresh: String?) -> SpotifyToken? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let access = root["access_token"] as? String, !access.isEmpty else { return nil }
        let refresh = (root["refresh_token"] as? String) ?? previousRefresh
        guard let refresh, !refresh.isEmpty else { return nil }
        let seconds = (root["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return SpotifyToken(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(seconds))
    }
}

/// Everything about talking to Spotify's sign-in that does not need the network.
public enum SpotifyAuth {
    /// The address Spotify sends the person back to. It must be listed, exactly like this, in the Spotify developer dashboard.
    public static let redirectScheme = "cabindash"
    public static let redirectURI = "cabindash://spotify-callback"

    /// Read what is playing, and control it. Nothing else is asked for.
    public static let scopes = ["user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing"]

    public static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")

    public static func authorizeURL(clientID: String, challenge: String, state: String) -> URL? {
        let query = FormEncoding.encode([
            ("client_id", clientID),
            ("response_type", "code"),
            ("redirect_uri", redirectURI),
            ("code_challenge_method", "S256"),
            ("code_challenge", challenge),
            ("state", state),
            ("scope", scopes.joined(separator: " "))
        ])
        return URL(string: "https://accounts.spotify.com/authorize?" + query)
    }

    public static func codeBody(clientID: String, code: String, verifier: String) -> Data {
        Data(FormEncoding.encode([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", verifier)
        ]).utf8)
    }

    public static func refreshBody(clientID: String, refreshToken: String) -> Data {
        Data(FormEncoding.encode([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID)
        ]).utf8)
    }

    /// Reads the address Spotify sent the person back to.
    public static func parseCallback(_ url: URL, expectedState: String) -> SpotifyCallback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .invalid }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        if value("error") != nil { return .denied }
        guard let state = value("state"), state == expectedState else { return .mismatch }
        guard let code = value("code"), !code.isEmpty else { return .invalid }
        return .code(code)
    }
}
