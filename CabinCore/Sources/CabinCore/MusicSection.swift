import Foundation

/// The parts of the Music screen, in the order they appear along its top.
public enum MusicSection: String, CaseIterable, Hashable, Sendable {
    case nowPlaying
    case playlists
    case liked
    case search
    case queue

    public var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .playlists: return "Playlists"
        case .liked: return "Liked"
        case .search: return "Search"
        case .queue: return "Queue"
        }
    }

    /// An SF Symbol name.
    public var symbol: String {
        switch self {
        case .nowPlaying: return "play.circle.fill"
        case .playlists: return "music.note.list"
        case .liked: return "heart.fill"
        case .search: return "magnifyingglass"
        case .queue: return "list.bullet"
        }
    }
}
