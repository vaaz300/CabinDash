import CabinCore
import Foundation
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "app.cabindash", category: "app")

enum DashTab: String {
    case apps
    case drive
}

/// Everything the screens share: the user's choices, which apps are installed, and what happens on a tap.
@MainActor @Observable
final class AppModel {
    var prefs: Preferences
    var tab: DashTab = .apps
    var pickerPresented = false
    var settingsPresented = false
    /// Ids of catalog apps whose URL scheme this iPhone answered "yes" to.
    private(set) var installed: Set<String> = []

    let icons: IconStore
    let toast = ToastCenter()

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
    }

    // MARK: Shelf

    var shelf: [AppEntry] {
        Shelf.compose(installed: installed, preferences: prefs)
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
        await icons.sync(shelf)
    }

    /// Pull to refresh: look for installed apps again, then fetch any missing icons.
    func reloadAll() async {
        refreshInstalled()
        await syncIcons()
    }

    func refreshIcons() async {
        await icons.reset()
        await icons.sync(shelf)
    }

    // MARK: Opening things

    func launch(_ app: AppEntry) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        prefs.noteLaunch(app)
        open(app.launchSequence, failure: "Couldn't open \(app.name)")
    }

    func navigate(to place: Place) {
        guard place.hasAddress else {
            toast.show("Add an address for \(place.name)", actionTitle: "Settings") { [weak self] in
                self?.settingsPresented = true
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let installedApp = prefs.navApp.scheme.map { canOpen(scheme: $0) } ?? false
        guard let url = prefs.navApp.directionsURL(to: place.address, appInstalled: installedApp) else { return }
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
