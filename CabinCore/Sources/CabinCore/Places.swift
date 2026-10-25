import Foundation

public enum PlaceKind: String, Codable, Hashable, Sendable {
    case home
    case work
    case pin

    public var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .pin: return "mappin"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlaceKind(rawValue: raw) ?? .pin
    }
}

public struct Place: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var kind: PlaceKind

    public init(id: UUID = UUID(), name: String, address: String = "", kind: PlaceKind = .pin) {
        self.id = id
        self.name = name
        self.address = address
        self.kind = kind
    }

    public var hasAddress: Bool { !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, name, address, kind
    }

    /// Tolerant decoding, so a save from another version never loses the user's places.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Place",
            address: try c.decodeIfPresent(String.self, forKey: .address) ?? "",
            kind: try c.decodeIfPresent(PlaceKind.self, forKey: .kind) ?? .pin
        )
    }
}

/// The maps app used when a place is tapped.
public enum NavApp: String, Codable, CaseIterable, Hashable, Sendable {
    case apple
    case google
    case waze

    public var title: String {
        switch self {
        case .apple: return "Apple Maps"
        case .google: return "Google Maps"
        case .waze: return "Waze"
        }
    }

    /// The scheme to ask iOS about, or nil when the app always exists (Apple Maps).
    public var scheme: String? {
        switch self {
        case .apple: return nil
        case .google: return "comgooglemaps"
        case .waze: return "waze"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NavApp(rawValue: raw) ?? .apple
    }

    /// Directions to `address`. Uses the app's own scheme when it is installed, and a web link otherwise.
    public func directionsURL(to address: String, appInstalled: Bool) -> URL? {
        let q = address.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        guard !q.isEmpty else { return nil }
        switch self {
        case .apple:
            return URL(string: "https://maps.apple.com/?daddr=\(q)&dirflg=d")
        case .google:
            if appInstalled { return URL(string: "comgooglemaps://?daddr=\(q)&directionsmode=driving") }
            return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(q)&travelmode=driving")
        case .waze:
            if appInstalled { return URL(string: "waze://?q=\(q)&navigate=yes") }
            return URL(string: "https://waze.com/ul?q=\(q)&navigate=yes")
        }
    }
}

public enum WebLink {
    /// Turns what someone typed ("spotify.com") into an https URL. Anything that is not a plain web address gives nil.
    public static func clean(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }
        if !text.contains("://") {
            // "mailto:a@b.com" and "javascript:..." have a scheme but no "//"; only a bare host should get https added.
            if let colon = text.firstIndex(of: ":"), text[text.startIndex..<colon].allSatisfy({ $0.isLetter }) { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, host.contains(".") else { return nil }
        return url
    }

    private static let notAppSchemes: Set<String> = [
        "http", "https", "file", "ftp", "javascript", "data", "blob", "about", "sms", "mailto", "tel", "facetime"
    ]

    /// "myapp://anything" gives "myapp": the launch link of an app. Web addresses and system links give nil.
    public static func appScheme(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { $0.isWhitespace }), let range = text.range(of: "://") else { return nil }
        let scheme = text[text.startIndex..<range.lowerBound].lowercased()
        guard let first = scheme.first, first.isLetter, !notAppSchemes.contains(scheme),
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "+") }) else { return nil }
        return scheme
    }
}
