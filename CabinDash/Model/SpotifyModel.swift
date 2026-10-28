import AuthenticationServices
import CabinCore
import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "app.cabindash", category: "spotify")

/// What Spotify answered to one request.
struct SpotifyReply {
    let data: Data
    let status: Int
    let retryAfter: String?

    var isSuccess: Bool { (200..<300).contains(status) }

    /// Why it did not work, in words a driver can act on. Only meaningful when `isSuccess` is false.
    var failure: SpotifyFailure {
        SpotifyFailure.classify(status: status, body: data, retryAfter: retryAfter)
    }
}

/// Connects Cabin Dash to Spotify through its Web API: shows what the Spotify app is playing and sends play, pause, next and previous.
/// Spotify keeps playing in its own app. This only reads and steers it, so it needs the Spotify app to be the active player.
@MainActor @Observable
final class SpotifyModel {
    enum Phase: Equatable {
        /// No client ID was built into this copy of the app.
        case notConfigured
        case signedOut
        /// Signed in with an older, smaller set of permissions. Playlists and likes need one more sign-in.
        case needsReconnect
        case signingIn
        case signedIn
    }

    private(set) var phase: Phase
    private(set) var nowPlaying: NowPlaying?
    /// When `nowPlaying` was read, so the progress bar can keep moving between reads.
    private(set) var observedAt = Date()
    /// What the Music screen complains about. Set only through `board`, which decides when a complaint may go away.
    private(set) var problem: SpotifyFailure?
    /// False until Spotify has answered once, so the screen does not say "nothing playing" while it is still asking.
    private(set) var hasAnswered = false
    /// The device the person picked in the list, for this session only. Spotify does not count a device as active until it
    /// has something to play, so after picking a phone with nothing playing the next play command is sent to this one.
    private(set) var chosenDeviceID: String?
    private(set) var chosenDeviceName: String?

    let clientID: String

    @ObservationIgnored private var board = SpotifyProblemBoard()
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
        if configured.isEmpty {
            phase = .notConfigured
        } else if let saved {
            phase = saved.hasAllRequiredScopes ? .signedIn : .needsReconnect
        } else {
            phase = .signedOut
        }
    }

    var statusText: String {
        switch phase {
        case .notConfigured: return "Not set up"
        case .signedOut: return "Not connected"
        case .needsReconnect: return "Needs new permissions"
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
            let reply = try await perform(SpotifyEndpoint.player())
            if reply.status == 204 {
                nowPlaying = nil
                board.readAnswered(playing: false)
                publishProblem()
            } else if reply.isSuccess {
                nowPlaying = SpotifyPlayback.parse(reply.data)
                observedAt = Date()
                board.readAnswered(playing: nowPlaying != nil)
                publishProblem()
            } else {
                throw reply.failure
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
        await command(playing ? SpotifyEndpoint.pause() : SpotifyEndpoint.resume())
    }

    func skipNext() async {
        await command(SpotifyEndpoint.next())
    }

    func skipPrevious() async {
        await command(SpotifyEndpoint.previous())
    }

    func seek(toSeconds seconds: Double) async {
        await command(SpotifyEndpoint.seek(milliseconds: Int(max(0, seconds) * 1000)))
    }

    /// Flips shuffle on the screen at once, then tells Spotify. If Spotify refuses, the next read puts it back.
    func toggleShuffle() async {
        guard let current = nowPlaying else { return }
        let target = !current.shuffle
        nowPlaying?.shuffle = target
        await command(SpotifyEndpoint.shuffle(target))
    }

    /// Off, then repeat all, then repeat one, then off again.
    func cycleRepeat() async {
        guard let current = nowPlaying else { return }
        let target = current.repeatMode.next
        nowPlaying?.repeatMode = target
        await command(SpotifyEndpoint.setRepeat(target))
    }

    /// Turns shuffle on or off whether or not anything is playing yet. True when Spotify accepted it.
    @discardableResult
    func setShuffle(_ on: Bool) async -> Bool {
        await command(SpotifyEndpoint.shuffle(on))
    }

    /// Starts playing an album, a playlist or a list of songs. True when Spotify accepted it.
    ///
    /// This is the plain version, used when the device list could not be read: it plays on whichever device Spotify says is
    /// active. When none is, it tries the device the person picked in the list, if they have picked one. Normally a tap on
    /// Play goes through `SpotifyLibraryModel.play`, which picks this iPhone (or the person's pick) first.
    @discardableResult
    func play(_ target: SpotifyPlayTarget) async -> Bool {
        guard phase == .signedIn else { return false }
        var failure = await attempt(SpotifyEndpoint.play(target))
        if let first = failure, let deviceID = SpotifyDevices.retryDeviceID(after: first, chosenID: chosenDeviceID) {
            failure = await attempt(SpotifyEndpoint.play(target, deviceID: deviceID))
            if failure != nil {
                // The picked device is gone or will not take it. Say what the person first saw, and stop trying it.
                forgetChosenDevice()
                failure = first
            }
        }
        if let failure {
            note(failure, fromCommand: true)
        } else {
            board.commandSucceeded()
            publishProblem()
        }
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
        return failure == nil
    }

    /// Starts playing on a named device, which Spotify accepts even for a device it does not yet count as active.
    /// Nil when Spotify accepted it, otherwise why not. A failure is not shown here: the caller may have another way to
    /// make it work (starting the Spotify app on the phone), so it calls `showPlayFailure` only when it has run out of them.
    func play(_ target: SpotifyPlayTarget, on device: SpotifyDevice) async -> SpotifyFailure? {
        guard phase == .signedIn else { return .notSignedIn }
        let failure = await attempt(SpotifyEndpoint.play(target, deviceID: device.id))
        if failure == nil {
            board.commandSucceeded()
            publishProblem()
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
        return failure
    }

    /// Shows why a play command did not work.
    func showPlayFailure(_ failure: SpotifyFailure) {
        note(failure, fromCommand: true)
    }

    /// Moves playback to a device the person picked and keeps playing there. True when Spotify accepted it.
    /// The pick is remembered even if Spotify declines the move, so the next play command still goes to that device.
    @discardableResult
    func transfer(to device: SpotifyDevice) async -> Bool {
        chosenDeviceID = device.id
        chosenDeviceName = device.name
        return await command(SpotifyEndpoint.transfer(to: device.id, play: true))
    }

    /// Goes back to the default, which is this iPhone.
    func forgetChosenDevice() {
        chosenDeviceID = nil
        chosenDeviceName = nil
    }

    /// Adds a song or episode to the end of the queue. True when Spotify accepted it.
    @discardableResult
    func addToQueue(uri: String) async -> Bool {
        await command(SpotifyEndpoint.addToQueue(uri: uri))
    }

    /// Nil when Spotify accepted the request, otherwise why it did not. Remembers nothing: the caller decides what to show.
    private func attempt(_ request: SpotifyRequest) async -> SpotifyFailure? {
        do {
            let reply = try await perform(request)
            return reply.isSuccess ? nil : reply.failure
        } catch {
            return (error as? SpotifyFailure) ?? .offline
        }
    }

    /// Sends one command, then looks at the player again. True when Spotify accepted the command.
    @discardableResult
    private func command(_ request: SpotifyRequest) async -> Bool {
        guard phase == .signedIn else { return false }
        var accepted = false
        do {
            let reply = try await perform(request)
            if reply.isSuccess {
                board.commandSucceeded()
                publishProblem()
                accepted = true
            } else {
                note(reply.failure, fromCommand: true)
            }
        } catch {
            handle(error)
        }
        // Spotify applies a command a moment after it answers, so look again shortly.
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
        return accepted
    }

    // MARK: Signing in

    func signIn() async {
        guard phase == .signedOut || phase == .needsReconnect else { return }
        let before = phase
        board.clear()
        publishProblem()
        phase = .signingIn

        let verifier = PKCE.randomString()
        let state = PKCE.randomString(byteCount: 16)
        guard let url = SpotifyAuth.authorizeURL(
            clientID: clientID, challenge: PKCE.challenge(forVerifier: verifier), state: state
        ) else {
            phase = before
            board.readFailed(.http(0))
            publishProblem()
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
                phase = before
            }
        } catch {
            phase = before
            if let sessionError = error as? ASWebAuthenticationSessionError, sessionError.code == .canceledLogin {
                return // the person closed the sheet
            }
            log.info("Spotify sign-in failed: \(error.localizedDescription, privacy: .public)")
            board.readFailed((error as? SpotifyFailure) ?? .offline)
            publishProblem()
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
        forgetChosenDevice()
        phase = clientID.isEmpty ? .notConfigured : .signedOut
        updatePolling()
    }

    // MARK: Network

    /// Sends one request signed in as the person. A 401 refreshes the token once and tries again.
    /// Throws when there is no answer at all (offline, not signed in); an answer with an error status is returned, not thrown.
    func perform(_ request: SpotifyRequest) async throws -> SpotifyReply {
        var retried = false
        while true {
            let accessToken = try await validAccessToken()
            guard let url = request.url() else { throw SpotifyFailure.http(0) }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = request.method
            urlRequest.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
            if let body = request.body {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = body
            } else if request.method != "GET" {
                // Spotify answers "411 Length Required" to a PUT, POST or DELETE with no body, so send an empty one.
                urlRequest.httpBody = Data()
            }

            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw SpotifyFailure.http(0) }
            if http.statusCode == 401, !retried {
                retried = true
                _ = try await refreshTokens()
                continue
            }
            return SpotifyReply(data: data, status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
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
              let fresh = SpotifyToken.parse(data, now: Date(), previousRefresh: current.refreshToken, previousScope: current.scope) else {
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
              var fresh = SpotifyToken.parse(data, now: Date(), previousRefresh: nil) else {
            throw SpotifyFailure.http(http.statusCode)
        }
        // Spotify names the granted permissions in its answer. If it ever left them out, this sign-in asked for all of them,
        // so assume they were given rather than asking the person to sign in again in a loop.
        if fresh.scope == nil { fresh.scope = SpotifyAuth.scopes.joined(separator: " ") }
        store(fresh)
    }

    private func store(_ fresh: SpotifyToken) {
        token = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            KeychainStore.write(data, account: Self.tokenAccount)
        }
    }

    /// For screens that call Spotify through `perform`: remembers a failure the same way the player does.
    func report(_ error: Error) {
        handle(error)
    }

    /// Copies the board's complaint to `problem`, which the screens watch, only when it has changed.
    private func publishProblem() {
        if problem != board.current { problem = board.current }
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        note((error as? SpotifyFailure) ?? .offline)
    }

    /// Remembers what went wrong, so the screen can say so, and backs off when Spotify asks for it.
    /// `fromCommand` is true for a refusal of something the person asked for, which stays on screen until something shows it is out of date.
    private func note(_ failure: SpotifyFailure, fromCommand: Bool = false) {
        hasAnswered = true
        if fromCommand {
            board.commandFailed(failure)
        } else {
            board.readFailed(failure)
        }
        publishProblem()
        if case .rateLimited(let seconds) = failure {
            pausedUntil = Date().addingTimeInterval(Double(max(1, seconds)))
        }
        if failure == .notSignedIn {
            signOutLocally()
        }
    }
}
