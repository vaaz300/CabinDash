import CabinCore
import SwiftUI
import UIKit

/// Says whose music this is and links back to the Spotify app, using Spotify's required wording.
/// Spotify's logo is not bundled yet: until it is, the name is written out as plain text.
struct SpotifyAttribution: View {
    /// What the link opens: a track, album or playlist, or Spotify's home when nil.
    var uri: String?
    var compact = true
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text("Spotify")
                .font(.system(size: compact ? 14 : 16, weight: .bold))
                .foregroundStyle(.secondary)
            Button {
                model.openSpotify(uri: uri)
            } label: {
                Label(SpotifyLink.label, systemImage: "arrow.up.right.square")
                    .font(.system(size: compact ? 14 : 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, compact ? 12 : 22)
                    .frame(minHeight: 44)
                    .background(Color.primary.opacity(0.10), in: Capsule())
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))
        }
    }
}
