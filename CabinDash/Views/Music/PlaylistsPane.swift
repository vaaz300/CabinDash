import CabinCore
import SwiftUI

/// The person's playlists, and the page of one playlist once they open it.
struct PlaylistsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        Group {
            if let playlist = library.openPlaylist {
                PlaylistPage(playlist: playlist)
            } else {
                PlaylistList()
            }
        }
        .onAppear { library.loadPlaylists() }
    }
}

private struct PlaylistList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        switch library.playlists {
        case .idle, .loading:
            PaneLoading(text: "Loading your playlists\u{2026}")
        case .failed(let failure):
            PaneNotice(
                symbol: "exclamationmark.triangle.fill",
                title: "Playlists could not be loaded",
                detail: failure.message,
                retry: { library.loadPlaylists(force: true) }
            )
        case .loaded(let playlists):
            if playlists.isEmpty {
                PaneNotice(
                    symbol: "music.note.list",
                    title: "No playlists yet",
                    detail: "Playlists you create or follow in Spotify appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(playlists) { playlist in
                            Button {
                                library.open(playlist)
                            } label: {
                                PlaylistRow(playlist: playlist)
                            }
                            .buttonStyle(PressScaleStyle(scale: 0.98))
                        }
                    }
                }
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: SpotifyPlaylist

    private var detail: String {
        var parts: [String] = []
        if !playlist.ownerName.isEmpty { parts.append(playlist.ownerName) }
        if let count = playlist.trackCount { parts.append(count == 1 ? "1 song" : "\(count) songs") }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: playlist.artworkURL, side: 52, symbol: "music.note.list")
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One playlist: Play and Shuffle, then its songs when Spotify lets Cabin Dash list them.
private struct PlaylistPage: View {
    let playlist: SpotifyPlaylist
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        VStack(alignment: .leading, spacing: 8) {
            header(library)
            content(library)
        }
    }

    private func header(_ library: SpotifyLibraryModel) -> some View {
        HStack(spacing: 12) {
            Button {
                library.closePlaylist()
            } label: {
                Label("Playlists", systemImage: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color.primary.opacity(0.10), in: Capsule())
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))

            Cover(url: playlist.artworkURL, side: 44, symbol: "music.note.list")
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                if !playlist.ownerName.isEmpty {
                    Text(playlist.ownerName)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            PillButton(title: "Play", symbol: "play.fill", filled: true) {
                Task { await library.play(.context(uri: playlist.uri, startAtURI: nil)) }
            }
            PillButton(title: "Shuffle", symbol: "shuffle") {
                Task { await library.shufflePlay(.context(uri: playlist.uri, startAtURI: nil)) }
            }
        }
    }

    @ViewBuilder
    private func content(_ library: SpotifyLibraryModel) -> some View {
        if !library.profileChecked && !playlist.isCollaborative {
            PaneLoading(text: "Opening\u{2026}")
        } else if !playlist.canListItems(profileID: library.profileID) {
            Text("Spotify only lets Cabin Dash list tracks in playlists you own. You can still play it.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch library.playlistTracks {
            case .idle, .loading:
                PaneLoading(text: "Loading tracks\u{2026}")
            case .failed(let failure):
                PaneNotice(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Tracks could not be loaded",
                    detail: failure.message,
                    retry: { library.retryPlaylistTracks() }
                )
            case .loaded(let tracks):
                if tracks.isEmpty {
                    PaneNotice(symbol: "music.note", title: "This playlist is empty")
                } else {
                    TrackList(
                        tracks: tracks,
                        onSelect: { _, track in
                            Task { await library.play(.context(uri: playlist.uri, startAtURI: track.uri)) }
                        },
                        onLastAppear: { library.loadMorePlaylistTracks() }
                    )
                }
            }
        }
    }
}
