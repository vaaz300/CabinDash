import SwiftUI
import UIKit
import CabinCore

/// Colours used across the app. Each pair is (day, night) and follows the Day / Night / Auto setting.
enum Theme {
    static let accent = Color(light: 0xC93400, dark: 0xFF9F0A)
    static let good = Color(light: 0x248A3D, dark: 0x30D158)
    static let bad = Color(light: 0xD70015, dark: 0xFF453A)
    static let base = Color(light: 0xEEF0F6, dark: 0x05060B)
}

extension Color {
    /// A colour that switches between two hex values with the light / dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension ThemeChoice {
    /// nil means "follow the iPhone".
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .day: return .light
        case .night: return .dark
        }
    }
}

extension AppCategory {
    var tint: Color {
        switch self {
        case .navigation: return Color(hex: 0x1F9D55)
        case .audio: return Color(hex: 0xFF375F)
        case .talk: return Color(hex: 0x8A4FD6)
        case .messages: return Color(hex: 0x0A84FF)
        case .charging: return Color(hex: 0xD99A00)
        case .more: return Color(hex: 0x5E5CE6)
        }
    }
}

/// Frosted card used for tiles, chips and the dock.
struct GlassBackground: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

extension View {
    func glass(radius: CGFloat = 22) -> some View {
        modifier(GlassBackground(radius: radius))
    }
}

/// Quick, small press response for every tappable tile.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
