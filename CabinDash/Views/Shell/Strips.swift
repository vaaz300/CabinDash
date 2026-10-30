import SwiftUI
import CabinCore

/// The thin bars that follow the driver from screen to screen: the next turn while a route is being followed,
/// and the playing track while Spotify plays. Which of them show on which screen is decided by `Strips.visible` in CabinCore.
struct StripStack: View {
    /// The strips to draw, in order.
    let strips: [Strip]
    /// Side by side in one bar (the bottom of most screens), or one above the other (the Map's top right corner).
    var stacked = false

    var body: some View {
        // One bar along the bottom, as wide as the screen's content, so its edges line up with what is above it.
        // With more than one strip showing they share it equally, the most urgent first.
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: StripClearance.gap))
            : AnyLayout(HStackLayout(spacing: StripClearance.gap))
        layout {
            ForEach(strips, id: \.self) { strip in
                Group {
                    switch strip {
                    case .call:
                        CallStrip()
                    case .route:
                        RouteBannerStrip()
                    case .music:
                        MiniPlayerStrip()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: StripClearance.height)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: strips)
    }
}

/// The phone's call, while there is one: what it is doing and, once connected, how long it has lasted. iOS does not say
/// who the call is with. Tapping opens the Phone screen.
struct CallStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        Button {
            model.go(.phone)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: phone.callStatus == .ringing ? "phone.arrow.down.left.fill" : "phone.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.good)
                    .frame(width: 30)
                Text(phone.callStatus.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let since = phone.callConnectedAt {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(CallFormat.duration(context.date.timeIntervalSince(since)))
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .glass(radius: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel("\(phone.callStatus.title). Open Phone")
    }
}

extension AppModel {
    /// The strips floating over the bottom of the current screen. `StripStack` draws them, and screens that end above them ask here.
    var visibleStrips: [Strip] {
        Strips.visible(
            on: router.current,
            musicActive: spotify.phase == .signedIn && spotify.nowPlaying != nil,
            routeGuiding: route.phase == .guiding,
            callActive: phone.callStatus.isLive
        )
    }

    /// The strips in the bar along the bottom. The Map has its own place for them, in the open space at the top right
    /// beside its panel, so its route panel can use the full height; every other screen ends above this bar.
    var bottomStrips: [Strip] {
        router.current == .map ? [] : visibleStrips
    }
}

/// How much room a screen keeps free along its bottom edge so its content ends above the strips instead of under them.
/// The heights are those of the strips as drawn below; if a strip changes size, change them here too.
enum StripClearance {
    /// The height of the bar the strips sit in. Both strips are drawn to fill it.
    static let height: CGFloat = 56
    /// The gap between the strips, and between the bar and the content above it.
    static let gap: CGFloat = 10

    /// The room the bar takes, with the edge below it and the gap above it. Zero when nothing floats there.
    static func reserve(for strips: [Strip]) -> CGFloat {
        strips.isEmpty ? 0 : CarLayout.edge + height + gap
    }

    /// The bottom padding for a screen: the usual edge when nothing floats there, otherwise room for the bar.
    static func bottom(for strips: [Strip]) -> CGFloat {
        max(CarLayout.edge, reserve(for: strips))
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
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(maxHeight: .infinity)
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
                .frame(maxHeight: .infinity)
                .glass(radius: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .accessibilityLabel("Next: \(step.instruction), in \(RouteFormat.maneuverDistance(meters: route.metersToNext ?? step.meters, units: model.prefs.units)). Open Map")
        }
    }
}
