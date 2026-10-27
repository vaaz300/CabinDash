import CabinCore
import SwiftUI
import UIKit

/// Says whose music this is and links back to the Spotify app, using Spotify's required wording.
///
/// Spotify's guidelines want their own icon or logo, drawn by them and never redrawn. Cabin Dash cannot download it in its
/// build environment, so it is added with `scripts/add_spotify_icon.py` (see docs/SPOTIFY-RULES.md). Until that has been done,
/// the name is written out as plain text and nothing resembling the logo is drawn.
struct SpotifyAttribution: View {
    /// What the link opens: a track, album or playlist, or Spotify's home when nil.
    var uri: String?
    var compact = true
    @Environment(AppModel.self) private var model

    /// Spotify's icon, when it has been added to the asset catalogue.
    private static let icon = UIImage(named: "SpotifyIcon")

    var body: some View {
        HStack(spacing: 8) {
            if let icon = Self.icon {
                // Shown as supplied: never recoloured, cropped or redrawn. 21 pt is the smallest Spotify allows.
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)
                    .accessibilityLabel("Spotify")
            } else {
                Text("Spotify")
                    .font(.system(size: compact ? 14 : 16, weight: .bold))
                    .foregroundStyle(.secondary)
            }
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
