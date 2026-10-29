import SwiftUI
import UIKit
import CabinCore

/// The whole screen: a wallpaper, one of Cabin Dash's screens (Home, Map, Music, Drive, Settings or Apps), the rail down the left edge, and the sheets.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model

        let onMusic = model.router.current == .music
        ZStack(alignment: .leading) {
            RibbonWallpaper(wallpaper: model.prefs.wallpaper)
                .ignoresSafeArea()

            // Behind Music the wallpaper is blurred and darkened, so the music is what stands out. The blur is iOS's own
            // frosted glass (a material, as in Control Center): SwiftUI's blur filter on the drawn wallpaper came out in
            // jagged, stepped bands on the phone.
            Group {
                if onMusic {
                    Rectangle()
                        .fill(.thickMaterial)
                        .overlay(Color.black.opacity(0.35))
                        .environment(\.colorScheme, .dark)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: onMusic)

            ZStack {
                screenView(model.router.current)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.2), value: model.router.current)

            StatusRail()
                .padding(.leading, CarLayout.edge)
                .padding(.vertical, CarLayout.edge)
        }
        // The next turn and the playing song sit along the bottom right, under each screen's content, so the top of
        // every screen stays its own (on Music, the section bar lines up with the top of the rail).
        .overlay(alignment: .bottomTrailing) {
            StripStack()
                .padding(.leading, CarLayout.railReserve)
                .padding(.trailing, CarLayout.edge)
                .padding(.bottom, CarLayout.edge)
        }
        .overlay(alignment: .bottom) {
            // Toasts appear above the strips rather than on top of them.
            ToastOverlay()
                .padding(.bottom, max(10, StripClearance.reserve(for: model.visibleStrips)))
        }
        .sheet(isPresented: $model.pickerPresented) {
            PickerSheet()
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
        // Spotify opens Cabin Dash again with this after "Start Spotify on this iPhone".
        .onOpenURL { url in
            model.handleIncoming(url)
        }
        // `self.model` (the environment value), not the local `@Bindable model` above: these closures are
        // @Sendable, and a local variable should not be captured by one.
        .task {
            await self.model.startUp(location: self.location)
            self.model.spotify.setActive(self.scenePhase == .active)
        }
        .task(id: model.iconTargets.map(\.id)) {
            await self.model.syncIcons()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.refreshInstalled()
                location.start()
                model.spotify.setActive(true)
                applyIdleTimer()
            case .inactive:
                location.saveTrip()
            case .background:
                location.stop()
                model.spotify.setActive(false)
            @unknown default:
                break
            }
        }
        .onChange(of: location.fixCount) { _, _ in
            model.noteMotion(speed: location.hasFix ? location.speed : nil, at: Date().timeIntervalSinceReferenceDate)
            if let latitude = location.latitude, let longitude = location.longitude {
                model.route.update(latitude: latitude, longitude: longitude)
            }
        }
        .onChange(of: model.router.current) { _, current in
            model.spotify.setFast(current == .music)
        }
        // Disconnecting (or Spotify signing the person out) drops the lists read for that account.
        .onChange(of: model.spotify.phase) { _, phase in
            if phase != .signedIn { model.library.reset() }
        }
        .onChange(of: model.prefs.showOtherApps) { _, _ in
            model.reconcileRouter()
        }
        .onChange(of: model.prefs) { _, _ in
            model.savePreferences()
        }
        .onChange(of: model.prefs.keepAwake, initial: true) { _, _ in
            applyIdleTimer()
        }
        .onChange(of: model.route.phase) { _, _ in
            applyIdleTimer()
        }
    }

    @ViewBuilder
    private func screenView(_ feature: Feature) -> some View {
        switch feature {
        case .dashboard:
            DashboardView()
        case .map:
            MapScreen()
        case .music:
            MusicScreen()
        case .drive:
            DriveView(landscape: true)
                .padding(.leading, CarLayout.railReserve)
                .padding(.bottom, StripClearance.reserve(for: model.visibleStrips))
        case .settings:
            SettingsScreen()
        case .apps:
            OtherAppsScreen()
                .padding(.leading, CarLayout.railReserve)
                .padding(.trailing, CarLayout.edge)
                .padding(.bottom, StripClearance.reserve(for: model.visibleStrips))
        }
    }

    /// The screen stays on while the setting says so, and always while a route is being followed.
    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = model.prefs.keepAwake || model.route.phase == .guiding
    }
}
