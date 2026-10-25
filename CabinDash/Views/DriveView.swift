import SwiftUI
import CabinCore

/// Live speed, heading and trip totals.
struct DriveView: View {
    let landscape: Bool
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location

    var body: some View {
        let units = model.prefs.units
        let speedValue = units.speed(fromMetersPerSecond: location.speed)
        let gauge = GaugeView(
            fraction: DriveFormat.gaugeFraction(speed: speedValue, units: units),
            speed: String(Int(speedValue.rounded())),
            unit: units.speedLabel,
            status: statusText
        )

        Group {
            if landscape {
                HStack(spacing: 20) {
                    gauge
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 14) {
                        tiles(units: units)
                        resetButton
                    }
                    .frame(maxWidth: 380)
                }
            } else {
                VStack(spacing: 18) {
                    gauge
                        .frame(maxWidth: 380, maxHeight: .infinity)
                    tiles(units: units)
                    resetButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay {
            if location.access == .denied {
                PermissionCard()
            }
        }
    }

    private var statusText: String? {
        switch location.access {
        case .unknown: return "Waiting for permission"
        case .denied: return "Location is off"
        case .allowed: return location.hasFix ? nil : "Finding GPS\u{2026}"
        }
    }

    private func tiles(units: Units) -> some View {
        let trip = location.trip
        let average = trip.averageSpeed.map { units.speed(fromMetersPerSecond: $0) }
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            StatTile(
                title: "Trip",
                symbol: "map",
                value: DriveFormat.distance(meters: trip.meters, units: units),
                unit: units.distanceLabel
            )
            StatTile(
                title: "Time",
                symbol: "clock",
                value: DriveFormat.duration(seconds: trip.seconds),
                unit: ""
            )
            StatTile(
                title: "Average",
                symbol: "speedometer",
                value: average.map { String(Int($0.rounded())) } ?? "\u{2014}",
                unit: average == nil ? "" : units.speedLabel
            )
            StatTile(
                title: "Heading",
                symbol: "location.north.fill",
                symbolRotation: location.hasHeading ? location.heading : 0,
                value: location.hasHeading ? Compass.cardinal(location.heading) : "\u{2014}",
                unit: location.hasHeading ? Compass.degreesText(location.heading) : ""
            )
        }
    }

    private var resetButton: some View {
        let empty = location.trip.meters == 0 && location.trip.seconds == 0
        return Button {
            let tracker = location
            let previous = tracker.resetTrip()
            model.toast.show("Trip reset", actionTitle: "Undo") {
                tracker.restoreTrip(previous)
            }
        } label: {
            Label("Reset trip", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glass(radius: 16)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(empty)
        .opacity(empty ? 0.5 : 1)
    }
}

private struct StatTile: View {
    let title: String
    let symbol: String
    var symbolRotation: Double = 0
    let value: String
    let unit: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .rotationEffect(.degrees(symbolRotation))
                    .animation(reduceMotion ? nil : Animation.smooth(duration: 0.4), value: symbolRotation)
                Text(title)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(radius: 20)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accent)
            Text("Location is off")
                .font(.headline)
            Text("Cabin Dash needs your location to show speed and trip distance. It stays on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                model.openSystemSettings()
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(20)
    }
}
