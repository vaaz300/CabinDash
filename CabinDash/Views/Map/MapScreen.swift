import CabinCore
import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// The in-app map: a full-screen Apple Maps view with a panel on the left for choosing a destination,
/// previewing the route, and following it turn by turn.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var searching = false

    var body: some View {
        let route = model.route

        GeometryReader { proxy in
            ZStack {
                map(route)
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    panel(route)
                        .frame(width: min(330, proxy.size.width * 0.42))
                        .frame(maxHeight: .infinity, alignment: .top)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CarLayout.railReserve)
                .padding(.vertical, CarLayout.edge)

                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if location.hasFix {
                        SpeedChip()
                    }
                    RecenterButton {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            camera = .userLocation(followsHeading: route.phase == .guiding, fallback: .automatic)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.trailing, CarLayout.edge)
                .padding(.bottom, CarLayout.edge)
            }
        }
        .sheet(isPresented: $searching) {
            DestinationSearchSheet()
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
        .onAppear {
            // Coming back from another screen builds this view again with the default camera. Frame it for where the route is now.
            if let position = framing(for: route.phase, route: route) { camera = position }
        }
        .onChange(of: route.phase) { _, phase in
            moveCamera(for: phase, route: route)
        }
    }

    // MARK: Map

    private func map(_ route: RouteModel) -> some View {
        Map(position: $camera) {
            UserAnnotation()
            RouteMapContent(route: route)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: true))
        .mapControlVisibility(.hidden)
    }

    /// Where the camera belongs at this stage of the route, or nil to leave it where it is.
    private func framing(for phase: RouteModel.Phase, route: RouteModel) -> MapCameraPosition? {
        switch phase {
        case .preview:
            guard let rect = route.route?.polyline.boundingMapRect else { return nil }
            return MapCameraPosition.rect(Self.leaveRoomForPanel(rect))
        case .guiding:
            return MapCameraPosition.userLocation(followsHeading: true, fallback: .automatic)
        case .idle:
            return MapCameraPosition.userLocation(followsHeading: false, fallback: .automatic)
        case .loading, .arrived:
            return nil
        }
    }

    private func moveCamera(for phase: RouteModel.Phase, route: RouteModel) {
        guard let position = framing(for: phase, route: route) else { return }
        withAnimation(.easeInOut(duration: 0.7)) {
            camera = position
        }
    }

    /// Widens the route's box, mostly to the left, so the route lands in the part of the map the panel does not cover.
    private static func leaveRoomForPanel(_ rect: MKMapRect) -> MKMapRect {
        let width = rect.size.width
        let height = rect.size.height
        return MKMapRect(
            x: rect.origin.x - width * 1.1,
            y: rect.origin.y - height * 0.45,
            width: width * 2.4,
            height: height * 1.9
        )
    }

    // MARK: Panel

    @ViewBuilder
    private func panel(_ route: RouteModel) -> some View {
        switch route.phase {
        case .idle:
            IdlePanel(route: route, searching: $searching)
        case .loading:
            LoadingPanel(route: route)
        case .preview:
            PreviewPanel(route: route)
        case .guiding:
            GuidancePanel(route: route)
        case .arrived:
            ArrivedPanel(route: route)
        }
    }
}

// MARK: - Panels

/// Where to? and one-tap routes to saved places.
private struct IdlePanel: View {
    let route: RouteModel
    @Binding var searching: Bool
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location

    private var saved: [Place] {
        Array(model.prefs.places.filter(\.hasAddress).prefix(3))
    }

    private var center: CLLocationCoordinate2D? {
        guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                searching = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Where to?")
                        .font(.system(size: 19, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glass(radius: 20)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))

            ForEach(saved) { place in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let target = center
                    Task { await self.route.plan(toAddress: place.address, name: place.name, near: target) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: place.kind.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.route)
                            .frame(width: 26)
                        Text(place.name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glass(radius: 18)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            }

            if saved.isEmpty {
                Button {
                    model.go(.settings)
                } label: {
                    Label("Add Home or Work in Settings", systemImage: "house")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
            }

            if let problem = route.problem {
                ProblemRow(text: problem) { route.dismissProblem() }
            }

            if location.access == .denied {
                ProblemRow(text: "Location is off, so the map can't follow you.", dismiss: nil)
            }
        }
    }
}

private struct ProblemRow: View {
    let text: String
    let dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .glass(radius: 16)
    }
}

private struct LoadingPanel: View {
    let route: RouteModel

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Finding a route\u{2026}")
                .font(.system(size: 17, weight: .semibold))
            Spacer(minLength: 0)
            Button("Cancel") { route.clear() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.route)
        }
        .padding(16)
        .glass(radius: 20)
    }
}

/// The route is drawn; ask whether to follow it here or hand it to the maps app.
private struct PreviewPanel: View {
    let route: RouteModel
    @Environment(AppModel.self) private var model

    var body: some View {
        let units = model.prefs.units
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.destinationName)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(2)
                    Text("\(RouteFormat.travelTime(seconds: route.remainingSeconds)) \u{00B7} \(RouteFormat.tripDistance(meters: route.remainingMeters, units: units))")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                CircleButton(symbol: "xmark", label: "Cancel route") { route.clear() }
            }
            PanelButton(title: "Start", symbol: "location.fill", filled: true) { route.start() }
            HandOffButton(route: route, filled: false)
        }
        .padding(16)
        .glass(radius: 24)
    }
}

/// While driving: the next manoeuvre on top, and time, distance and arrival along the bottom.
private struct GuidancePanel: View {
    let route: RouteModel
    @Environment(AppModel.self) private var model

    var body: some View {
        let units = model.prefs.units
        VStack(spacing: 10) {
            if let step = route.currentStep {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: RouteFormat.maneuverSymbol(step.instruction))
                        .font(.system(size: 40, weight: .bold))
                        .frame(width: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(RouteFormat.maneuverDistance(meters: route.metersToNext ?? step.meters, units: units))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(step.instruction)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(Color(hex: 0x16181F).opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RouteFormat.travelTime(seconds: route.remainingSeconds))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("\(RouteFormat.tripDistance(meters: route.remainingMeters, units: units)) \u{00B7} \(arrival)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                CircleButton(symbol: "arrow.triangle.2.circlepath", label: "Get a new route") {
                    Task { await self.route.reroute() }
                }
                HandOffCircle(route: route)
                CircleButton(symbol: "xmark", label: "End route", tint: Theme.bad) { route.clear() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glass(radius: 24)
        }
    }

    private var arrival: String {
        Date.now.addingTimeInterval(route.remainingSeconds).formatted(date: .omitted, time: .shortened)
    }
}

private struct ArrivedPanel: View {
    let route: RouteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You've arrived")
                        .font(.system(size: 22, weight: .bold))
                    Text(route.destinationName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            PanelButton(title: "Done", symbol: "checkmark", filled: true) { route.clear() }
        }
        .padding(16)
        .glass(radius: 24)
    }
}

// MARK: - Pieces

/// A wide labelled button: filled blue for the main action, frosted for the rest.
private struct PanelButton: View {
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background {
                    if filled {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.route)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.10))
                    }
                }
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }
}

/// Hands the destination to the navigation app chosen in Settings, so it can do the real turn-by-turn.
private struct HandOffButton: View {
    let route: RouteModel
    let filled: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        PanelButton(title: "Open in \(model.prefs.navApp.title)", symbol: "arrow.up.right.square", filled: filled) {
            if let coordinate = route.destination?.placemark.coordinate {
                model.navigate(toLatitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
    }
}

private struct HandOffCircle: View {
    let route: RouteModel
    @Environment(AppModel.self) private var model

    var body: some View {
        CircleButton(symbol: "arrow.up.right.square", label: "Open in \(model.prefs.navApp.title)") {
            if let coordinate = route.destination?.placemark.coordinate {
                model.navigate(toLatitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
    }
}

private struct CircleButton: View {
    let symbol: String
    let label: String
    var tint: Color = Color.primary
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.10), in: Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

private struct RecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.route)
                .frame(width: 48, height: 48)
                .glass(radius: 24)
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel("Centre the map on me")
    }
}

private struct SpeedChip: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location

    var body: some View {
        let units = model.prefs.units
        let value = Int(units.speed(fromMetersPerSecond: location.speed).rounded())
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(units.speedLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 58, height: 48)
        .glass(radius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed \(value) \(units.speedLabel)")
    }
}
