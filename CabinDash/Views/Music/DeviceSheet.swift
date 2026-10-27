import CabinCore
import SwiftUI

/// The devices Spotify can play on. Tapping one moves playback there. Pull down to look again.
struct DeviceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

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
    }

    @ViewBuilder
    private func list(_ devices: [SpotifyDevice], library: SpotifyLibraryModel) -> some View {
        List {
            if devices.isEmpty {
                Text("No devices found. Open the Spotify app once, then pull to refresh.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            ForEach(devices) { device in
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
