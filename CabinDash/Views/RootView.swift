import SwiftUI
import UIKit
import CabinCore

/// The whole screen: a wallpaper, one of the screens (the home grid, Maps, Now Playing or Drive), the rail down the left edge, and the sheets.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .leading) {
            RibbonWallpaper(wallpaper: model.prefs.wallpaper)
                .ignoresSafeArea()

            // The home grid stays alive underneath, so it is on the same page when you come back to it.
            ZStack {
                HomeGrid()
                    .padding(.leading, CarLayout.railReserve)
                    .padding(.trailing, CarLayout.edge)
                    .opacity(model.screen == nil ? 1 : 0)
                    .allowsHitTesting(model.screen == nil)
                    .accessibilityHidden(model.screen != nil)
                if let screen = model.screen {
                    screenView(screen)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.screen)

            StatusRail()
                .padding(.leading, CarLayout.edge)
                .padding(.vertical, CarLayout.edge)
        }
        .overlay(alignment: .bottom) {
            ToastOverlay()
                .padding(.bottom, 10)
        }
        .sheet(isPresented: $model.pickerPresented) {
            PickerSheet()
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
        .sheet(isPresented: $model.settingsPresented) {
            SettingsSheet()
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
        // `self.model` (the environment value), not the local `@Bindable model` above: these closures are
        // @Sendable, and a local variable should not be captured by one.
        .task {
            await self.model.startUp(location: self.location)
            self.model.spotify.setActive(self.scenePhase == .active)
        }
        .task(id: model.shelf.map(\.id)) {
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
            if let latitude = location.latitude, let longitude = location.longitude {
                model.route.update(latitude: latitude, longitude: longitude)
            }
        }
        .onChange(of: model.screen) { _, screen in
            model.spotify.setFast(screen == .nowPlaying)
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
    private func screenView(_ screen: AppScreen) -> some View {
        switch screen {
        case .maps:
            MapScreen()
        case .nowPlaying:
            NowPlayingScreen()
        case .drive:
            DriveView(landscape: true)
                .padding(.leading, CarLayout.railReserve)
        }
    }

    /// The screen stays on while the setting says so, and always while a route is being followed.
    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = model.prefs.keepAwake || model.route.phase == .guiding
    }
}
