import Foundation

/// The colour family of a tile that has no App Store artwork. The app turns each into a real colour.
public enum HomeTone: String, Hashable, Sendable {
    case green
    case blue
    case red
    case orange
    case purple
    case graphite
}

/// One tile on the Other apps screen.
public struct HomeItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A system link such as the Phone or Messages.
        case url(URL)
        case addApps
        /// Another app, opened through its own link.
        case app(AppEntry)
    }

    public let id: String
    public let title: String
    public let kind: Kind
    /// An SF Symbol name, used when there is no artwork.
    public let symbol: String
    public let tone: HomeTone
    /// A catalog app whose App Store artwork this tile shows instead of the symbol.
    public let artwork: AppEntry?

    public init(id: String, title: String, kind: Kind, symbol: String, tone: HomeTone = .graphite, artwork: AppEntry? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.symbol = symbol
        self.tone = tone
        self.artwork = artwork
    }

    public var app: AppEntry? {
        if case .app(let app) = kind { return app }
        return nil
    }
}

/// Decides which tiles the Other apps screen shows and in which order. That screen is optional and off by default:
/// Cabin Dash's own features live in the dock, not here.
/// Pure logic, so it can be tested without a phone.
public enum HomeLayout {
    /// Tiles per page: four across, two down, as on CarPlay.
    public static let perPage = 8

    /// Shelf apps that Cabin Dash replaces with a feature of its own, so they get no tile.
    public static let replacedByFeatures: Set<String> = ["apple-maps"]

    private static func link(_ id: String, _ title: String, _ text: String, _ symbol: String, _ tone: HomeTone) -> HomeItem? {
        guard let url = URL(string: text) else { return nil }
        return HomeItem(id: id, title: title, kind: .url(url), symbol: symbol, tone: tone)
    }

    public static let addApps = HomeItem(id: "add-apps", title: "Add Apps", kind: .addApps, symbol: "plus", tone: .blue)

    /// Phone and Messages hand off to the system apps until Cabin Dash has screens of its own for them.
    public static let systemLinks: [HomeItem] = [
        link("phone", "Phone", "tel://", "phone.fill", .green),
        link("messages", "Messages", "sms://", "message.fill", .green)
    ].compactMap { $0 }

    public static func tile(for app: AppEntry) -> HomeItem {
        HomeItem(id: app.id, title: app.name, kind: .app(app), symbol: app.category.symbol, tone: .graphite, artwork: app)
    }

    /// Every tile, in order: the system links, the shelf apps in shelf order, then Add Apps.
    public static func items(shelf: [AppEntry]) -> [HomeItem] {
        var result = systemLinks
        var used = Set(systemLinks.map(\.id))
        used.insert(addApps.id)
        for app in shelf where !replacedByFeatures.contains(app.id) {
            if used.insert(app.id).inserted {
                result.append(tile(for: app))
            }
        }
        result.append(addApps)
        return result
    }

    /// Splits tiles into pages of `perPage`. An empty list gives no pages.
    public static func pages(_ items: [HomeItem], perPage: Int = HomeLayout.perPage) -> [[HomeItem]] {
        guard perPage > 0, !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: perPage).map { start in
            Array(items[start ..< min(start + perPage, items.count)])
        }
    }
}
