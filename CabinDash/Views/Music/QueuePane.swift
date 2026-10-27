import CabinCore
import SwiftUI

/// What is playing now and what comes next. Read-only: Spotify's web API can add to the queue but not reorder or remove.
struct QueuePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        Group {
            switch library.queue {
            case .idle, .loading:
                PaneLoading(text: "Loading the queue\u{2026}")
            case .failed(let failure):
                PaneNotice(
                    symbol: "exclamationmark.triangle.fill",
                    title: "The queue could not be loaded",
                    detail: failure.message,
                    retry: { library.loadQueue() }
                )
            case .loaded(let queue):
                if queue.current == nil && queue.upNext.isEmpty {
                    PaneNotice(
                        symbol: "list.bullet",
                        title: "The queue is empty",
                        detail: "Add songs from Search with the plus button."
                    )
                } else {
                    QueueList(queue: queue)
                }
            }
        }
        .onAppear { library.loadQueue() }
        // A new song means a new queue.
        .onChange(of: model.spotify.nowPlaying?.uri) { _, _ in
            library.loadQueue()
        }
    }
}

private struct QueueList: View {
    let queue: SpotifyQueue

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if let current = queue.current {
                    SectionHeader(title: "Now playing")
                    TrackRow(track: current)
                }
                if !queue.upNext.isEmpty {
                    SectionHeader(title: "Up next")
                    // The same song can be queued twice, so rows are told apart by position.
                    ForEach(Array(queue.upNext.enumerated()), id: \.offset) { _, track in
                        TrackRow(track: track)
                    }
                }
            }
        }
    }
}
