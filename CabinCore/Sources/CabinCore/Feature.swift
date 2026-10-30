import Foundation

/// The screens Cabin Dash draws itself. Everything the driver can do without leaving the app lives in one of these.
public enum Feature: String, CaseIterable, Codable, Hashable, Sendable {
    case dashboard
    case map
    case music
    /// Contacts, favourites, a keypad and calls placed from Cabin Dash. iOS's own call screen takes over for the call.
    case phone
    case drive
    case settings
    /// The optional list of other apps installed on the iPhone. Opening one of them leaves Cabin Dash.
    case apps

    public var title: String {
        switch self {
        case .dashboard: return "Home"
        case .map: return "Map"
        case .music: return "Music"
        case .phone: return "Phone"
        case .drive: return "Drive"
        case .settings: return "Settings"
        case .apps: return "Apps"
        }
    }

    /// An SF Symbol name.
    public var symbol: String {
        switch self {
        case .dashboard: return "house.fill"
        case .map: return "map.fill"
        case .music: return "music.note"
        case .phone: return "phone.fill"
        case .drive: return "speedometer"
        case .settings: return "gearshape.fill"
        case .apps: return "square.grid.2x2.fill"
        }
    }

    public var tone: HomeTone {
        switch self {
        case .dashboard: return .graphite
        case .map: return .green
        case .music: return .red
        case .phone: return .green
        case .drive: return .orange
        case .settings: return .graphite
        case .apps: return .blue
        }
    }
}

/// What the rail shows: pages of up to four buttons, swiped between, always in the same order so the driver finds the
/// same button in the same place. The first page holds what is used while driving.
public enum Dock {
    public static let perPage = 4

    /// Every button in order: Home, Map, Music, Phone, then Drive, Apps (only when the Other apps switch is on) and Settings.
    public static func pages(showOtherApps: Bool) -> [[Feature]] {
        var all: [Feature] = [.dashboard, .map, .music, .phone, .drive]
        if showOtherApps { all.append(.apps) }
        all.append(.settings)
        return stride(from: 0, to: all.count, by: perPage).map { Array(all[$0..<min($0 + perPage, all.count)]) }
    }

    /// The page holding `feature`, or nil when it is not in the dock.
    public static func page(of feature: Feature, showOtherApps: Bool) -> Int? {
        pages(showOtherApps: showOtherApps).firstIndex { $0.contains(feature) }
    }

    public static func isAvailable(_ feature: Feature, showOtherApps: Bool) -> Bool {
        feature != .apps || showOtherApps
    }
}

/// Which feature is on screen. Pure state, so the rules can be tested without a phone.
public struct Router: Equatable, Sendable {
    public private(set) var current: Feature

    public init(current: Feature = .dashboard) {
        self.current = current
    }

    /// Moves to `feature`, unless it is not available right now.
    public mutating func go(_ feature: Feature, showOtherApps: Bool) {
        guard Dock.isAvailable(feature, showOtherApps: showOtherApps) else { return }
        current = feature
    }

    /// Call after the Other apps switch changes: leaves the Apps screen if it just went away.
    public mutating func reconcile(showOtherApps: Bool) {
        if !Dock.isAvailable(current, showOtherApps: showOtherApps) {
            current = .dashboard
        }
    }
}

/// A thin bar that follows the driver from screen to screen.
public enum Strip: Hashable, Sendable {
    /// A call is in progress, ringing or being placed.
    case call
    case route
    case music
}

public enum Strips {
    /// The strips to show on `feature`, most urgent first. A feature never repeats its own information in a strip,
    /// and the Dashboard already has a widget for each, so it shows none.
    public static func visible(on feature: Feature, musicActive: Bool, routeGuiding: Bool, callActive: Bool = false) -> [Strip] {
        guard feature != .dashboard else { return [] }
        var result: [Strip] = []
        if callActive, feature != .phone { result.append(.call) }
        if routeGuiding, feature != .map { result.append(.route) }
        if musicActive, feature != .music { result.append(.music) }
        return result
    }
}

/// How big the rail buttons are, so every button fits whatever the screen height.
public enum DockMetrics {
    public static let minIcon = 30.0
    public static let maxIcon = 52.0
    /// The gap between buttons, as a fraction of a button.
    public static let gapRatio = 0.2

    /// The largest icon, up to `maxIcon`, for which `itemCount` icons and the gaps between them fit in `availableHeight`.
    /// Never below `minIcon`: on a very short screen the buttons stay tappable and the rail is allowed to be tight.
    public static func iconSize(availableHeight: Double, itemCount: Int) -> Double {
        guard itemCount > 0 else { return maxIcon }
        guard availableHeight > 0 else { return minIcon }
        let count = Double(itemCount)
        let fit = availableHeight / (count + gapRatio * (count - 1))
        return min(maxIcon, max(minIcon, fit))
    }

    public static func gap(forIconSize size: Double) -> Double {
        size * gapRatio
    }
}
