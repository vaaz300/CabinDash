import Foundation

public enum ThemeChoice: String, Codable, CaseIterable, Hashable, Sendable {
    case auto
    case day
    case night

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .day: return "Day"
        case .night: return "Night"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ThemeChoice(rawValue: raw) ?? .auto
    }
}

/// The wallpaper is three soft trails of light. Each case gives the three hues (degrees on the colour wheel).
public enum Wallpaper: String, Codable, CaseIterable, Hashable, Sendable {
    case dusk
    case coast
    case ember
    case city
    case forest
    case graphite

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public var hues: [Double] {
        switch self {
        case .dusk: return [285, 28, 215]
        case .coast: return [176, 205, 140]
        case .ember: return [8, 34, 330]
        case .city: return [322, 198, 255]
        case .forest: return [146, 92, 182]
        case .graphite: return [215, 240, 200]
        }
    }

    /// Colour strength, 0...1. Graphite is nearly grey.
    public var saturation: Double { self == .graphite ? 0.10 : 0.92 }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Wallpaper(rawValue: raw) ?? .dusk
    }
}

/// Everything the user chooses, saved as one value. Decoding is tolerant so new fields never wipe old saves.
public struct Preferences: Codable, Equatable, Sendable {
    public var units: Units
    public var navApp: NavApp
    public var theme: ThemeChoice
    public var wallpaper: Wallpaper
    public var keepAwake: Bool
    /// Adds an Apps button to the dock that lists apps installed on this iPhone. Off by default: Cabin Dash is meant to be self-contained.
    public var showOtherApps: Bool
    /// Show catalog apps that are installed on this iPhone without being asked.
    public var autoDetect: Bool
    /// Apps the user added by hand (catalog apps that cannot be detected, search results, web shortcuts).
    public var added: [AppEntry]
    /// Detected apps the user removed from the shelf.
    public var hidden: Set<String>
    public var places: [Place]
    /// Most recently opened app ids, newest first.
    public var recent: [String]
    /// Someone other than the driver is using the screen, so typing stays available while the car moves.
    public var passengerMode: Bool

    public init(
        units: Units = .kmh, navApp: NavApp = .apple, theme: ThemeChoice = .auto, wallpaper: Wallpaper = .dusk,
        keepAwake: Bool = true, showOtherApps: Bool = false, autoDetect: Bool = true, added: [AppEntry] = [], hidden: Set<String> = [],
        places: [Place] = Preferences.starterPlaces(), recent: [String] = [], passengerMode: Bool = false
    ) {
        self.units = units
        self.navApp = navApp
        self.theme = theme
        self.wallpaper = wallpaper
        self.keepAwake = keepAwake
        self.showOtherApps = showOtherApps
        self.autoDetect = autoDetect
        self.added = added
        self.hidden = hidden
        self.places = places
        self.recent = recent
        self.passengerMode = passengerMode
    }

    public static func starterPlaces() -> [Place] {
        [Place(name: "Home", kind: .home), Place(name: "Work", kind: .work)]
    }

    public static func defaults(region: String?) -> Preferences {
        Preferences(units: Units.preferred(forRegion: region))
    }

    private enum CodingKeys: String, CodingKey {
        case units, navApp, theme, wallpaper, keepAwake, showOtherApps, autoDetect, added, hidden, places, recent, passengerMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = Preferences()
        self.init(
            units: try c.decodeIfPresent(Units.self, forKey: .units) ?? base.units,
            navApp: try c.decodeIfPresent(NavApp.self, forKey: .navApp) ?? base.navApp,
            theme: try c.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? base.theme,
            wallpaper: try c.decodeIfPresent(Wallpaper.self, forKey: .wallpaper) ?? base.wallpaper,
            keepAwake: try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? base.keepAwake,
            showOtherApps: try c.decodeIfPresent(Bool.self, forKey: .showOtherApps) ?? base.showOtherApps,
            autoDetect: try c.decodeIfPresent(Bool.self, forKey: .autoDetect) ?? base.autoDetect,
            added: try c.decodeIfPresent([AppEntry].self, forKey: .added) ?? base.added,
            hidden: try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? base.hidden,
            places: try c.decodeIfPresent([Place].self, forKey: .places) ?? base.places,
            recent: try c.decodeIfPresent([String].self, forKey: .recent) ?? base.recent,
            passengerMode: try c.decodeIfPresent(Bool.self, forKey: .passengerMode) ?? base.passengerMode
        )
    }

    // MARK: Shelf editing

    public func isOnShelf(_ app: AppEntry, installed: Set<String>) -> Bool {
        if autoDetect, installed.contains(app.id), !hidden.contains(app.id) { return true }
        return added.contains { $0.id == app.id }
    }

    public mutating func addApp(_ app: AppEntry, installed: Set<String>) {
        hidden.remove(app.id)
        if autoDetect, installed.contains(app.id) { return } // it shows up on its own
        if !added.contains(where: { $0.id == app.id }) { added.append(app) }
    }

    public mutating func removeApp(_ app: AppEntry, installed: Set<String>) {
        added.removeAll { $0.id == app.id }
        recent.removeAll { $0 == app.id }
        if autoDetect, installed.contains(app.id) { hidden.insert(app.id) }
    }

    public mutating func noteLaunch(_ app: AppEntry) {
        noteRecent(app.id)
    }

    /// Remembers that an app, or one of Cabin Dash's own screens ("maps", "now-playing", "drive"), was just opened.
    public mutating func noteRecent(_ id: String) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if recent.count > 6 { recent.removeLast(recent.count - 6) }
    }

    public mutating func resetApps() {
        added = []
        hidden = []
        recent = []
        autoDetect = true
    }
}

public struct ShelfSection: Identifiable, Equatable, Sendable {
    public let category: AppCategory
    public let apps: [AppEntry]
    public var id: AppCategory { category }

    public init(category: AppCategory, apps: [AppEntry]) {
        self.category = category
        self.apps = apps
    }
}

public enum Shelf {
    /// Detected catalog apps first (in catalog order), then the apps added by hand, without duplicates.
    public static func compose(installed: Set<String>, preferences p: Preferences) -> [AppEntry] {
        var seen = Set<String>()
        var result: [AppEntry] = []
        if p.autoDetect {
            for app in Catalog.all where installed.contains(app.id) && !p.hidden.contains(app.id) {
                if seen.insert(app.id).inserted { result.append(app) }
            }
        }
        for stored in p.added {
            let app = Catalog.entry(id: stored.id) ?? stored // catalog updates win over old saves
            if seen.insert(app.id).inserted { result.append(app) }
        }
        return result
    }

    /// Groups apps by category, in the order of `AppCategory.allCases`, leaving out empty groups.
    public static func sections(_ apps: [AppEntry]) -> [ShelfSection] {
        AppCategory.allCases.compactMap { category in
            let inCategory = apps.filter { $0.category == category }
            return inCategory.isEmpty ? nil : ShelfSection(category: category, apps: inCategory)
        }
    }

    /// The recent apps that are still on the shelf, newest first, at most four.
    public static func recents(_ apps: [AppEntry], ids: [String]) -> [AppEntry] {
        let byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }.prefix(4).map { $0 }
    }
}
