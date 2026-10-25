import Foundation

/// The groups apps are shelved under. These follow the app types CarPlay supports.
public enum AppCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case navigation
    case audio
    case talk
    case messages
    case charging
    case more

    public var title: String {
        switch self {
        case .navigation: return "Navigation"
        case .audio: return "Music and radio"
        case .talk: return "Podcasts and books"
        case .messages: return "Messages and calls"
        case .charging: return "Charging, fuel and parking"
        case .more: return "Assistants and more"
        }
    }

    /// An SF Symbol name. Used for section headings and for the tile an app shows until its icon loads.
    public var symbol: String {
        switch self {
        case .navigation: return "location.fill"
        case .audio: return "music.note"
        case .talk: return "headphones"
        case .messages: return "message.fill"
        case .charging: return "bolt.fill"
        case .more: return "square.grid.2x2.fill"
        }
    }

    /// Unknown values from a newer or older save fall back to `.more` instead of failing the whole decode.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppCategory(rawValue: raw) ?? .more
    }
}
