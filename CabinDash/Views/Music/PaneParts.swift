import CabinCore
import SwiftUI
import UIKit

/// A small picture from Spotify, such as an album or a playlist cover. It is shown as Spotify sends it:
/// rounded corners, nothing drawn over it. Without a picture, a plain tile with a symbol stands in.
struct Cover: View {
    let url: URL?
    let side: CGFloat
    var radius: CGFloat = 4
    var symbol = "music.note"

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Color.primary.opacity(0.10)
                    Image(systemName: symbol)
                        .font(.system(size: side * 0.4, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The text colour that reads on the app's accent colour in both Day and Night.
let onAccent = Color(light: 0xFFFFFF, dark: 0x000000)

/// A rounded button with a symbol, at least 44 pt tall.
struct PillButton: View {
    let title: String
    let symbol: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? onAccent : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(filled ? Theme.accent : Color.primary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
    }
}

/// A centred message for a pane: nothing here yet, or something went wrong, with an optional Try again.
struct PaneNotice: View {
    let symbol: String
    let title: String
    var detail: String?
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            if let retry {
                PillButton(title: "Try again", symbol: "arrow.clockwise", action: retry)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A spinner with one line under it, centred in its pane.
struct PaneLoading: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
