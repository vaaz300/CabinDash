import Foundation

/// What the app remembers about one app's icon. `url == nil` records "looked and found nothing",
/// so an app the App Store does not know is not asked about again straight away.
public struct IconRecord: Codable, Equatable, Sendable {
    public var url: String?
    public var fetchedAt: Date

    public init(url: String?, fetchedAt: Date) {
        self.url = url
        self.fetchedAt = fetchedAt
    }

    public static let hitLifetime: TimeInterval = 30 * 24 * 3600
    public static let missLifetime: TimeInterval = 24 * 3600

    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0 else { return false }
        return age < (url == nil ? Self.missLifetime : Self.hitLifetime)
    }
}
