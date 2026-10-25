import Foundation

/// The apps CarPlay supports, with what is needed to find them on the phone and match their icons.
///
/// Every URL scheme listed here must also be listed under `LSApplicationQueriesSchemes` in the app's
/// Info.plist (see `project.yml`), or iOS answers "not installed" for it. iOS allows at most 50.
/// `scripts/check_schemes.py` checks the two lists agree.
///
/// Schemes marked "best guess" are the ones I could not confirm. A wrong guess only means that app is
/// not found automatically; it can still be added by hand, and nothing is opened that was not detected.
public enum Catalog {
    private static func app(
        _ id: String, _ name: String, _ category: AppCategory,
        t: Int? = nil, m: String? = nil, v: String? = nil, s: String? = nil, w: String? = nil
    ) -> AppEntry {
        AppEntry(id: id, name: name, category: category, trackID: t, match: m, vendor: v, scheme: s, web: w)
    }

    public static let all: [AppEntry] = [
        // Navigation
        app("apple-maps", "Apple Maps", .navigation, t: 915056765, m: "maps", v: "apple", s: "maps", w: "https://maps.apple.com/"),
        app("google-maps", "Google Maps", .navigation, t: 585027354, m: "google maps", s: "comgooglemaps", w: "https://www.google.com/maps"),
        app("waze", "Waze", .navigation, t: 323229106, m: "waze", s: "waze", w: "https://waze.com/ul"),
        app("here-wego", "HERE WeGo", .navigation, t: 955837609, m: "here wego", w: "https://wego.here.com/"),
        app("sygic", "Sygic GPS", .navigation, t: 585193266, m: "sygic", s: "com.sygic.aura"),
        app("abrp", "A Better Routeplanner", .navigation, m: "routeplanner", w: "https://abetterrouteplanner.com/"),

        // Music and radio
        app("spotify", "Spotify", .audio, t: 324684580, m: "spotify", s: "spotify", w: "https://open.spotify.com/"),
        app("apple-music", "Apple Music", .audio, t: 1108187390, m: "apple music", v: "apple", s: "music", w: "https://music.apple.com/"),
        app("youtube-music", "YouTube Music", .audio, t: 1017492454, m: "youtube music", s: "youtubemusic", w: "https://music.youtube.com/"),
        app("amazon-music", "Amazon Music", .audio, t: 510855668, m: "amazon music", s: "amazonmusic"),
        app("pandora", "Pandora", .audio, t: 284035177, m: "pandora", s: "pandora"),
        app("deezer", "Deezer", .audio, t: 292738169, m: "deezer", s: "deezer"),
        app("tidal", "TIDAL", .audio, t: 913943275, m: "tidal", s: "tidal"),
        app("soundcloud", "SoundCloud", .audio, t: 336353151, m: "soundcloud", s: "soundcloud"),
        app("siriusxm", "SiriusXM", .audio, t: 317951436, m: "siriusxm", s: "siriusxm", w: "https://www.siriusxm.com/"), // scheme: best guess
        app("iheart", "iHeartRadio", .audio, t: 290638154, m: "iheart", s: "iheartradio", w: "https://www.iheart.com/"), // scheme: best guess
        app("tunein", "TuneIn Radio", .audio, t: 418987775, m: "tunein", s: "tunein", w: "https://tunein.com/"), // scheme: best guess

        // Podcasts and books
        app("apple-podcasts", "Podcasts", .talk, t: 525463029, m: "podcasts", v: "apple", s: "podcasts", w: "https://podcasts.apple.com/"),
        app("overcast", "Overcast", .talk, t: 888422857, m: "overcast", s: "overcast"),
        app("pocket-casts", "Pocket Casts", .talk, t: 414834813, m: "pocket casts", s: "pktc"),
        app("audible", "Audible", .talk, t: 379693831, m: "audible", s: "audible", w: "https://www.audible.com/"),
        app("libby", "Libby", .talk, t: 1076402606, m: "libby", s: "libbyapp"),
        app("apple-books", "Books", .talk, t: 364709193, m: "books", v: "apple", s: "ibooks"),

        // Messages and calls
        app("whatsapp", "WhatsApp", .messages, t: 310633997, m: "whatsapp", s: "whatsapp"),
        app("telegram", "Telegram", .messages, t: 686449807, m: "telegram", s: "tg"),
        app("messenger", "Messenger", .messages, t: 454638411, m: "messenger", s: "fb-messenger"),
        app("teams", "Microsoft Teams", .messages, t: 1113153706, m: "teams", s: "msteams"),
        app("zoom", "Zoom", .messages, t: 546505307, m: "zoom", s: "zoomus"),
        app("wechat", "WeChat", .messages, t: 414478124, m: "wechat", s: "weixin"),

        // Charging, fuel and parking
        app("plugshare", "PlugShare", .charging, m: "plugshare", w: "https://www.plugshare.com/"),
        app("chargepoint", "ChargePoint", .charging, m: "chargepoint", w: "https://driver.chargepoint.com/"),
        app("electrify-america", "Electrify America", .charging, m: "electrify america", w: "https://www.electrifyamerica.com/"),
        app("spothero", "SpotHero", .charging, m: "spothero", s: "spothero", w: "https://spothero.com/"), // scheme: best guess
        app("easypark", "EasyPark", .charging, m: "easypark", w: "https://easypark.com/"),

        // Assistants and more
        app("chatgpt", "ChatGPT", .more, t: 6448311069, m: "chatgpt", s: "chatgpt", w: "https://chatgpt.com/"), // scheme: best guess
        app("claude", "Claude", .more, t: 6473753684, m: "claude", s: "claude", w: "https://claude.ai/"), // scheme: best guess
        app("carrot", "CARROT Weather", .more, t: 961390574, m: "carrot")
    ]

    public static let byID: [String: AppEntry] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func entry(id: String) -> AppEntry? { byID[id] }

    public static func entry(trackID: Int) -> AppEntry? { all.first { $0.trackID == trackID } }

    /// Every scheme the app asks iOS about. Must equal the Info.plist list.
    public static var schemes: [String] {
        var seen = Set<String>()
        return all.compactMap { $0.scheme }.filter { seen.insert($0).inserted }
    }

    public static func apps(in category: AppCategory) -> [AppEntry] {
        all.filter { $0.category == category }
    }
}
