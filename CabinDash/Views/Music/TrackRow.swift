import CabinCore
import SwiftUI

/// One song or episode in a list: a small cover, the title, the artists and the length.
/// A row Spotify cannot play (a local file, an unavailable song) is dimmed.
struct TrackRow: View {
    let track: SpotifyTrack

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: track.artworkURL, side: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                if !track.subtitle.isEmpty {
                    Text(track.subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if track.duration > 0 {
                Text(Self.clock(track.duration))
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .opacity(track.isPlayable ? 1 : 0.4)
        .accessibilityElement(children: .combine)
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A scrolling list of songs. The same song can appear twice in a playlist, so rows are told apart by position.
struct TrackList: View {
    let tracks: [SpotifyTrack]
    /// Called with the row's position and the song when a playable row is tapped.
    let onSelect: (Int, SpotifyTrack) -> Void
    /// Called when the last row appears, so a long list can load its next page.
    var onLastAppear: () -> Void = {}

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button {
                        onSelect(index, track)
                    } label: {
                        TrackRow(track: track)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
                    .disabled(!track.isPlayable)
                    .onAppear {
                        if index == tracks.count - 1 { onLastAppear() }
                    }
                }
            }
        }
    }
}
