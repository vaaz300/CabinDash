import SwiftUI
import UIKit
import CabinCore

/// The tall frosted bar down the left edge: the time, the connection and battery, the apps you used last, and the home button.
struct StatusRail: View {
    @Environment(AppModel.self) private var model

    private let iconSize: CGFloat = 52
    private let iconGap: CGFloat = 16
    private let headerHeight: CGFloat = 104
    private let footerHeight: CGFloat = 70

    var body: some View {
        GeometryReader { proxy in
            let room = proxy.size.height - headerHeight - footerHeight - 24
            let slots = max(1, min(4, Int(room / (iconSize + iconGap))))
            let dock = HomeLayout.dock(items: model.homeItems, recent: model.prefs.recent, limit: slots)

            VStack(spacing: 0) {
                StatusHeader()
                    .frame(height: headerHeight)
                Spacer(minLength: 0)
                VStack(spacing: iconGap) {
                    ForEach(dock) { item in
                        RailButton(item: item, size: iconSize)
                    }
                }
                Spacer(minLength: 0)
                HomeButton()
                    .frame(height: footerHeight)
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
            .padding(.top, 18)
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

/// One of the apps used last. Opens it, or does nothing if it is the screen already showing.
private struct RailButton: View {
    let item: HomeItem
    let size: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let showing = item.screen != nil && item.screen == model.screen
        Button {
            if !showing { model.open(item) }
        } label: {
            HomeIcon(item: item, size: size)
                .overlay(alignment: .bottom) {
                    if showing {
                        Capsule()
                            .fill(Color.primary.opacity(0.9))
                            .frame(width: 14, height: 3)
                            .offset(y: 8)
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(showing ? .isSelected : [])
    }
}

/// The rounded square at the bottom, which goes back to the home screen.
private struct HomeButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.show(nil)
        } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary, lineWidth: 3)
                .frame(width: 30, height: 30)
                .frame(width: CarLayout.railWidth, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel("Home")
    }
}
