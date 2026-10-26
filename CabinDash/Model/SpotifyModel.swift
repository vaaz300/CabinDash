import AuthenticationServices
import CabinCore
import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "app.cabindash", category: "spotify")

/// Connects Cabin Dash to Spotify through its Web API: shows what the Spotify app is playing and sends play, pause, next and previous.
/// Spotify keeps playing in its own app. This only reads and steers it, so it needs the Spotify app to be the active player.
@MainActor @Observable
final class SpotifyModel {
    enum Phase: Equatable {
        /// No client ID was built into this copy of the app.
        case notConfigured
        case signedOut
        case signingIn
        case signedIn
    }

    private(set) var phase: Phase
    private(set) var nowPlaying: NowPlaying?
    /// When `nowPlaying` was read, so the progress bar can keep moving between reads.
    private(set) var observedAt = Date()
    private(set) var problem: SpotifyFailure?
    /// False until Spotify has answered once, so the screen does not say "nothing playing" while it is still asking.
    private(set) var hasAnswered = false

    let clientID: String

    @ObservationIgnored private var token: SpotifyToken?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let authenticator = SpotifyAuthenticator()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshInFlight: Task<SpotifyToken, Error>?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var fast = false
    /// After Spotify says "slow down", polling waits until this time.
    @ObservationIgnored private var pausedUntil = Date.distantPast

    private static let tokenAccount = "spotify-token"

    init() {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10

        var saved: SpotifyToken?
        if let data = KeychainStore.read(account: Self.tokenAccount),
           let decoded = try? JSONDecoder().decode(SpotifyToken.self, from: data) {
            saved = decoded
        }

        clientID = configured
        session = URLSession(configuration: configuration)
        token = saved
        phase = configured.isEmpty ? .notConfigured : (saved == nil ? .signedOut : .signedIn)
    }

    var statusText: String {
        switch phase {
        case .notConfigured: return "Not set up"
        case .signedOut: return "Not connected"
        case .signingIn: return "Connecting\u{2026}"
        case .signedIn: return "Connected"
        }
    }

    // MARK: Polling

    /// On while the app is on screen. Off in the background, so nothing runs while the phone is in a pocket.
    func setActive(_ value: Bool) {
        active = value
        updatePolling()
    }

    /// The Now Playing screen asks more often than the rest of the app.
    func setFast(_ value: Bool) {
        fast = value
    }

    private func updatePolling() {
        guard active, phase == .signedIn else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Date() >= self.pausedUntil { await self.refresh() }
                let seconds: Double = self.fast ? 2 : 6
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    /// Where the track is now: the last known position plus the time since it was read, while it is playing.
    func position(at date: Date) -> Double {
        guard let current = nowPlaying else { return 0 }
        let elapsed = current.isPlaying ? date.timeIntervalSince(observedAt) : 0
        return min(current.duration, max(0, current.progress + elapsed))
    }

    func refresh() async {
        guard phase == .signedIn else { return }
        do {
            let reply = try await send("GET", "/v1/me/player", query: [("additional_types", "track,episode")])
            if reply.status == 204 {
                nowPlaying = nil
                problem = nil
            } else if (200..<300).contains(reply.status) {
                nowPlaying = SpotifyPlayback.parse(reply.data)
                observedAt = Date()
                problem = nil
            } else {
                throw SpotifyFailure.classify(status: reply.status, body: reply.data, retryAfter: reply.retryAfter)
            }
            hasAnswered = true
        } catch {
            handle(error)
        }
    }

    // MARK: Controls

    func togglePlayPause() async {
        let playing = nowPlaying?.isPlaying ?? false
        if nowPlaying != nil {
            nowPlaying?.isPlaying = !playing
            observedAt = Date()
        }
        await command(playing ? "/v1/me/player/pause" : "/v1/me/player/play", method: "PUT")
    }

    func skipNext() async {
        await command("/v1/me/player/next", method: "POST")
    }

    func skipPrevious() async {
        await command("/v1/me/player/previous", method: "POST")
    }

    func seek(toSeconds seconds: Double) async {
        let milliseconds = Int(max(0, seconds) * 1000)
        await command("/v1/me/player/seek", method: "PUT", query: [("position_ms", String(milliseconds))])
    }

    private func command(_ path: String, method: String, query: [(String, String)] = []) async {
        guard phase == .signedIn else { return }
        do {
            let reply = try await send(method, path, query: query)
            if (200..<300).contains(reply.status) {
                problem = nil
            } else {
                note(SpotifyFailure.classify(status: reply.status, body: reply.data, retryAfter: reply.retryAfter))
            }
        } catch {
            handle(error)
        }
        // Spotify applies a command a moment after it answers, so look again shortly.
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
    }

    // MARK: Signing in

    func signIn() async {
        guard phase == .signedOut else { return }
        problem = nil
        phase = .signingIn

        let verifier = PKCE.randomString()
        let state = PKCE.randomString(byteCount: 16)
        guard let url = SpotifyAuth.authorizeURL(
            clientID: clientID, challenge: PKCE.challenge(forVerifier: verifier), state: state
        ) else {
            phase = .signedOut
            problem = .http(0)
            return
        }

        do {
            let callback = try await authenticator.authenticate(url: url, callbackScheme: SpotifyAuth.redirectScheme)
            switch SpotifyAuth.parseCallback(callback, expectedState: state) {
            case .code(let code):
                try await exchange(code: code, verifier: verifier)
                phase = .signedIn
                updatePolling()
                await refresh()
            case .denied, .mismatch, .invalid:
                phase = .signedOut
            }
        } catch {
            phase = .signedOut
            if let sessionError = error as? ASWebAuthenticationSessionError, sessionError.code == .canceledLogin {
                return // the person closed the sheet
            }
            log.info("Spotify sign-in failed: \(error.localizedDescription, privacy: .public)")
            problem = (error as? SpotifyFailure) ?? .offline
        }
    }

    func signOut() {
        signOutLocally()
    }

    private func signOutLocally() {
        token = nil
        KeychainStore.delete(account: Self.tokenAccount)
        nowPlaying = nil
        hasAnswered = false
        phase = clientID.isEmpty ? .notConfigured : .signedOut
        updatePolling()
    }

    // MARK: Network

    private struct Reply {
        let data: Data
        let status: Int
        let retryAfter: String?
    }

    private func send(_ method: String, _ path: String, query: [(String, String)] = []) async throws -> Reply {
        var retried = false
        while true {
            let accessToken = try await validAccessToken()
            var text = "https://api.spotify.com" + path
            if !query.isEmpty { text += "?" + FormEncoding.encode(query) }
            guard let url = URL(string: text) else { throw SpotifyFailure.http(0) }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
            // Spotify answers "411 Length Required" to a PUT or POST with no body, so send an empty one.
            if method != "GET" { request.httpBody = Data() }

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpotifyFailure.http(0) }
            if http.statusCode == 401, !retried {
                retried = true
                _ = try await refreshTokens()
                continue
            }
            return Reply(data: data, status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
    }

    private func validAccessToken() async throws -> String {
        guard let current = token else { throw SpotifyFailure.notSignedIn }
        if current.isExpired(at: Date()) {
            return try await refreshTokens().accessToken
        }
        return current.accessToken
    }

    /// One refresh at a time: a second caller waits for the first instead of starting its own.
    private func refreshTokens() async throws -> SpotifyToken {
        if let running = refreshInFlight {
            return try await running.value
        }
        let task = Task { try await self.performRefresh() }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> SpotifyToken {
        guard let current = token, let url = SpotifyAuth.tokenURL else { throw SpotifyFailure.notSignedIn }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpotifyAuth.refreshBody(clientID: clientID, refreshToken: current.refreshToken)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let fresh = SpotifyToken.parse(data, now: Date(), previousRefresh: current.refreshToken) else {
            throw SpotifyFailure.notSignedIn
        }
        store(fresh)
        return fresh
    }

    private func exchange(code: String, verifier: String) async throws {
        guard let url = SpotifyAuth.tokenURL else { throw SpotifyFailure.http(0) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpotifyAuth.codeBody(clientID: clientID, code: code, verifier: verifier)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyFailure.http(0) }
        guard (200..<300).contains(http.statusCode),
              let fresh = SpotifyToken.parse(data, now: Date(), previousRefresh: nil) else {
            throw SpotifyFailure.http(http.statusCode)
        }
        store(fresh)
    }

    private func store(_ fresh: SpotifyToken) {
        token = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            KeychainStore.write(data, account: Self.tokenAccount)
        }
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        note((error as? SpotifyFailure) ?? .offline)
    }

    /// Remembers what went wrong, so the screen can say so, and backs off when Spotify asks for it.
    private func note(_ failure: SpotifyFailure) {
        hasAnswered = true
        problem = failure
        if case .rateLimited(let seconds) = failure {
            pausedUntil = Date().addingTimeInterval(Double(max(1, seconds)))
        }
        if failure == .notSignedIn {
            signOutLocally()
        }
    }
}
