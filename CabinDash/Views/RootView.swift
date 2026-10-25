import SwiftUI
import UIKit

/// Wallpaper, the two screens, the dock and the sheets. Switches to a side dock when the phone is turned.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model

        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height * 1.25
            ZStack {
                WallpaperView(wallpaper: model.prefs.wallpaper)
                    .ignoresSafeArea()
                if landscape {
                    HStack(spacing: 12) {
                        DockBar(landscape: true)
                        screens(landscape: true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 10) {
                        screens(landscape: false)
                        DockBar(landscape: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
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
        }
        .task(id: model.shelf.map(\.id)) {
            await self.model.syncIcons()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.refreshInstalled()
                location.start()
                UIApplication.shared.isIdleTimerDisabled = model.prefs.keepAwake
            case .inactive:
                location.saveTrip()
            case .background:
                location.stop()
            @unknown default:
                break
            }
        }
        .onChange(of: model.prefs) { _, _ in
            model.savePreferences()
        }
        .onChange(of: model.prefs.keepAwake, initial: true) { _, keepAwake in
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    }

    /// Both screens stay alive so the app grid keeps its scroll position while Drive is showing.
    private func screens(landscape: Bool) -> some View {
        ZStack {
            AppsView(landscape: landscape)
                .opacity(model.tab == .apps ? 1 : 0)
                .allowsHitTesting(model.tab == .apps)
                .accessibilityHidden(model.tab != .apps)
            DriveView(landscape: landscape)
                .opacity(model.tab == .drive ? 1 : 0)
                .allowsHitTesting(model.tab == .drive)
                .accessibilityHidden(model.tab != .drive)
        }
        .animation(.easeOut(duration: 0.2), value: model.tab)
        .overlay(alignment: .bottom) {
            ToastOverlay()
                .padding(.bottom, 8)
        }
    }
}
