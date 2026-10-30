import SwiftUI
import CabinCore

/// The tall frosted bar down the left edge: the time, the connection and the battery, then Cabin Dash's screens in pages
/// of four, swiped up and down. The first page is Home, Map, Music and Phone; the second Drive, Apps (if switched on) and
/// Settings. Dots under the buttons show which page is up, and tapping a dot goes to its page.
struct StatusRail: View {
    @Environment(AppModel.self) private var model
    @State private var page: Int? = 0

    private let headerHeight: CGFloat = 84
    private let dotsHeight: CGFloat = 26
    /// Breathing room above the first button of a page.
    private let verticalPadding: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let pages = Dock.pages(showOtherApps: model.prefs.showOtherApps)
            let pageHeight = max(0, proxy.size.height - headerHeight - dotsHeight)
            // Sized for a full page of four, so the buttons are the same size on every page.
            let size = DockMetrics.iconSize(availableHeight: Double(pageHeight - verticalPadding * 2), itemCount: Dock.perPage)
            let gap = DockMetrics.gap(forIconSize: size)

            VStack(spacing: 0) {
                StatusHeader()
                    .frame(height: headerHeight)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            VStack(spacing: CGFloat(gap)) {
                                ForEach(pages[index], id: \.self) { feature in
                                    FeatureButton(feature: feature, size: CGFloat(size), gap: CGFloat(gap))
                                }
                            }
                            .padding(.top, verticalPadding)
                            .frame(width: CarLayout.railWidth, height: pageHeight, alignment: .top)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .frame(height: pageHeight)

                DockDots(count: pages.count, current: page ?? 0) { index in
                    withAnimation(.easeOut(duration: 0.25)) { page = index }
                }
                .frame(height: dotsHeight)
            }
            .frame(width: CarLayout.railWidth, height: proxy.size.height)
            .railGlass(radius: 38)
        }
        .frame(width: CarLayout.railWidth)
        // Going to a screen from elsewhere (a widget, a strip, Settings) turns the dock to the page with its button.
        .onChange(of: model.router.current, initial: true) { _, feature in
            if let target = Dock.page(of: feature, showOtherApps: model.prefs.showOtherApps), target != page {
                withAnimation(.easeOut(duration: 0.25)) { page = target }
            }
        }
    }
}

/// One dot per dock page, the current one bright. Each dot is a 44 pt target that turns to its page.
private struct DockDots: View {
    let count: Int
    let current: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    select(index)
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(index == current ? 0.9 : 0.3))
                        .frame(width: 7, height: 7)
                        .frame(width: 22, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dock page \(index + 1) of \(count)")
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
        .opacity(count > 1 ? 1 : 0)
    }
}

/// Clock on top, then the connection and the battery. Re-reads every 20 seconds, which is plenty for both.
private struct StatusHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            VStack(spacing: 6) {
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

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
