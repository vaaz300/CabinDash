import Foundation
import Testing
@testable import CabinCore

@Suite struct PKCETests {
    /// The worked example in RFC 7636, appendix B.
    @Test func matchesTheRFCExample() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(forVerifier: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func base64URLHasNoPaddingOrUnsafeCharacters() {
        // 0xFB 0xFF 0xBF encodes to "+/+/" in plain base64.
        #expect(PKCE.base64URL(Data([0xFB, 0xFF, 0xBF])) == "-_-_")
        #expect(PKCE.base64URL(Data([0x01])) == "AQ")
        #expect(PKCE.base64URL(Data()) == "")
    }

    @Test func randomStringsAreLongEnoughAndDifferent() {
        let first = PKCE.randomString()
        let second = PKCE.randomString()
        #expect(first.count >= 43 && first.count <= 128)
        #expect(first != second)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(first.unicodeScalars.allSatisfy { allowed.contains($0) })
    }
}

@Suite struct FormEncodingTests {
    @Test func escapesEverythingButUnreservedCharacters() {
        #expect(FormEncoding.escape("a b&c=d") == "a%20b%26c%3Dd")
        #expect(FormEncoding.escape("cabindash://spotify-callback") == "cabindash%3A%2F%2Fspotify-callback")
        #expect(FormEncoding.escape("A-z_0.9~") == "A-z_0.9~")
    }

    @Test func joinsPairsWithAmpersands() {
        #expect(FormEncoding.encode([("a", "1"), ("b", "x y")]) == "a=1&b=x%20y")
        #expect(FormEncoding.encode([]) == "")
    }
}

@Suite struct SpotifyAuthTests {
    @Test func authorizeURLCarriesEverySpotifyNeeds() throws {
        let url = try #require(SpotifyAuth.authorizeURL(clientID: "client123", challenge: "chal", state: "st"))
        let text = url.absoluteString
        #expect(text.hasPrefix("https://accounts.spotify.com/authorize?"))
        #expect(text.contains("client_id=client123"))
        #expect(text.contains("response_type=code"))
        #expect(text.contains("redirect_uri=cabindash%3A%2F%2Fspotify-callback"))
        #expect(text.contains("code_challenge_method=S256"))
        #expect(text.contains("code_challenge=chal"))
        #expect(text.contains("state=st"))
        #expect(text.contains("scope=user-read-playback-state%20user-modify-playback-state%20user-read-currently-playing%20playlist-read-private%20playlist-read-collaborative%20user-library-read%20user-library-modify"))
    }

    @Test func codeBodyHasTheVerifierButNoSecret() {
        let body = String(decoding: SpotifyAuth.codeBody(clientID: "c", code: "the code", verifier: "ver"), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=the%20code"))
        #expect(body.contains("code_verifier=ver"))
        #expect(body.contains("client_id=c"))
        #expect(!body.contains("secret"))
    }

    @Test func refreshBody() {
        let body = String(decoding: SpotifyAuth.refreshBody(clientID: "c", refreshToken: "r"), as: UTF8.self)
        #expect(body == "grant_type=refresh_token&refresh_token=r&client_id=c")
    }

    @Test func callbackWithTheRightStateGivesTheCode() throws {
        let url = try #require(URL(string: "cabindash://spotify-callback?code=XYZ&state=st"))
        #expect(SpotifyAuth.parseCallback(url, expectedState: "st") == .code("XYZ"))
    }

    @Test func callbackWithAnotherStateIsRejected() throws {
        let url = try #require(URL(string: "cabindash://spotify-callback?code=XYZ&state=other"))
        #expect(SpotifyAuth.parseCallback(url, expectedState: "st") == .mismatch)
        let none = try #require(URL(string: "cabindash://spotify-callback?code=XYZ"))
        #expect(SpotifyAuth.parseCallback(none, expectedState: "st") == .mismatch)
    }

    @Test func cancelledSignInIsDenied() throws {
        let url = try #require(URL(string: "cabindash://spotify-callback?error=access_denied&state=st"))
        #expect(SpotifyAuth.parseCallback(url, expectedState: "st") == .denied)
    }

    @Test func callbackWithoutACodeIsInvalid() throws {
        let url = try #require(URL(string: "cabindash://spotify-callback?state=st"))
        #expect(SpotifyAuth.parseCallback(url, expectedState: "st") == .invalid)
    }
}

@Suite struct SpotifyTokenTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func readsAFirstSignInAnswer() throws {
        let json = #"{"access_token":"AT","token_type":"Bearer","expires_in":3600,"refresh_token":"RT","scope":"x"}"#
        let token = try #require(SpotifyToken.parse(Data(json.utf8), now: now, previousRefresh: nil))
        #expect(token.accessToken == "AT")
        #expect(token.refreshToken == "RT")
        #expect(token.expiresAt == now.addingTimeInterval(3600))
    }

    @Test func aRefreshAnswerKeepsTheOldRefreshToken() throws {
        let json = #"{"access_token":"AT2","expires_in":1800}"#
        let token = try #require(SpotifyToken.parse(Data(json.utf8), now: now, previousRefresh: "OLD"))
        #expect(token.accessToken == "AT2")
        #expect(token.refreshToken == "OLD")
        #expect(token.expiresAt == now.addingTimeInterval(1800))
    }

    @Test func withoutAnyRefreshTokenItFails() {
        let json = #"{"access_token":"AT","expires_in":3600}"#
        #expect(SpotifyToken.parse(Data(json.utf8), now: now, previousRefresh: nil) == nil)
    }

    @Test func badAnswersFail() {
        #expect(SpotifyToken.parse(Data(), now: now, previousRefresh: "R") == nil)
        #expect(SpotifyToken.parse(Data(#"{"error":"invalid_grant"}"#.utf8), now: now, previousRefresh: "R") == nil)
        #expect(SpotifyToken.parse(Data(#"{"access_token":"","refresh_token":"R"}"#.utf8), now: now, previousRefresh: nil) == nil)
    }

    @Test func expiryUsesAMargin() {
        let token = SpotifyToken(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(100))
        #expect(!token.isExpired(at: now))
        #expect(token.isExpired(at: now.addingTimeInterval(50)))
        #expect(token.isExpired(at: now.addingTimeInterval(200)))
        #expect(!token.isExpired(at: now.addingTimeInterval(50), margin: 10))
    }

    @Test func survivesBeingSavedAndLoaded() throws {
        let token = SpotifyToken(accessToken: "a", refreshToken: "r", expiresAt: now)
        let data = try JSONEncoder().encode(token)
        #expect(try JSONDecoder().decode(SpotifyToken.self, from: data) == token)
    }
}

@Suite struct SpotifyScopeTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let everyScope = SpotifyAuth.scopes.joined(separator: " ")

    @Test func requiredScopesCoverLibraryAndPlaylists() {
        #expect(SpotifyAuth.scopes == [
            "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
            "playlist-read-private", "playlist-read-collaborative", "user-library-read", "user-library-modify"
        ])
    }

    @Test func tokenAnswerCarriesItsScope() throws {
        let json = #"{"access_token":"AT","expires_in":3600,"refresh_token":"RT","scope":"a b"}"#
        let token = try #require(SpotifyToken.parse(Data(json.utf8), now: now, previousRefresh: nil))
        #expect(token.scope == "a b")
    }

    @Test func refreshWithoutScopeKeepsThePreviousScope() throws {
        let json = #"{"access_token":"AT2","expires_in":1800}"#
        let token = try #require(SpotifyToken.parse(Data(json.utf8), now: now, previousRefresh: "OLD", previousScope: "a b"))
        #expect(token.scope == "a b")
    }

    @Test func oldSavedTokenWithoutScopeNeedsReconnect() throws {
        let old = #"{"accessToken":"a","refreshToken":"r","expiresAt":0}"#
        let token = try JSONDecoder().decode(SpotifyToken.self, from: Data(old.utf8))
        #expect(token.scope == nil)
        #expect(!token.hasAllRequiredScopes)
        #expect(SpotifyAuth.missingScopes(granted: nil) == SpotifyAuth.scopes)
    }

    @Test func tokenWithEveryScopeIsFine() {
        let token = SpotifyToken(accessToken: "a", refreshToken: "r", expiresAt: now, scope: everyScope)
        #expect(token.hasAllRequiredScopes)
    }

    @Test func missingScopesNamesTheOnesLeftOut() {
        let granted = SpotifyAuth.scopes.filter { $0 != "user-library-modify" }.joined(separator: " ")
        #expect(SpotifyAuth.missingScopes(granted: granted) == ["user-library-modify"])
    }

    @Test func scopeComparisonIgnoresOrderAndExtraSpaces() {
        let jumbled = "  user-library-modify   user-library-read playlist-read-collaborative playlist-read-private "
            + "user-read-currently-playing user-modify-playback-state user-read-playback-state  "
        #expect(SpotifyAuth.missingScopes(granted: jumbled).isEmpty)
    }

    @Test func aScopeSurvivesBeingSavedAndLoaded() throws {
        let token = SpotifyToken(accessToken: "a", refreshToken: "r", expiresAt: now, scope: everyScope)
        let data = try JSONEncoder().encode(token)
        #expect(try JSONDecoder().decode(SpotifyToken.self, from: data).scope == everyScope)
    }
}
