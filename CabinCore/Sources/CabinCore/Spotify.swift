import Foundation

/// What the Now Playing screen shows, read from Spotify's "current playback" answer.
public struct NowPlaying: Equatable, Sendable {
    public var trackID: String?
    public var title: String
    /// The artists, or the show for a podcast episode.
    public var subtitle: String
    public var album: String
    public var artworkURL: URL?
    /// Seconds.
    public var duration: TimeInterval
    /// Seconds into the track at the moment Spotify answered.
    public var progress: TimeInterval
    public var isPlaying: Bool
    public var deviceName: String?

    public init(
        trackID: String? = nil, title: String, subtitle: String = "", album: String = "", artworkURL: URL? = nil,
        duration: TimeInterval = 0, progress: TimeInterval = 0, isPlaying: Bool = false, deviceName: String? = nil
    ) {
        self.trackID = trackID
        self.title = title
        self.subtitle = subtitle
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.progress = progress
        self.isPlaying = isPlaying
        self.deviceName = deviceName
    }

    /// 0...1, how far through the track.
    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, progress / duration))
    }
}

public enum SpotifyPlayback {
    /// Reads the answer of `GET /v1/me/player`. Returns nil for an empty body (nothing is playing anywhere),
    /// for something that is not JSON, and when no track or episode is loaded.
    public static func parse(_ data: Data) -> NowPlaying? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let item = root["item"] as? [String: Any],
              let title = item["name"] as? String else { return nil }

        let artistList = (item["artists"] as? [[String: Any]]) ?? []
        let artists = artistList.compactMap { $0["name"] as? String }
        let show = item["show"] as? [String: Any]
        let album = item["album"] as? [String: Any]
        let subtitle = artists.isEmpty ? ((show?["name"] as? String) ?? "") : artists.joined(separator: ", ")

        // Tracks keep their pictures on the album, episodes on the episode or the show.
        let images = (album?["images"] as? [[String: Any]])
            ?? (item["images"] as? [[String: Any]])
            ?? (show?["images"] as? [[String: Any]])
            ?? []
        let device = root["device"] as? [String: Any]

        return NowPlaying(
            trackID: item["id"] as? String,
            title: title,
            subtitle: subtitle,
            album: (album?["name"] as? String) ?? "",
            artworkURL: largestImage(in: images),
            duration: number(item["duration_ms"]) / 1000,
            progress: number(root["progress_ms"]) / 1000,
            isPlaying: (root["is_playing"] as? Bool) ?? false,
            deviceName: device?["name"] as? String
        )
    }

    static func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }

    /// The widest picture. Spotify lists them largest first, but that is not promised.
    static func largestImage(in images: [[String: Any]]) -> URL? {
        var best: (width: Double, url: URL)?
        for image in images {
            guard let text = image["url"] as? String, let url = URL(string: text) else { continue }
            let width = number(image["width"])
            if best == nil || width > (best?.width ?? 0) {
                best = (width, url)
            }
        }
        return best?.url
    }
}

/// Why a Spotify request did not work, in words a driver can act on.
public enum SpotifyFailure: Error, Equatable, Sendable {
    case notSignedIn
    case noActiveDevice
    case premiumRequired
    case notAllowed
    case rateLimited(retryAfter: Int)
    case http(Int)
    case offline

    /// Works out the failure from the HTTP status and Spotify's error body, e.g.
    /// `{"error":{"status":404,"message":"...","reason":"NO_ACTIVE_DEVICE"}}`.
    public static func classify(status: Int, body: Data, retryAfter: String? = nil) -> SpotifyFailure {
        switch status {
        case 401:
            return .notSignedIn
        case 429:
            return .rateLimited(retryAfter: Int(retryAfter ?? "") ?? 3)
        default:
            break
        }
        let reason = reasonCode(in: body)
        if reason == "NO_ACTIVE_DEVICE" { return .noActiveDevice }
        if reason == "PREMIUM_REQUIRED" { return .premiumRequired }
        if status == 403 { return .notAllowed }
        return .http(status)
    }

    static func reasonCode(in body: Data) -> String? {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body),
              let root = object as? [String: Any],
              let error = root["error"] as? [String: Any] else { return nil }
        return error["reason"] as? String
    }

    public var message: String {
        switch self {
        case .notSignedIn: return "Connect Spotify to see what is playing."
        case .noActiveDevice: return "Open Spotify and start playing something, then try again."
        case .premiumRequired: return "Spotify only lets Premium accounts control playback from other apps."
        case .notAllowed: return "Spotify refused the request. Check that your account is listed under User Management for this app."
        case .rateLimited: return "Spotify asked Cabin Dash to slow down. It will try again in a moment."
        case .http(let status): return "Spotify returned an error (\(status))."
        case .offline: return "No internet connection."
        }
    }
}
