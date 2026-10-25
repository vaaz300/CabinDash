import Foundation

/// Apple's public iTunes Search API. It is how the app gets each app's real icon: iOS has no way to read
/// the icon of an app installed on the phone, but every app's App Store artwork is the same image.
public enum StoreAPI {
    /// The App Store country to ask. Falls back to the US store when the phone has no region set.
    public static func country(forRegion region: String?) -> String {
        guard let region, region.count == 2 else { return "us" }
        return region.lowercased()
    }

    public static func lookupURL(ids: [Int], country: String) -> URL? {
        guard !ids.isEmpty else { return nil }
        let list = ids.map(String.init).joined(separator: ",")
        return URL(string: "https://itunes.apple.com/lookup?id=\(list)&country=\(country)")
    }

    public static func searchURL(term: String, country: String) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        return URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=software&limit=10&country=\(country)")
    }
}

extension CharacterSet {
    /// Letters, digits and "-._~" only. `urlQueryAllowed` leaves "&", "+" and "=" alone, which breaks values.
    public static let urlQueryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}

public struct StoreResponse: Decodable, Sendable {
    public let results: [StoreResult]

    public init(results: [StoreResult]) { self.results = results }
}

/// One app in an iTunes API response. Every field is optional so one odd result cannot fail the whole decode.
public struct StoreResult: Decodable, Sendable, Equatable {
    public let trackId: Int?
    public let trackName: String?
    public let sellerName: String?
    public let artistName: String?
    public let primaryGenreName: String?
    public let artworkUrl512: String?
    public let artworkUrl100: String?
    public let artworkUrl60: String?

    public init(
        trackId: Int? = nil, trackName: String? = nil, sellerName: String? = nil, artistName: String? = nil,
        primaryGenreName: String? = nil, artworkUrl512: String? = nil, artworkUrl100: String? = nil, artworkUrl60: String? = nil
    ) {
        self.trackId = trackId
        self.trackName = trackName
        self.sellerName = sellerName
        self.artistName = artistName
        self.primaryGenreName = primaryGenreName
        self.artworkUrl512 = artworkUrl512
        self.artworkUrl100 = artworkUrl100
        self.artworkUrl60 = artworkUrl60
    }

    /// The largest artwork offered, as long as it is served over https.
    public var artworkURL: URL? {
        for candidate in [artworkUrl512, artworkUrl100, artworkUrl60] {
            if let candidate, candidate.hasPrefix("https://"), let url = URL(string: candidate) { return url }
        }
        return nil
    }
}

/// Decides whether an App Store result really is the app we asked about, so a wrong id or a loose name
/// search never puts another app's icon on a tile.
public enum IconMatcher {
    /// True when `needle` appears in `haystack` as whole words: "mine" matches "Mine - Notes" but not "Minecraft".
    public static func containsWord(_ haystack: String, _ needle: String) -> Bool {
        let hay = haystack.lowercased()
        let pin = needle.lowercased()
        guard !pin.isEmpty else { return false }
        var from = hay.startIndex
        while from < hay.endIndex, let found = hay.range(of: pin, range: from..<hay.endIndex) {
            let beforeOK = found.lowerBound == hay.startIndex || !isWordCharacter(hay[hay.index(before: found.lowerBound)])
            let afterOK = found.upperBound == hay.endIndex || !isWordCharacter(hay[found.upperBound])
            if beforeOK && afterOK { return true }
            from = hay.index(after: found.lowerBound)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    public static func verify(_ app: AppEntry, _ result: StoreResult) -> Bool {
        guard let name = result.trackName, containsWord(name, app.match) else { return false }
        if let vendor = app.vendor, !vendor.isEmpty {
            let publisher = ((result.sellerName ?? "") + " " + (result.artistName ?? "")).lowercased()
            return publisher.contains(vendor)
        }
        return true
    }

    /// "Spotify: Music and Podcasts" becomes "Spotify".
    public static func shortName(_ full: String) -> String {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [" - ", " \u{2013} ", " \u{2014} ", ": "]
        var cut = trimmed.endIndex
        for separator in separators {
            if let found = trimmed.range(of: separator), found.lowerBound < cut { cut = found.lowerBound }
        }
        let short = trimmed[trimmed.startIndex..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
        return short.isEmpty ? trimmed : short
    }

    public static func category(forGenre genre: String?) -> AppCategory {
        switch (genre ?? "").lowercased() {
        case "navigation": return .navigation
        case "music": return .audio
        case "social networking": return .messages
        case "books": return .talk
        default: return .more
        }
    }

    /// Turns a search result into a shelf entry. An app that is already in the catalog comes back as the
    /// catalog entry, so searching for Spotify never creates a second Spotify.
    public static func entry(from result: StoreResult) -> AppEntry? {
        guard let id = result.trackId, let fullName = result.trackName else { return nil }
        if let known = Catalog.entry(trackID: id) {
            var entry = known
            entry.publisher = result.sellerName
            return entry
        }
        let name = shortName(fullName)
        return AppEntry(
            id: "t\(id)", name: name, category: category(forGenre: result.primaryGenreName),
            trackID: id, match: name, publisher: result.sellerName
        )
    }
}
