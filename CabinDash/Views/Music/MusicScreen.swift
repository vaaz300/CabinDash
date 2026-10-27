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
        let spotify = model.spotify
        Group {
            if spotify.phase == .signedIn {
                VStack(spacing: 10) {
                    SectionBar()
                    if let problem = spotify.problem {
                        Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            PaneNotice(symbol: "magnifyingglass", title: "Search is coming next")
        case .queue:
            PaneNotice(symbol: "list.bullet", title: "The queue is coming next")
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

            if let device = model.spotify.nowPlaying?.deviceName, !device.isEmpty {
                Label("Playing on \(device)", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
            }
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
