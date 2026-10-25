import SwiftUI
import CabinCore

/// Three soft trails of light on a dark (or pale) base, like the CarPlay wallpapers.
struct WallpaperView: View {
    let wallpaper: Wallpaper
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let reach = max(width, height)
            ZStack {
                Theme.base
                trail(0, reach: reach, thickness: 0.22)
                    .position(x: width * 0.30, y: height * 0.18)
                trail(1, reach: reach, thickness: 0.16)
                    .position(x: width * 0.80, y: height * 0.55)
                trail(2, reach: reach, thickness: 0.20)
                    .position(x: width * 0.25, y: height * 0.93)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.5), value: wallpaper)
        .accessibilityHidden(true)
    }

    private func trail(_ index: Int, reach: CGFloat, thickness: CGFloat) -> some View {
        Capsule()
            .fill(tone(index))
            .frame(width: reach * 1.25, height: reach * thickness)
            .rotationEffect(.degrees(-32))
            .blur(radius: reach * 0.07)
    }

    private func tone(_ index: Int) -> Color {
        let dark = scheme == .dark
        return Color(
            hue: wallpaper.hues[index] / 360,
            saturation: wallpaper.saturation * (dark ? 0.9 : 0.75),
            brightness: dark ? 0.95 : 0.98,
            opacity: dark ? 0.6 : 0.42
        )
    }
}
