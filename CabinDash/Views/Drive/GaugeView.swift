import Foundation
import SwiftUI

/// A 240 degree speed dial. The number in the middle is the main thing; the arc and ticks are secondary.
struct GaugeView: View {
    let fraction: Double
    let speed: String
    let unit: String
    var status: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Degrees of arc, and the angle where it starts. SwiftUI measures angles clockwise from 3 o'clock,
    /// so 150 is the lower left and 150 + 240 = 390 (30) is the lower right.
    private static let sweep = 240.0
    private static let start = 150.0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.07
            ZStack {
                track(line: line)
                fill(line: line)
                ticks(line: line)
                readout(side: side)
            }
            .frame(width: side, height: side)
            .overlay(alignment: .bottom) {
                if let status {
                    Text(status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.bottom, side * 0.05)
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed")
        .accessibilityValue("\(speed) \(unit)")
    }

    private func track(line: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: Self.sweep / 360)
            .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(Self.start))
            .padding(line / 2)
    }

    private func fill(line: CGFloat) -> some View {
        let clamped = max(0, min(1, fraction))
        return Circle()
            .trim(from: 0, to: clamped * Self.sweep / 360)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(Self.start))
            .padding(line / 2)
            .opacity(clamped > 0.004 ? 1 : 0)
            .animation(reduceMotion ? nil : Animation.smooth(duration: 0.45), value: clamped)
    }

    private func ticks(line: CGFloat) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = size.width / 2 - line - 6
            for index in 0...40 {
                let major = index % 5 == 0
                let degrees = Self.start + Double(index) * 6
                let angle = CGFloat(degrees * Double.pi / 180)
                let inner = outer - (major ? 13 : 7)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                context.stroke(
                    path,
                    with: .color(.primary.opacity(major ? 0.45 : 0.22)),
                    style: StrokeStyle(lineWidth: major ? 2 : 1, lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func readout(side: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(speed)
                .font(.system(size: side * 0.36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Animation.snappy(duration: 0.25), value: speed)
            Text(unit)
                .font(.system(size: side * 0.075, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .offset(y: -side * 0.02)
    }
}
