import SwiftUI
import CabinCore

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var confirmReset = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
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
                } header: {
                    Text("Driving")
                } footer: {
                    Text("Tapping a place opens directions in this maps app. Google Maps and Waze use their website if they aren't installed.")
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
                    Text("Tap a place on the Apps screen to start directions. Addresses stay on this iPhone.")
                }

                Section {
                    LabeledContent("Version", value: version)
                } header: {
                    Text("About")
                } footer: {
                    Text("Cabin Dash is not CarPlay. It's a dashboard that runs on the iPhone's own screen, so it works in any car.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                PickerSheet()
                    .preferredColorScheme(model.prefs.theme.colorScheme)
            }
            .confirmationDialog("Reset apps?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset apps", role: .destructive) { model.resetApps() }
            } message: {
                Text("This clears the apps you added, the ones you hid, and your recent apps. Places and settings stay.")
            }
        }
        .presentationDragIndicator(.visible)
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
