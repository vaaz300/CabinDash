import CabinCore
import MapKit
import SwiftUI

/// Home: a live map beside the music and the speed. Each widget opens the full screen it summarises.
struct DashboardView: View {
    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 12
            HStack(spacing: gap) {
                MapWidget()
                    .frame(width: (proxy.size.width - gap) * 0.58)
                VStack(spacing: gap) {
                    MusicWidget()
                    DriveWidget()
                }
            }
        }
        .padding(.leading, CarLayout.railReserve)
        .padding(.trailing, CarLayout.edge)
        .padding(.vertical, CarLayout.edge)
    }
}

// MARK: - Map

/// A map that follows the iPhone and can't be dragged. The next turn sits on it while a route is being followed.
private struct MapWidget: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    var body: some View {
        let route = model.route
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        Button {
            model.go(.map)
        } label: {
            // The card sits at the top: Apple's "Maps" attribution and Legal link live in the bottom-left corner and must stay visible.
            ZStack(alignment: .topLeading) {
                Map(position: $camera, interactionModes: []) {
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: true))
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false)

                routeCard(route)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel(route.phase == .guiding ? "Map. Following a route" : "Map")
    }

    @ViewBuilder
    private func routeCard(_ route: RouteModel) -> some View {
        if route.phase == .guiding, let step = route.currentStep {
            HStack(spacing: 12) {
                Image(systemName: RouteFormat.maneuverSymbol(step.instruction))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.route)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RouteFormat.maneuverDistance(meters: route.metersToNext ?? step.meters, units: model.prefs.units))
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(step.instruction)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(RouteFormat.travelTime(seconds: route.remainingSeconds))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glass(radius: 18)
        } else {
            Label("Where to?", systemImage: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
    }
}

// MARK: - Music

/// What Spotify is playing, with previous, play/pause and next. Any other state is one line saying what to do.
private struct MusicWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let spotify = model.spotify

        ZStack {
            Button {
                model.go(.music)
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Music")

            if spotify.phase == .signedIn, let playing = spotify.nowPlaying {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        WidgetArtwork(url: playing.artworkURL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playing.title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Text(playing.subtitle)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)

                    HStack(spacing: 0) {
                        WidgetControl(symbol: "backward.fill", label: "Previous") {
                            Task { await spotify.skipPrevious() }
                        }
                        WidgetControl(symbol: playing.isPlaying ? "pause.fill" : "play.fill", label: playing.isPlaying ? "Pause" : "Play") {
                            Task { await spotify.togglePlayPause() }
                        }
                        WidgetControl(symbol: "forward.fill", label: "Next") {
                            Task { await spotify.skipNext() }
                        }
                    }
                }
                .padding(12)
            } else {
                Label(message(for: spotify.phase), systemImage: "music.note")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glass(radius: 24)
    }

    private func message(for phase: SpotifyModel.Phase) -> String {
        switch phase {
        case .notConfigured: return "Spotify isn't set up"
        case .signedOut: return "Connect Spotify"
        case .signingIn: return "Connecting\u{2026}"
        case .signedIn: return "Nothing playing"
        }
    }
}

private struct WidgetControl: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

private struct WidgetArtwork: View {
    let url: URL?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

// MARK: - Drive

/// The same speed dial as the Drive screen, with the trip underneath. Says so when there is no location rather than showing a confident zero.
private struct DriveWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location

    var body: some View {
        let units = model.prefs.units

        Button {
            model.go(.drive)
        } label: {
            Group {
                if location.access == .denied {
                    notice("Location is off", symbol: "location.slash.fill")
                } else if !location.hasFix {
                    notice("Finding GPS\u{2026}", symbol: "location.fill")
                } else {
                    let speed = units.speed(fromMetersPerSecond: location.speed)
                    GaugeView(
                        fraction: DriveFormat.gaugeFraction(speed: speed, units: units),
                        speed: String(Int(speed.rounded())),
                        unit: units.speedLabel,
                        status: "\(DriveFormat.distance(meters: location.trip.meters, units: units)) \(units.distanceLabel) \u{00B7} \(DriveFormat.duration(seconds: location.trip.seconds))"
                    )
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(radius: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel("Drive")
    }

    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(12)
    }
}
