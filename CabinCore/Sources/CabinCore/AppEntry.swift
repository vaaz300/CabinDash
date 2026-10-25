import Foundation

/// One app that can appear on the shelf: a catalog app, an app found by App Store search,
/// or a web shortcut the user typed in.
public struct AppEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var category: AppCategory
    /// The App Store id. Used for the App Store page and for looking up the app's icon.
    public var trackID: Int?
    /// Lowercase name an App Store result must contain (as whole words) before its icon is accepted.
    public var match: String
    /// Lowercase fragment the App Store publisher must contain. Stops "Maps" matching Google Maps.
    public var vendor: String?
    /// URL scheme without "://". Used to detect the app and to open it.
    public var scheme: String?
    /// Web page opened when the app is not installed (or has no URL scheme).
    public var web: String?
    /// Publisher name, shown for apps found through search.
    public var publisher: String?
    /// True for web shortcuts the user typed in. These never get App Store artwork.
    public var isCustom: Bool

    public init(
        id: String,
        name: String,
        category: AppCategory,
        trackID: Int? = nil,
        match: String? = nil,
        vendor: String? = nil,
        scheme: String? = nil,
        web: String? = nil,
        publisher: String? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.trackID = trackID
        self.match = (match ?? name).lowercased()
        self.vendor = vendor?.lowercased()
        self.scheme = scheme
        self.web = web
        self.publisher = publisher
        self.isCustom = isCustom
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, trackID, match, vendor, scheme, web, publisher, isCustom
    }

    /// Tolerant decoding: a missing optional field never throws away the user's saved apps.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let category = try c.decodeIfPresent(AppCategory.self, forKey: .category) ?? .more
        let trackID = try c.decodeIfPresent(Int.self, forKey: .trackID)
        let match = try c.decodeIfPresent(String.self, forKey: .match)
        let vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
        let scheme = try c.decodeIfPresent(String.self, forKey: .scheme)
        let web = try c.decodeIfPresent(String.self, forKey: .web)
        let publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        let isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        self.init(
            id: id, name: name, category: category, trackID: trackID, match: match, vendor: vendor,
            scheme: scheme, web: web, publisher: publisher, isCustom: isCustom
        )
    }

    /// Whether the app can be found by asking iOS if its URL scheme is registered.
    public var canBeDetected: Bool { scheme != nil }

    /// Key for the icon cache. An App Store id is exact; a name is the fallback.
    public var iconKey: String {
        if let trackID { return "t\(trackID)" }
        return "n:" + match
    }

    public var schemeURL: URL? {
        guard let scheme else { return nil }
        return URL(string: scheme + "://")
    }

    /// Where to send the user when the app is not installed or cannot be opened directly.
    public var fallbackURL: URL {
        if let web, let url = URL(string: web) { return url }
        if let trackID, let url = URL(string: "https://apps.apple.com/app/id\(trackID)") { return url }
        let term = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://apps.apple.com/search?term=" + term) ?? URL(string: "https://apps.apple.com")!
    }

    /// The URL to open when the user taps the app.
    public func launchURL(installed: Bool) -> URL {
        if installed, let url = schemeURL { return url }
        return fallbackURL
    }

    /// Everything to try, in order, when the app is tapped: its own link first (iOS reports failure when
    /// nothing handles it), then the web or App Store page. This also works for apps that could not be detected.
    public var launchSequence: [URL] {
        var urls: [URL] = []
        if let schemeURL { urls.append(schemeURL) }
        urls.append(fallbackURL)
        return urls
    }
}
