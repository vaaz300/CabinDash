import CabinCore
import SwiftUI

/// Music inside Cabin Dash: a row of sections along the top (Now Playing, Playlists, Liked, Search, Queue) and the section below it.
/// Spotify still plays the sound in its own app. This screen browses the library and steers playback.
struct MusicScreen: View {
    @Environment(AppModel.self) private var model

    /// The route banner floats over the top right of every screen but the Map. Leave room for it.
    private var routeBannerShowing: Bool {
        !Strips.visible(on: .music, musicActive: false, routeGuiding: model.route.phase == .guiding).isEmpty
    }

    var body: some View {
        @Bindable var library = model.library
        let spotify = model.spotify
        Group {
            if spotify.phase == .signedIn {
                VStack(spacing: 10) {
                    SectionBar()
                    if let problem = spotify.problem {
                        HStack(spacing: 10) {
                            Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // "No device ready" is fixed by choosing one, so the way to do that is right here.
                            if problem == .noActiveDevice {
                                PillButton(title: "Devices", symbol: "speaker.wave.2.fill") {
                                    model.library.devicePickerPresented = true
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glass(radius: 14)
                    }
                    SectionContent()
                }
            } else {
                // Not connected yet: the connect panel, not the sections.
                StatePanel(spotify: spotify)
            }
        }
        .padding(.leading, CarLayout.railReserve)
        .padding(.trailing, CarLayout.edge)
        .padding(.bottom, CarLayout.edge)
        .padding(.top, routeBannerShowing ? 74 : CarLayout.edge)
        .sheet(isPresented: $library.devicePickerPresented) {
            DeviceSheet()
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
    }
}

private struct SectionContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.library.section {
        case .nowPlaying:
            NowPlayingPane()
        case .playlists:
            PlaylistsPane()
        case .liked:
            LikedPane()
        case .search:
            SearchPane()
        case .queue:
            QueuePane()
        }
    }
}

/// The section pills, then which device is playing and the link back to Spotify.
private struct SectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        HStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MusicSection.allCases, id: \.self) { section in
                        SectionPill(section: section, selected: library.section == section) {
                            library.section = section
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            // Which device is playing. Tapping it opens the list, so it is also how to pick one when none is ready.
            let device = model.spotify.nowPlaying?.deviceName ?? ""
            Button {
                library.devicePickerPresented = true
            } label: {
                Label(device.isEmpty ? "Choose device" : "Playing on \(device)", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: 220, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))
            .accessibilityLabel(device.isEmpty ? "Choose device" : "Playing on \(device). Choose another device")
            SpotifyAttribution(uri: model.spotify.nowPlaying?.uri)
        }
    }
}

private struct SectionPill: View {
    let section: MusicSection
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? onAccent : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(selected ? Theme.accent : Color.primary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
