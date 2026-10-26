import SwiftUI
import CabinCore

/// A wide band that sweeps across the screen from left to right, with a bend in the middle.
private struct Ribbon: Shape {
    /// Where the top edge starts on the left and ends on the right, as a fraction of the height.
    var left: CGFloat
    var right: CGFloat
    /// How thick the band is, as a fraction of the height.
    var thickness: CGFloat
    /// How hard the middle bends, as a fraction of the height. Negative bends the other way.
    var bend: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let start = -width * 0.1
        let end = width * 1.1

        var path = Path()
        path.move(to: CGPoint(x: start, y: height * left))
        path.addCurve(
            to: CGPoint(x: end, y: height * right),
            control1: CGPoint(x: width * 0.30, y: height * (left + bend)),
            control2: CGPoint(x: width * 0.70, y: height * (right - bend))
        )
        path.addLine(to: CGPoint(x: end, y: height * (right + thickness)))
        path.addCurve(
            to: CGPoint(x: start, y: height * (left + thickness)),
            control1: CGPoint(x: width * 0.70, y: height * (right - bend + thickness * 1.3)),
            control2: CGPoint(x: width * 0.30, y: height * (left + bend + thickness * 0.7))
        )
        path.closeSubpath()
        return path
    }
}

/// The backdrop: a dark navy (or a pale sand by day) with three soft ribbons sweeping across it,
/// in the manner of the CarPlay wallpapers. The wallpaper setting tints the ribbons.
struct RibbonWallpaper: View {
    let wallpaper: Wallpaper
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: baseColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ribbon(0, left: 0.10, right: -0.12, thickness: 0.62, bend: 0.30)
            ribbon(1, left: 0.55, right: 0.12, thickness: 0.50, bend: 0.22)
            ribbon(2, left: 1.05, right: 0.52, thickness: 0.58, bend: 0.18)
        }
        .animation(.easeInOut(duration: 0.4), value: wallpaper)
        .accessibilityHidden(true)
    }

    private func ribbon(_ index: Int, left: CGFloat, right: CGFloat, thickness: CGFloat, bend: CGFloat) -> some View {
        let shape = Ribbon(left: left, right: right, thickness: thickness, bend: bend)
        let tint = tone(index)
        return shape
            .fill(
                LinearGradient(
                    colors: [tint.opacity(dark ? 0.50 : 0.34), tint.opacity(dark ? 0.06 : 0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(dark ? 0.34 : 0.65), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            )
    }

    private var baseColors: [Color] {
        let hues = wallpaper.hues
        let strength = wallpaper.saturation
        if dark {
            return [
                Color(hue: hues[2] / 360, saturation: strength * 0.62, brightness: 0.26),
                Color(hue: hues[0] / 360, saturation: strength * 0.70, brightness: 0.12)
            ]
        }
        return [
            Color(hue: hues[1] / 360, saturation: strength * 0.22, brightness: 0.93),
            Color(hue: hues[2] / 360, saturation: strength * 0.14, brightness: 0.74)
        ]
    }

    private func tone(_ index: Int) -> Color {
        Color(
            hue: wallpaper.hues[index] / 360,
            saturation: wallpaper.saturation * (dark ? 0.55 : 0.40),
            brightness: dark ? 0.95 : 0.80
        )
    }
}
