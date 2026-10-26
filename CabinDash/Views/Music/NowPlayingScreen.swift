import CabinCore
import SwiftUI
import UIKit

/// What Spotify is playing, with the controls. Spotify itself keeps playing in its own app;
/// this screen reads its state and sends it play, pause, next and previous.
struct NowPlayingScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let spotify = model.spotify
        Group {
            if spotify.phase == .signedIn, let playing = spotify.nowPlaying {
                PlayerView(spotify: spotify, playing: playing)
            } else {
                StatePanel(spotify: spotify)
            }
        }
        .padding(.leading, CarLayout.railReserve)
        .padding(.trailing, CarLayout.edge)
        .padding(.vertical, CarLayout.edge)
    }
}

// MARK: - Player

private struct PlayerView: View {
    let spotify: SpotifyModel
    let playing: NowPlaying

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.height, proxy.size.width * 0.42)
            HStack(spacing: 28) {
                Artwork(url: playing.artworkURL)
                    .frame(width: side, height: side)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(playing.title)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(playing.subtitle)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                    if !playing.album.isEmpty {
                        Text(playing.album)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }

                    ProgressBar(spotify: spotify, duration: playing.duration)
                        .padding(.top, 18)

                    Controls(spotify: spotify, playing: playing.isPlaying)
                        .padding(.top, 14)

                    Spacer(minLength: 0)

                    Footer(spotify: spotify, device: playing.deviceName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct Artwork: View {
    let url: URL?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: 0x1DB954).opacity(0.85), Color(hex: 0x0B3D1E)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityHidden(true)
    }
}

/// Elapsed time, a bar you can tap or drag to jump around, and the time left.
private struct ProgressBar: View {
    let spotify: SpotifyModel
    let duration: Double
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = duration > 0 ? spotify.position(at: context.date) / duration : 0
            let fraction = max(0, min(1, dragFraction ?? live))
            HStack(spacing: 12) {
                Text(Self.clock(fraction * duration))
                    .frame(width: 46, alignment: .trailing)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.18))
                        Capsule()
                            .fill(Color.primary.opacity(0.9))
                            .frame(width: max(6, proxy.size.width * fraction))
                    }
                    .frame(height: dragFraction == nil ? 6 : 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = max(0, min(1, value.location.x / max(1, proxy.size.width)))
                            }
                            .onEnded { value in
                                let target = max(0, min(1, value.location.x / max(1, proxy.size.width)))
                                dragFraction = nil
                                let seconds = target * duration
                                Task { await spotify.seek(toSeconds: seconds) }
                            }
                    )
                }
                .frame(height: 28)
                Text("-" + Self.clock(max(0, duration - fraction * duration)))
                    .frame(width: 52, alignment: .leading)
            }
            .font(.system(size: 14, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct Controls: View {
    let spotify: SpotifyModel
    let playing: Bool

    var body: some View {
        HStack(spacing: 44) {
            Spacer(minLength: 0)
            ControlButton(symbol: "backward.fill", size: 32, label: "Previous") {
                Task { await spotify.skipPrevious() }
            }
            ControlButton(symbol: playing ? "pause.fill" : "play.fill", size: 40, label: playing ? "Pause" : "Play") {
                Task { await spotify.togglePlayPause() }
            }
            ControlButton(symbol: "forward.fill", size: 32, label: "Next") {
                Task { await spotify.skipNext() }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 72, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

/// Which device is playing, a way into the Spotify app, and any complaint from Spotify.
private struct Footer: View {
    let spotify: SpotifyModel
    let device: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = spotify.problem {
                Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if let device, !device.isEmpty {
                    Label("Playing on \(device)", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                OpenSpotifyButton(compact: true)
            }
        }
    }
}

// MARK: - Nothing to show yet

/// Everything that is not "a song is playing": not set up, not connected, waiting, or nothing playing.
private struct StatePanel: View {
    let spotify: SpotifyModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            switch spotify.phase {
            case .notConfigured:
                message(
                    symbol: "wrench.and.screwdriver.fill",
                    title: "Spotify isn't set up in this build",
                    detail: "Cabin Dash needs a Spotify Client ID to show what's playing. The README explains how to add one."
                )
                OpenSpotifyButton(compact: false)
            case .signedOut:
                message(
                    symbol: "music.note.list",
                    title: "Connect Spotify",
                    detail: "See what's playing and control it from here. You sign in on Spotify's own page, and it needs a Premium account."
                )
                ActionButton(title: "Connect Spotify", symbol: "link", filled: true) {
                    Task { await spotify.signIn() }
                }
                OpenSpotifyButton(compact: false)
            case .signingIn:
                ProgressView()
                Text("Connecting\u{2026}")
                    .font(.system(size: 18, weight: .semibold))
            case .signedIn:
                if spotify.hasAnswered {
                    message(
                        symbol: "pause.circle",
                        title: "Nothing is playing",
                        detail: "Start a song in Spotify, then come back. Cabin Dash steers the Spotify app. It doesn't play music itself."
                    )
                    OpenSpotifyButton(compact: false)
                } else {
                    ProgressView()
                    Text("Asking Spotify\u{2026}")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            if let problem = spotify.problem {
                Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Color.primary)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background {
                    if filled {
                        Capsule().fill(Color(hex: 0x1DB954))
                    } else {
                        Capsule().fill(Color.primary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
    }
}

/// Opens the Spotify app, where playlists and search live. Cabin Dash can't browse Spotify's library.
private struct OpenSpotifyButton: View {
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        if let spotify = Catalog.entry(id: "spotify") {
            if compact {
                Button {
                    model.launch(spotify)
                } label: {
                    Label("Open Spotify", systemImage: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.10), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(PressScaleStyle(scale: 0.95))
            } else {
                ActionButton(title: "Open Spotify", symbol: "arrow.up.right.square", filled: false) {
                    model.launch(spotify)
                }
            }
        }
    }
}
