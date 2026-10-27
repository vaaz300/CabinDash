import SwiftUI
import CabinCore

/// Settings as a screen of its own, reached from the gear at the bottom of the dock.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    @State private var showPicker = false
    @State private var confirmReset = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var spotifyFooter: String {
        if model.spotify.phase == .notConfigured {
            return "This copy of Cabin Dash was built without a Spotify Client ID, so the Music screen can't connect. See docs/SPOTIFY-SETUP.md in the repository."
        }
        if model.spotify.phase == .needsReconnect {
            return "Cabin Dash now browses your playlists and likes songs, which needs a few more permissions. You only do this once."
        }
        return "Needs a Spotify Premium account. Cabin Dash shows what the Spotify app is playing and sends play, pause and skip. Spotify keeps playing in its own app."
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Picker("Speed", selection: $model.prefs.units) {
                    ForEach(Units.allCases, id: \.self) { units in
                        Text(units.speedLabel).tag(units)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Directions with", selection: $model.prefs.navApp) {
                    ForEach(NavApp.allCases, id: \.self) { app in
                        Text(app.title).tag(app)
                    }
                }
                Toggle("Keep screen on", isOn: $model.prefs.keepAwake)
                Toggle("Passenger mode", isOn: $model.prefs.passengerMode)
            } header: {
                Text("Driving")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The Map screen plans routes with Apple Maps. \u{201C}Open in\u{2026}\u{201D} hands the trip to this app, which does the real turn-by-turn. Google Maps and Waze use their website if they aren't installed.")
                    Text("Cabin Dash turns off typing, such as music search, while you are moving faster than about 8 km/h. Turn this on if someone else is using the screen.")
                }
            }

            Section {
                LabeledContent("Status", value: model.spotify.statusText)
                switch model.spotify.phase {
                case .notConfigured:
                    EmptyView()
                case .signedOut:
                    Button("Connect Spotify") {
                        Task { await self.model.spotify.signIn() }
                    }
                case .needsReconnect:
                    Button("Connect Spotify again") {
                        Task { await self.model.spotify.signIn() }
                    }
                case .signingIn:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Waiting for Spotify\u{2026}")
                            .foregroundStyle(.secondary)
                    }
                case .signedIn:
                    Button("Disconnect Spotify", role: .destructive) {
                        model.spotify.signOut()
                    }
                }
            } header: {
                Text("Spotify")
            } footer: {
                Text(spotifyFooter)
            }

            Section {
                Picker("Theme", selection: $model.prefs.theme) {
                    ForEach(ThemeChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                WallpaperChooser()
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Show Other apps in the dock", isOn: $model.prefs.showOtherApps)
            } header: {
                Text("Other apps")
            } footer: {
                Text("Adds an Apps button that lists apps installed on this iPhone. Opening one leaves Cabin Dash.")
            }

            if model.prefs.showOtherApps {
                Section {
                    Toggle("Show installed apps automatically", isOn: $model.prefs.autoDetect)
                    Button("Add apps\u{2026}") { showPicker = true }
                    Button("Refresh icons") {
                        Task { await self.model.refreshIcons() }
                    }
                    Button("Reset apps", role: .destructive) { confirmReset = true }
                } header: {
                    Text("Apps")
                } footer: {
                    Text("Cabin Dash finds apps by asking iOS whether their link is registered. It can only do that for apps on its list. Others can be added by hand.")
                }
            }

            Section {
                ForEach($model.prefs.places) { $place in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: place.kind.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            TextField("Name", text: $place.name)
                        }
                        TextField("Address", text: $place.address, axis: .vertical)
                            .textContentType(.fullStreetAddress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 30)
                    }
                }
                .onDelete { offsets in
                    model.prefs.places.remove(atOffsets: offsets)
                }
                Button {
                    model.prefs.places.append(Place(name: "New place"))
                } label: {
                    Label("Add place", systemImage: "plus")
                }
            } header: {
                Text("Places")
            } footer: {
                Text("Saved places appear on the Map screen for one-tap routes. Planning a route sends the address to Apple Maps.")
            }

            Section {
                LabeledContent("Version", value: version)
            } header: {
                Text("About")
            } footer: {
                Text("Cabin Dash is not CarPlay. It's a self-contained driving app that runs on the iPhone's own screen, so it works in any car. Music is controlled through Spotify, which keeps playing in its own app.")
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.leading, CarLayout.railReserve)
        .padding(.trailing, CarLayout.edge)
        .padding(.vertical, CarLayout.edge)
        .sheet(isPresented: $showPicker) {
            PickerSheet()
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
        .confirmationDialog("Reset apps?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset apps", role: .destructive) { model.resetApps() }
        } message: {
            Text("This clears the apps you added and the ones you hid. Places and settings stay.")
        }
    }
}

private struct WallpaperChooser: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(Wallpaper.allCases, id: \.self) { wallpaper in
                    swatch(wallpaper)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    private func swatch(_ wallpaper: Wallpaper) -> some View {
        let selected = model.prefs.wallpaper == wallpaper
        let colors = wallpaper.hues.map { hue in
            Color(hue: hue / 360, saturation: wallpaper.saturation * 0.85, brightness: 0.95)
        }
        return Button {
            model.prefs.wallpaper = wallpaper
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Circle().strokeBorder(
                            selected ? Theme.accent : Color.primary.opacity(0.15),
                            lineWidth: selected ? 3 : 1
                        )
                    )
                Text(wallpaper.title)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(wallpaper.title) wallpaper")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
