import SwiftUI
import UIKit
import CabinCore

/// The icon of one of Cabin Dash's own screens, in the dock and on the Home screen.
/// Music shows Spotify's own icon once it is in the asset catalogue (scripts/add_spotify_icon.py).
struct FeatureIcon: View {
    let feature: Feature
    let size: CGFloat

    private static let spotifyIcon = UIImage(named: "SpotifyIconGreen")

    var body: some View {
        if feature == .music, let icon = Self.spotifyIcon {
            SpotifyTile(icon: icon, size: size)
        } else {
            SymbolTile(symbol: feature.symbol, tone: feature.tone, size: size)
        }
    }
}

/// Spotify's green icon on black. Spotify's guidelines allow the green icon only on black or white, ask for clear space
/// around it of half its height, and say it must not be changed: so the icon is half the tile, shown exactly as supplied.
private struct SpotifyTile: View {
    let icon: UIImage
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        ZStack {
            Color.black
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75
            )
        )
        .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }
}
