import CabinCore
import Foundation
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "app.cabindash", category: "app")

/// Everything the screens share: the user's choices, which apps are installed, and what happens on a tap.
@MainActor @Observable
final class AppModel {
    var prefs: Preferences
    /// Which of Cabin Dash's own screens is showing.
    private(set) var router = Router()
    var pickerPresented = false
    /// Ids of catalog apps whose URL scheme this iPhone answered "yes" to.
    private(set) var installed: Set<String> = []

    let icons: IconStore
    let toast: ToastCenter
    let device = DeviceStatus()
    let spotify: SpotifyModel
    /// Playlists, Liked Songs, search and the queue, for the Music screen.
    let library: SpotifyLibraryModel
    let route = RouteModel()

    /// True while the car is going faster than about 8 km/h. Assigned only when it changes, so screens do not redraw on every GPS fix.
    private(set) var isMoving = false
    @ObservationIgnored private var lock = DrivingLock()

    @ObservationIgnored private let defaults: UserDefaults
    private static let prefsKey = "cabin-dash.prefs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let region = Locale.current.region?.identifier
        if let data = defaults.data(forKey: Self.prefsKey),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            prefs = saved
        } else {
            prefs = Preferences.defaults(region: region)
        }
        icons = IconStore(country: StoreAPI.country(forRegion: region))
        let toast = ToastCenter()
        let spotify = SpotifyModel()
        self.toast = toast
        self.spotify = spotify
        library = SpotifyLibraryModel(spotify: spotify, toast: toast)
    }

    // MARK: Driving lock

    /// Typing, such as music search, is switched off while the car is moving, unless Passenger mode is on.
    var typingLocked: Bool {
        isMoving && !prefs.passengerMode
    }

    /// Call with every GPS fix. `speed` is metres per second, or nil when there is no usable fix.
    func noteMotion(speed: Double?, at time: Double) {
        lock.update(speed: speed, at: time)
        if lock.isMoving != isMoving { isMoving = lock.isMoving }
    }

    // MARK: Shelf

    var shelf: [AppEntry] {
        Shelf.compose(installed: installed, preferences: prefs)
    }

    /// Every tile of the Other apps screen, in order.
    var homeItems: [HomeItem] {
        HomeLayout.items(shelf: shelf)
    }

    func isOnShelf(_ app: AppEntry) -> Bool {
        prefs.isOnShelf(app, installed: installed)
    }

    func isDetected(_ app: AppEntry) -> Bool {
        installed.contains(app.id)
    }

    func add(_ app: AppEntry) {
        prefs.addApp(app, installed: installed)
        toast.show("Added \(app.name)")
    }

    func remove(_ app: AppEntry) {
        let before = prefs
        prefs.removeApp(app, installed: installed)
        toast.show("Removed \(app.name)", actionTitle: "Undo") { [weak self] in self?.prefs = before }
    }

    func resetApps() {
        prefs.resetApps()
        toast.show("Apps reset")
    }

    // MARK: Start up

    /// First launch: find installed apps and start the GPS. Async so it can be awaited from a view's task.
    func startUp(location: LocationModel) async {
        refreshInstalled()
        device.start()
        location.start()
    }

    // MARK: Detection

    /// Asks iOS which catalog apps are installed. Needs every scheme listed in Info.plist.
    func refreshInstalled() {
        var found = Set<String>()
        for app in Catalog.all {
            if let url = app.schemeURL, UIApplication.shared.canOpenURL(url) { found.insert(app.id) }
        }
        if found != installed {
            installed = found
            log.info("Detected \(found.count) installed catalog apps")
        }
    }

    func canOpen(scheme: String) -> Bool {
        guard let url = URL(string: scheme + "://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: Icons

    func syncIcons() async {
        await icons.sync(iconTargets)
    }

    /// The apps whose App Store artwork the Other apps screen needs. Empty while that screen is off, so nothing is looked up.
    var iconTargets: [AppEntry] {
        HomeLayout.iconApps(shelf: shelf, showOtherApps: prefs.showOtherApps)
    }

    /// Pull to refresh: look for installed apps again, then fetch any missing icons.
    func reloadAll() async {
        refreshInstalled()
        await syncIcons()
    }

    func refreshIcons() async {
        await icons.reset()
        await icons.sync(iconTargets)
    }

    // MARK: Opening things

    /// Goes to one of Cabin Dash's own screens. Ignored when that screen is not available, such as Apps while Other apps is off.
    func go(_ feature: Feature) {
        guard Dock.isAvailable(feature, showOtherApps: prefs.showOtherApps) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        router.go(feature, showOtherApps: prefs.showOtherApps)
    }

    /// Call after the Other apps switch changes, so the Apps screen does not stay up once its button is gone.
    func reconcileRouter() {
        router.reconcile(showOtherApps: prefs.showOtherApps)
    }

    /// What a tap on a tile of the Other apps screen does.
    func open(_ item: HomeItem) {
        switch item.kind {
        case .url(let url):
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            prefs.noteRecent(item.id)
            open([url], failure: "Couldn't open \(item.title)")
        case .addApps:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            pickerPresented = true
        case .app(let app):
            launch(app)
        }
    }

    func launch(_ app: AppEntry) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        prefs.noteLaunch(app)
        open(app.launchSequence, failure: "Couldn't open \(app.name)")
    }

    /// The "Open Spotify" link. With a URI it opens that track, album or playlist in the Spotify app (or its web page if the
    /// app is not installed); without one it opens Spotify's home.
    func openSpotify(uri: String? = nil) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        open(SpotifyLink.openURLs(forURI: uri), failure: "Couldn't open Spotify")
    }

    /// Starts Spotify on this iPhone, plays the last song there, and returns to Cabin Dash by itself. Spotify asks once for permission.
    func startSpotifyHere() {
        guard !spotify.clientID.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        library.startSpotifyHere()
    }

    /// A link that opened Cabin Dash. The only one expected is Spotify's answer after it was started on this iPhone.
    func handleIncoming(_ url: URL) {
        spotify.handleIncoming(url)
    }

    func navigate(to place: Place) {
        guard place.hasAddress else {
            toast.show("Add an address for \(place.name)", actionTitle: "Settings") { [weak self] in
                self?.go(.settings)
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let installedApp = prefs.navApp.scheme.map { canOpen(scheme: $0) } ?? false
        guard let url = prefs.navApp.directionsURL(to: place.address, appInstalled: installedApp) else { return }
        open([url], failure: "Couldn't start directions")
    }

    /// Hands the route to the chosen navigation app (Google Maps by default is a setting), already pointed at the destination.
    func navigate(toLatitude latitude: Double, longitude: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let installedApp = prefs.navApp.scheme.map { canOpen(scheme: $0) } ?? false
        guard let url = prefs.navApp.directionsURL(toLatitude: latitude, longitude: longitude, appInstalled: installedApp) else { return }
        open([url], failure: "Couldn't start directions")
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        open([url], failure: "Couldn't open Settings")
    }

    /// Tries each URL in turn and stops at the first one iOS accepts.
    private func open(_ urls: [URL], failure: String) {
        Task {
            for url in urls {
                if await UIApplication.shared.open(url) { return }
                log.info("Could not open \(url.absoluteString, privacy: .public)")
            }
            self.toast.show(failure)
        }
    }

    // MARK: Saving

    func savePreferences() {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: Self.prefsKey)
    }
}
