import CabinCore
import SwiftUI

/// The songs the person has liked in Spotify, newest first, loaded a page at a time.
struct LikedPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        Group {
            switch library.liked {
            case .idle, .loading:
                PaneLoading(text: "Loading your liked songs\u{2026}")
            case .failed(let failure):
                PaneNotice(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Liked Songs could not be loaded",
                    detail: failure.message,
                    retry: { library.loadLiked(reset: true) }
                )
            case .loaded(let tracks):
                if tracks.isEmpty {
                    PaneNotice(
                        symbol: "heart",
                        title: "No liked songs yet",
                        detail: "Songs you like in Spotify appear here."
                    )
                } else {
                    TrackList(
                        tracks: tracks,
                        onSelect: { index, _ in
                            // Plays this song and the ones after it. Spotify takes up to 100 songs at once.
                            let target = SpotifyPlayTarget.window(tracks.map(\.uri), startingAt: index)
                            Task { await library.play(target) }
                        },
                        onLastAppear: { library.loadMoreLiked() }
                    )
                }
            }
        }
        .onAppear { library.loadLiked() }
    }
}
