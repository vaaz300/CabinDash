import CabinCore
import SwiftUI

/// Music inside Cabin Dash: a row of sections along the top (Now Playing, Playlists, Liked, Search, Queue) and the section below it.
/// Spotify still plays the sound in its own app. This screen browses the library and steers playback.
struct MusicScreen: View {
    @Environment(AppModel.self) private var model

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
        // The background behind Music is darkened (RootView), so its text and Spotify's white icons are drawn for dark,
        // whatever the theme. The device list keeps the theme: it is presented from outside this.
        .environment(\.colorScheme, .dark)
        .padding(.leading, CarLayout.railReserve)
        .padding(.trailing, CarLayout.edge)
        .padding(.bottom, CarLayout.edge)
        // The route banner floats over the top right of every screen but the Map. Start below it.
        .padding(.top, StripClearance.top(for: model.visibleStrips))
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

/// Two rows. The sections get the whole width of the first, so none of them is squeezed or cut off.
/// Which device is playing and the link back to Spotify sit on the second.
private struct SectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            SectionPills()
            HStack(spacing: 12) {
                DeviceChip()
                Spacer(minLength: 12)
                SpotifyAttribution(uri: model.spotify.nowPlaying?.uri)
                    .layoutPriority(1)
            }
        }
    }
}

/// The five sections, spread evenly across the row. If a narrow phone cannot fit them at full size they scroll instead of shrinking.
private struct SectionPills: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(MusicSection.allCases, id: \.self) { section in
                    SectionPill(section: section, selected: library.section == section, expands: true) {
                        library.section = section
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MusicSection.allCases, id: \.self) { section in
                        SectionPill(section: section, selected: library.section == section, expands: false) {
                            library.section = section
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Which device is playing, or where Play will go. Tapping it opens the list, to pick another device.
private struct DeviceChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let line = SpotifyDevices.lineText(
            playingOn: model.spotify.nowPlaying?.deviceName, chosenName: model.spotify.chosenDeviceName
        )
        Button {
            model.library.devicePickerPresented = true
        } label: {
            Label(line, systemImage: "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel(line + ". Choose another device")
    }
}

private struct SectionPill: View {
    let section: MusicSection
    let selected: Bool
    /// True in the evenly spread row, where each pill takes an equal share of the width.
    let expands: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.symbol)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? onAccent : Color.primary)
                .padding(.horizontal, 18)
                .frame(maxWidth: expands ? CGFloat.infinity : nil, minHeight: 46)
                .background(selected ? Theme.accent : Color.primary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
