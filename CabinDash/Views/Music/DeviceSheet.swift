import CabinCore
import SwiftUI

/// The devices Spotify can play on. Tapping one moves playback there. Pull down to look again.
/// Nothing here is chosen for the person: playback only moves when they tap a device.
struct DeviceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let library = model.library
        NavigationStack {
            Group {
                switch library.devices {
                case .idle, .loading:
                    PaneLoading(text: "Looking for devices\u{2026}")
                case .failed(let failure):
                    PaneNotice(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Devices could not be loaded",
                        detail: failure.message,
                        retry: { library.loadDevices() }
                    )
                case .loaded(let devices):
                    list(devices, library: library)
                }
            }
            .navigationTitle("Play on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { library.loadDevices() }
        // Coming back from the Spotify app: it has probably just announced itself, so look again now and once more shortly.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            library.loadDevices()
            Task {
                try? await Task.sleep(for: .seconds(2))
                await library.reloadDevices()
            }
        }
    }

    @ViewBuilder
    private func list(_ devices: [SpotifyDevice], library: SpotifyLibraryModel) -> some View {
        List {
            // Spotify lists a phone only while its Spotify app is running. When this iPhone is missing, this row is how to
            // wake it: it opens Spotify, and the phone shows up in the list below when the person comes back.
            if !SpotifyDevices.hasPhone(in: devices) {
                Section {
                    Button {
                        model.openSpotify()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("This iPhone")
                                    .font(.system(size: 17, weight: .semibold))
                                Text(SpotifyLink.label + " so it can play here")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                } footer: {
                    Text("Spotify lists a device only while its app is on. After opening Spotify, come back here and This iPhone appears in the list. Tap it to play on it.")
                }
            }

            Section {
                if devices.isEmpty {
                    Text("No devices are on right now.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                ForEach(SpotifyDevices.phonesFirst(devices)) { device in
                    Button {
                        Task {
                            await library.transfer(to: device)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: Self.symbol(forType: device.type))
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 32)
                            Text(device.name)
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if device.isActive {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityLabel("Playing here")
                            }
                        }
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    // A restricted device (some speakers) does not accept playback from other apps.
                    .disabled(device.isRestricted)
                    .opacity(device.isRestricted ? 0.4 : 1)
                }
            }
        }
        .refreshable { await library.reloadDevices() }
    }

    /// Spotify's device type names ("Computer", "Smartphone", "Speaker"...) mapped to symbols.
    static func symbol(forType type: String) -> String {
        switch type {
        case "Computer": return "laptopcomputer"
        case "Tablet": return "ipad"
        case "Smartphone": return "iphone"
        case "Speaker", "CastAudio": return "hifispeaker.fill"
        case "AVR": return "hifispeaker.2.fill"
        case "TV", "STB", "CastVideo": return "tv"
        case "GameConsole": return "gamecontroller.fill"
        case "Automobile": return "car.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}
