import CabinCore
import SwiftUI
import UIKit

/// Search Spotify for songs, albums and playlists. Typing is switched off while the car is moving
/// (unless Passenger mode is on), but results already on screen can still be tapped.
struct SearchPane: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var library = model.library
        let locked = model.typingLocked

        VStack(spacing: 8) {
            field($library.searchText, locked: locked)
            if locked {
                Label(
                    "Search is off while you're moving. Passenger mode in Settings turns this lock off.",
                    systemImage: "lock.fill"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
            }
            results(model.library)
        }
        .onChange(of: model.library.searchText) { _, _ in
            model.library.searchTextChanged()
        }
        .onChange(of: locked) { _, nowLocked in
            if nowLocked { focused = false }
        }
    }

    private func field(_ text: Binding<String>, locked: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search songs, albums and playlists", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .disabled(locked)
                .onSubmit { focused = false }
            if !text.wrappedValue.isEmpty && !locked {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 17, weight: .regular))
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 44)
        .background(Color.primary.opacity(0.10), in: Capsule())
        .opacity(locked ? 0.5 : 1)
    }

    @ViewBuilder
    private func results(_ library: SpotifyLibraryModel) -> some View {
        let query = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            PaneNotice(
                symbol: "magnifyingglass",
                title: "Search Spotify",
                detail: "Songs, albums and playlists. Tap a result to play it."
            )
        } else {
            switch library.search {
            case .idle, .loading:
                PaneLoading(text: "Searching\u{2026}")
            case .failed(let failure):
                PaneNotice(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Search could not finish",
                    detail: failure.message,
                    retry: { Task { await library.runSearch() } }
                )
            case .loaded(let found):
                if found.tracks.isEmpty && found.albums.isEmpty && found.playlists.isEmpty {
                    PaneNotice(symbol: "questionmark.circle", title: "Nothing found for \u{201C}\(query)\u{201D}")
                } else {
                    SearchResults(found: found)
                }
            }
        }
    }
}

private struct SearchResults: View {
    let found: SpotifySearchResults
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        ScrollView {
            LazyVStack(spacing: 2) {
                if !found.tracks.isEmpty {
                    SectionHeader(title: "Songs")
                    ForEach(Array(found.tracks.enumerated()), id: \.offset) { _, track in
                        HStack(spacing: 0) {
                            Button {
                                Task { await library.play(track.playTarget) }
                            } label: {
                                TrackRow(track: track)
                            }
                            .buttonStyle(PressScaleStyle(scale: 0.98))
                            .disabled(!track.isPlayable)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                library.addToQueue(track)
                            } label: {
                                Image(systemName: "text.badge.plus")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 52, height: 52)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressScaleStyle(scale: 0.88))
                            .disabled(!track.isPlayable)
                            .opacity(track.isPlayable ? 1 : 0.3)
                            .accessibilityLabel("Add \(track.name) to the queue")
                        }
                    }
                }
                if !found.albums.isEmpty {
                    SectionHeader(title: "Albums")
                    ForEach(Array(found.albums.enumerated()), id: \.offset) { _, album in
                        Button {
                            Task { await library.play(.context(uri: album.uri, startAtURI: nil)) }
                        } label: {
                            ResultRow(
                                url: album.artworkURL, symbol: "square.stack", title: album.name,
                                detail: album.artist, chevron: false
                            )
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                    }
                }
                if !found.playlists.isEmpty {
                    SectionHeader(title: "Playlists")
                    ForEach(Array(found.playlists.enumerated()), id: \.offset) { _, playlist in
                        Button {
                            // Opens the playlist's own page under Playlists, where it can be played or shuffled.
                            library.open(playlist)
                            library.section = .playlists
                        } label: {
                            ResultRow(
                                url: playlist.artworkURL, symbol: "music.note.list", title: playlist.name,
                                detail: playlist.ownerName, chevron: true
                            )
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// An album or playlist in search results.
private struct ResultRow: View {
    let url: URL?
    let symbol: String
    let title: String
    let detail: String
    let chevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: url, side: 40, symbol: symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
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
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
