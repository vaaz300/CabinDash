import CabinCore
import Foundation
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "app.cabindash", category: "icons")

/// Finds, remembers and serves each app's icon.
///
/// iOS does not let one app read another app's icon, so the icons come from the App Store, where every
/// app has the same artwork. A result is only accepted when its name (and, for Apple's own apps, its
/// publisher) matches, so a wrong id can never put another app's icon on a tile.
@MainActor @Observable
final class IconStore {
    /// Decoded icons by `AppEntry.iconKey`. Views read this, so they redraw when an icon arrives.
    private(set) var images: [String: UIImage] = [:]

    @ObservationIgnored private var records: [String: IconRecord]
    @ObservationIgnored private let loader = ImageLoader()
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let country: String
    @ObservationIgnored private let recordsURL: URL

    /// Name searches are slow and rate limited, so a pass does a few and carries on next time.
    private static let searchesPerPass = 6
    private static let searchGap: Duration = .milliseconds(1200)

    init(country: String) {
        self.country = country
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
        let url = Self.makeRecordsURL()
        self.recordsURL = url
        self.records = Self.readRecords(from: url)
    }

    func image(for app: AppEntry) -> UIImage? {
        images[app.iconKey]
    }

    // MARK: Showing icons

    /// Puts an already-known icon on screen. Cheap when it is in memory or on disk.
    func ensureImage(for app: AppEntry) async {
        let key = app.iconKey
        guard !app.isCustom, images[key] == nil,
              let text = records[key]?.url, let url = URL(string: text) else { return }
        if let image = await loader.image(for: url), images[key] == nil {
            images[key] = image
        }
    }

    // MARK: Finding icons

    /// Makes sure every app in `apps` has a fresh icon record, asking the App Store only for the ones that need it.
    func sync(_ apps: [AppEntry]) async {
        let now = Date()
        let candidates = apps.filter { !$0.isCustom }
        let stale = candidates.filter { !(records[$0.iconKey]?.isFresh(at: now) ?? false) }
        guard !stale.isEmpty else { return }

        var needsSearch = stale.filter { $0.trackID == nil }
        let withID = stale.filter { $0.trackID != nil }

        if !withID.isEmpty {
            let ids = withID.compactMap(\.trackID)
            // nil means the request failed (offline, say), so nothing is recorded and the next pass tries again.
            guard let results = await fetch(StoreAPI.lookupURL(ids: ids, country: country)) else { return }
            var byID: [Int: StoreResult] = [:]
            for result in results {
                if let id = result.trackId, byID[id] == nil { byID[id] = result }
            }
            for app in withID {
                if let id = app.trackID, let result = byID[id], IconMatcher.verify(app, result), let url = result.artworkURL {
                    await save(app, url: url)
                } else {
                    needsSearch.append(app)
                }
            }
        }

        var searched = 0
        for app in needsSearch {
            if Task.isCancelled || searched >= Self.searchesPerPass { return }
            if searched > 0 {
                try? await Task.sleep(for: Self.searchGap)
                if Task.isCancelled { return }
            }
            searched += 1
            guard let results = await fetch(StoreAPI.searchURL(term: app.name, country: country)) else { return }
            if let hit = results.first(where: { IconMatcher.verify(app, $0) }), let url = hit.artworkURL {
                await save(app, url: url)
            } else {
                log.info("No App Store icon found for \(app.name, privacy: .public)")
                records[app.iconKey] = IconRecord(url: nil, fetchedAt: Date())
                persist()
            }
        }
    }

    /// Searches the App Store for apps to add. The icons of the results are remembered, so they show straight away.
    /// Returns nil when the App Store could not be reached.
    func search(_ term: String) async -> [AppEntry]? {
        guard let results = await fetch(StoreAPI.searchURL(term: term, country: country)) else { return nil }
        var seen = Set<String>()
        var entries: [AppEntry] = []
        for result in results {
            guard let entry = IconMatcher.entry(from: result), seen.insert(entry.id).inserted else { continue }
            entries.append(entry)
            if let url = result.artworkURL, records[entry.iconKey]?.url == nil {
                records[entry.iconKey] = IconRecord(url: url.absoluteString, fetchedAt: Date())
            }
        }
        persist()
        return entries
    }

    /// Forget every stored icon and start again.
    func reset() async {
        records = [:]
        images = [:]
        persist()
        await loader.purge()
    }

    // MARK: Private

    private func save(_ app: AppEntry, url: URL) async {
        records[app.iconKey] = IconRecord(url: url.absoluteString, fetchedAt: Date())
        persist()
        if let image = await loader.image(for: url) {
            images[app.iconKey] = image
        }
    }

    private func fetch(_ url: URL?) async -> [StoreResult]? {
        guard let url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(StoreResponse.self, from: data).results
        } catch {
            if !(error is CancellationError) {
                log.info("App Store request failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: recordsURL, options: .atomic)
    }

    private static func makeRecordsURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("CabinDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("icon-records.json")
    }

    private static func readRecords(from url: URL) -> [String: IconRecord] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: IconRecord].self, from: data)) ?? [:]
    }
}
