import SwiftUI
import CabinCore

/// The thin bars that follow the driver from screen to screen: the next turn while a route is being followed,
/// and the playing track while Spotify plays. Which of them show on which screen is decided by `Strips.visible` in CabinCore.
struct StripStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let spotify = model.spotify
        let strips = Strips.visible(
            on: model.router.current,
            musicActive: spotify.phase == .signedIn && spotify.nowPlaying != nil,
            routeGuiding: model.route.phase == .guiding
        )

        VStack(alignment: .trailing, spacing: 8) {
            ForEach(strips, id: \.self) { strip in
                Group {
                    switch strip {
                    case .route:
                        RouteBannerStrip()
                    case .music:
                        MiniPlayerStrip()
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 380)
        .animation(.easeOut(duration: 0.2), value: strips)
    }
}

/// The track that is playing, with one play/pause button. Tapping anywhere else opens Music.
struct MiniPlayerStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let spotify = model.spotify
        if let playing = spotify.nowPlaying {
            HStack(spacing: 6) {
                Button {
                    model.go(.music)
                } label: {
                    HStack(spacing: 10) {
                        StripArtwork(url: playing.artworkURL)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(playing.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(playing.subtitle)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Music. Playing \(playing.title)")

                Button {
                    Task { await spotify.togglePlayPause() }
                } label: {
                    Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .accessibilityLabel(playing.isPlaying ? "Pause" : "Play")
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .glass(radius: 18)
        }
    }
}

private struct StripArtwork: View {
    let url: URL?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Color(hex: 0x1DB954).opacity(0.85)
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// The next instruction while a route is being followed, with the distance to it and the time left. Tapping opens Map.
struct RouteBannerStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let route = model.route
        if let step = route.currentStep {
            Button {
                model.go(.map)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: RouteFormat.maneuverSymbol(step.instruction))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.route)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(RouteFormat.maneuverDistance(meters: route.metersToNext ?? step.meters, units: model.prefs.units))
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text(step.instruction)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(RouteFormat.travelTime(seconds: route.remainingSeconds))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glass(radius: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .accessibilityLabel("Next: \(step.instruction), in \(RouteFormat.maneuverDistance(meters: route.metersToNext ?? step.meters, units: model.prefs.units)). Open Map")
        }
    }
}
