import Foundation
import Observation

/// A short record of what Cabin Dash and Spotify said to each other while starting playback, shown in Settings so that a
/// problem on the phone can be understood from a screenshot. It holds no sign-in tokens, only the steps taken, device names
/// and song or playlist addresses. It is kept in memory and sent nowhere.
@MainActor @Observable
final class SpotifyLog {
    private(set) var lines: [String] = []

    private static let limit = 80
    @ObservationIgnored private var lastText = ""

    func add(_ text: String) {
        // The same event twice in a row (such as a refused connection on every return to the app) is worth one line.
        guard text != lastText else { return }
        lastText = text
        let stamp = Date().formatted(date: .omitted, time: .standard)
        lines.append("\(stamp)  \(text)")
        if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
    }

    func clear() {
        lines = []
        lastText = ""
    }

    /// The newest step first, which is the one that matters when looking at what just went wrong.
    var text: String {
        lines.reversed().joined(separator: "\n")
    }
}
