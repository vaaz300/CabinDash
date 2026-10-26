import Foundation

/// The screens Cabin Dash draws itself. Every other tile on the home grid opens another app.
public enum AppScreen: String, Codable, CaseIterable, Hashable, Sendable {
    case maps
    case nowPlaying = "now-playing"
    case drive

    public var title: String {
        switch self {
        case .maps: return "Maps"
        case .nowPlaying: return "Now Playing"
        case .drive: return "Drive"
        }
    }
}

/// The colour family of a tile that has no App Store artwork. The app turns each into a real colour.
public enum HomeTone: String, Hashable, Sendable {
    case green
    case blue
    case red
    case orange
    case purple
    case graphite
}

/// One tile on the home grid, or one icon in the rail beside it.
public struct HomeItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A screen Cabin Dash draws itself.
        case screen(AppScreen)
        /// A system link such as the Phone or Messages.
        case url(URL)
        case settings
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

    /// Whether the item may sit in the rail. Settings and Add Apps never do.
    public var isDockable: Bool {
        switch kind {
        case .settings, .addApps: return false
        case .screen, .url, .app: return true
        }
    }

    public var screen: AppScreen? {
        if case .screen(let screen) = kind { return screen }
        return nil
    }

    public var app: AppEntry? {
        if case .app(let app) = kind { return app }
        return nil
    }
}

/// Decides which tiles the home grid shows, in which order, and which of them sit in the rail.
/// Pure logic, so it can be tested without a phone.
public enum HomeLayout {
    /// Tiles per page: four across, two down, as on CarPlay.
    public static let perPage = 8

    /// The first tiles, in order. A built-in tile is always there; an app tile appears only when that app is on the shelf.
    /// Whatever is missing is filled by the next apps on the shelf, so the first page stays full.
    public static let pinned = ["phone", "spotify", "maps", "messages", "now-playing", "google-maps", "drive", "settings"]

    /// What the rail shows before the user has opened anything.
    public static let dockDefaults = ["maps", "now-playing", "drive"]

    /// Shelf apps that Cabin Dash replaces with a screen of its own, so they get no second tile.
    public static let replacedByScreens: Set<String> = ["apple-maps"]

    private static func link(_ id: String, _ title: String, _ text: String, _ symbol: String, _ tone: HomeTone) -> HomeItem? {
        guard let url = URL(string: text) else { return nil }
        return HomeItem(id: id, title: title, kind: .url(url), symbol: symbol, tone: tone)
    }

    public static let addApps = HomeItem(id: "add-apps", title: "Add Apps", kind: .addApps, symbol: "plus", tone: .blue)

    /// Tiles Cabin Dash always has, by id.
    public static let builtIn: [String: HomeItem] = {
        var items: [HomeItem] = [
            HomeItem(id: "maps", title: "Maps", kind: .screen(.maps), symbol: "map.fill", tone: .green,
                     artwork: Catalog.entry(id: "apple-maps")),
            HomeItem(id: "now-playing", title: "Now Playing", kind: .screen(.nowPlaying), symbol: "waveform", tone: .red),
            HomeItem(id: "drive", title: "Drive", kind: .screen(.drive), symbol: "speedometer", tone: .orange),
            HomeItem(id: "settings", title: "Settings", kind: .settings, symbol: "gearshape.fill", tone: .graphite)
        ]
        let links: [HomeItem?] = [
            link("phone", "Phone", "tel://", "phone.fill", .green),
            link("messages", "Messages", "sms://", "message.fill", .green)
        ]
        items.append(contentsOf: links.compactMap { $0 })
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }()

    public static func tile(for app: AppEntry) -> HomeItem {
        HomeItem(id: app.id, title: app.name, kind: .app(app), symbol: app.category.symbol, tone: .graphite, artwork: app)
    }

    /// Every tile, in order. Add Apps is always last.
    public static func items(shelf: [AppEntry]) -> [HomeItem] {
        let usable = shelf.filter { !replacedByScreens.contains($0.id) }
        let byID = Dictionary(usable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [HomeItem] = []
        var used = Set<String>()

        for id in pinned {
            if let builtInItem = builtIn[id] {
                result.append(builtInItem)
                used.insert(id)
            } else if let app = byID[id] {
                result.append(tile(for: app))
                used.insert(id)
            }
        }
        for app in usable {
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

    /// The rail: what was opened most recently, then the defaults, up to `limit`, with no repeats.
    public static func dock(items: [HomeItem], recent: [String], limit: Int = 3) -> [HomeItem] {
        guard limit > 0 else { return [] }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [HomeItem] = []
        var seen = Set<String>()
        for id in recent + dockDefaults {
            if result.count >= limit { break }
            guard let item = byID[id], item.isDockable, seen.insert(id).inserted else { continue }
            result.append(item)
        }
        return result
    }
}
