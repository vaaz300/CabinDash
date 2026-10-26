import SwiftUI
import UIKit
import CabinCore

/// The tall frosted bar down the left edge: the time, the connection and battery, then the same buttons on every screen.
/// Home, Map, Music and Drive (and Apps, if switched on) stack from the top; Settings sits at the bottom.
struct StatusRail: View {
    @Environment(AppModel.self) private var model

    private let headerHeight: CGFloat = 84
    /// Breathing room above the first button and below the gear.
    private let verticalPadding: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let features = Dock.features(showOtherApps: model.prefs.showOtherApps)
            let available = proxy.size.height - headerHeight - verticalPadding * 2
            // The gear counts as a button for sizing, so everything fits whatever the screen height.
            let size = DockMetrics.iconSize(availableHeight: Double(available), itemCount: features.count + 1)
            let gap = DockMetrics.gap(forIconSize: size)

            VStack(spacing: 0) {
                StatusHeader()
                    .frame(height: headerHeight)
                VStack(spacing: CGFloat(gap)) {
                    ForEach(features, id: \.self) { feature in
                        FeatureButton(feature: feature, size: CGFloat(size), gap: CGFloat(gap))
                    }
                }
                .padding(.top, verticalPadding)
                Spacer(minLength: 0)
                FeatureButton(feature: Dock.footer, size: CGFloat(size), gap: CGFloat(gap))
                    .padding(.bottom, verticalPadding)
            }
            .frame(width: CarLayout.railWidth, height: proxy.size.height)
            .railGlass(radius: 38)
        }
        .frame(width: CarLayout.railWidth)
    }
}

/// Clock on top, then the connection and the battery. Re-reads every 20 seconds, which is plenty for both.
private struct StatusHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            VStack(spacing: 6) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Circle()
                        .fill(gpsColor)
                        .frame(width: 7, height: 7)
                    Image(systemName: model.device.connectivity.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                BatteryGlyph(level: model.device.batteryLevel, charging: model.device.isCharging)
            }
            .padding(.top, 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var gpsColor: Color {
        if location.access == .denied { return Theme.bad }
        return location.hasFix ? Theme.good : Color.primary.opacity(0.35)
    }

    private var accessibilityText: String {
        var parts = [Date.now.formatted(date: .omitted, time: .shortened)]
        if let level = model.device.batteryLevel {
            parts.append("Battery \(Int((level * 100).rounded())) percent")
        }
        parts.append(location.hasFix ? "GPS ready" : "No GPS yet")
        return parts.joined(separator: ", ")
    }
}

/// A small battery: an outline with a level bar, and a bolt while charging.
private struct BatteryGlyph: View {
    let level: Double?
    let charging: Bool

    var body: some View {
        let fraction = max(0.06, min(1, level ?? 1))
        let fill: Color = charging ? Theme.good : (fraction <= 0.2 ? Theme.bad : Color.primary)

        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fill)
                        .frame(width: max(3, (proxy.size.width - 3) * fraction))
                        .padding(1.5)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.75))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 30, height: 14)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.primary.opacity(0.45))
                .frame(width: 2, height: 5)
        }
        .opacity(level == nil ? 0.4 : 1)
    }
}

/// One of Cabin Dash's own screens. Marks the one showing, and does nothing when tapped again.
private struct FeatureButton: View {
    let feature: Feature
    let size: CGFloat
    let gap: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let showing = model.router.current == feature
        Button {
            if !showing { model.go(feature) }
        } label: {
            FeatureIcon(feature: feature, size: size)
                .overlay(alignment: .bottom) {
                    if showing {
                        Capsule()
                            .fill(Color.primary.opacity(0.9))
                            .frame(width: 14, height: 3)
                            .offset(y: gap / 2 + 1.5)
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(feature.title)
        .accessibilityAddTraits(showing ? .isSelected : [])
    }
}
