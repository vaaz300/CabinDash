import CabinCore
import SwiftUI
import UIKit

/// What Spotify is playing, with the controls. Spotify itself keeps playing in its own app;
/// this pane reads its state and steers it. The Music screen supplies the padding around it.
struct NowPlayingPane: View {
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
        // The heart needs to know whether this song is liked, which is asked once per song while this pane is showing.
        .onChange(of: spotify.nowPlaying?.uri, initial: true) { _, uri in
            if let uri { model.library.refreshLiked(for: uri) }
        }
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

                    ProgressBar(spotify: spotify, duration: playing.duration, canSeek: playing.canSeek)
                        .padding(.top, 12)

                    Controls(spotify: spotify, track: playing)
                        .padding(.top, 6)

                    Spacer(minLength: 0)
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
        // Spotify's design guidelines ask for artwork shown unaltered, with 8 pt corners on large screens.
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityHidden(true)
    }
}

/// Elapsed time, a bar you can tap or drag to jump around, and the time left.
private struct ProgressBar: View {
    let spotify: SpotifyModel
    let duration: Double
    /// False when Spotify says seeking is not allowed (some ads and podcasts), so the bar is shown but does nothing.
    let canSeek: Bool
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
                .allowsHitTesting(canSeek)
                .opacity(canSeek ? 1 : 0.45)
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

/// Previous, play or pause and next, with shuffle and repeat on a smaller row beneath.
/// A control Spotify has switched off for this track (an ad, say) is dimmed and does nothing.
private struct Controls: View {
    let spotify: SpotifyModel
    let track: NowPlaying

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 44) {
                Spacer(minLength: 0)
                ControlButton(symbol: "backward.fill", size: 32, label: "Previous", enabled: track.canSkipPrevious) {
                    Task { await spotify.skipPrevious() }
                }
                ControlButton(
                    symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 40,
                    label: track.isPlaying ? "Pause" : "Play"
                ) {
                    Task { await spotify.togglePlayPause() }
                }
                ControlButton(symbol: "forward.fill", size: 32, label: "Next", enabled: track.canSkipNext) {
                    Task { await spotify.skipNext() }
                }
                Spacer(minLength: 0)
            }
            // Three buttons now (shuffle, repeat, like), kept narrower than the transport row above so nothing is clipped.
            HStack(spacing: 28) {
                Spacer(minLength: 0)
                ModeButton(
                    symbol: "shuffle", label: track.shuffle ? "Shuffle on" : "Shuffle off",
                    active: track.shuffle, enabled: track.canShuffle
                ) {
                    Task { await spotify.toggleShuffle() }
                }
                ModeButton(
                    symbol: track.repeatMode.symbol, label: track.repeatMode.title,
                    active: track.repeatMode != .off, enabled: track.canRepeat
                ) {
                    Task { await spotify.cycleRepeat() }
                }
                if SpotifyLibraryModel.canLike(track.uri), let uri = track.uri {
                    LikeButton(uri: uri)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 72, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

/// Shuffle and repeat: smaller than the transport, and lit when on.
private struct ModeButton: View {
    let symbol: String
    let label: String
    let active: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(active ? Theme.accent : Color.primary.opacity(0.7))
                .frame(width: 72, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// The heart: lit when the song is in Liked Songs. Dimmed until Spotify has said which; tapping it then asks again.
private struct LikeButton: View {
    let uri: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let liked = model.library.isLiked(uri)
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.library.toggleLiked(uri)
        } label: {
            Image(systemName: liked == true ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(liked == true ? Theme.accent : Color.primary.opacity(0.7))
                .frame(width: 72, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .opacity(liked == nil ? 0.4 : 1)
        .accessibilityLabel(liked == true ? "Remove from Liked Songs" : "Add to Liked Songs")
        .accessibilityAddTraits(liked == true ? [.isSelected] : [])
    }
}

// MARK: - Nothing to show yet

/// Everything that is not "a song is playing": not set up, not connected, waiting, or nothing playing.
/// The Music screen shows it whole when Spotify is not connected, and inside Now Playing when nothing is playing.
struct StatePanel: View {
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
                SpotifyAttribution(compact: false)
            case .signedOut:
                message(
                    symbol: "music.note.list",
                    title: "Connect Spotify",
                    detail: "See what's playing and control it from here. You sign in on Spotify's own page, and it needs a Premium account."
                )
                ActionButton(title: "Connect Spotify", symbol: "link", filled: true) {
                    Task { await spotify.signIn() }
                }
                SpotifyAttribution(compact: false)
            case .needsReconnect:
                message(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Connect Spotify again",
                    detail: "Cabin Dash now browses your playlists and likes songs, which needs a few more permissions. You only do this once."
                )
                ActionButton(title: "Connect Spotify", symbol: "link", filled: true) {
                    Task { await spotify.signIn() }
                }
            case .signingIn:
                ProgressView()
                Text("Connecting\u{2026}")
                    .font(.system(size: 18, weight: .semibold))
            case .signedIn:
                if spotify.hasAnswered {
                    message(
                        symbol: "pause.circle",
                        title: "Nothing is playing",
                        detail: "Pick something from Playlists, Liked or Search. Spotify plays the sound, so keep the Spotify app running on this iPhone."
                    )
                } else {
                    ProgressView()
                    Text("Asking Spotify\u{2026}")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            // Once connected, the Music screen shows the complaint in a banner above the sections.
            if spotify.phase != .signedIn, let problem = spotify.problem {
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
