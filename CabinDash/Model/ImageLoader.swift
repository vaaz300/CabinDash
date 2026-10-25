import CryptoKit
import ImageIO
import OSLog
import UIKit

private let log = Logger(subsystem: "app.cabindash", category: "images")

/// Downloads icon artwork once, keeps it on disk and in memory, and shares a download that is already running.
actor ImageLoader {
    private let memory = NSCache<NSURL, UIImage>()
    private let directory: URL
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = caches.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let running = inFlight[url] { return await running.value }
        let task = Task { await self.load(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    /// Forget everything that was downloaded.
    func purge() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func load(_ url: URL) async -> UIImage? {
        let file = directory.appendingPathComponent(Self.fileName(for: url))
        if let data = try? Data(contentsOf: file), let image = Self.thumbnail(from: data) {
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = Self.thumbnail(from: data) else {
                log.debug("Icon download was not usable: \(url.absoluteString, privacy: .public)")
                return nil
            }
            try? data.write(to: file, options: .atomic)
            memory.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            log.debug("Icon download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    /// Decodes at most 256 pixels on the long side, which is plenty for a 64 point icon on a 3x screen.
    private static func thumbnail(from data: Data, maxPixel: Int = 256) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
