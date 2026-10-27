import Foundation

/// Keeps the one complaint the Music screen shows, and decides when it may go away.
///
/// What is playing is read every few seconds. If any good read cleared the complaint, a failed tap on a song would show
/// "no device ready" for under a second: with no device Spotify answers every read with "nothing is playing", which is
/// a good read. So a complaint about something the person asked for stays until something shows it is out of date:
/// a command that works, or a song actually playing. Connection trouble is different. It clears as soon as Spotify answers.
public struct SpotifyProblemBoard: Equatable, Sendable {
    public private(set) var current: SpotifyFailure?
    /// True while `current` is about a command and an idle read ("nothing is playing") does not disprove it.
    private var holdsThroughIdleReads = false

    public init() {}

    /// A command the person sent (play, skip, add to queue, switch device) was refused.
    public mutating func commandFailed(_ failure: SpotifyFailure) {
        current = failure
        holdsThroughIdleReads = Self.holds(failure)
    }

    public mutating func commandSucceeded() {
        clear()
    }

    /// The regular read of what is playing, or a list, could not be done.
    public mutating func readFailed(_ failure: SpotifyFailure) {
        current = failure
        holdsThroughIdleReads = false
    }

    /// Spotify answered the regular read. `playing` is true when it described something playing.
    public mutating func readAnswered(playing: Bool) {
        if holdsThroughIdleReads && !playing { return }
        clear()
    }

    public mutating func clear() {
        current = nil
        holdsThroughIdleReads = false
    }

    /// Refusals are about the account or the setup, so a read cannot prove them wrong. Connection trouble can be proved wrong.
    private static func holds(_ failure: SpotifyFailure) -> Bool {
        switch failure {
        case .noActiveDevice, .premiumRequired, .notAllowed, .http:
            return true
        case .offline, .rateLimited, .notSignedIn:
            return false
        }
    }
}
