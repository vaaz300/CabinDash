import SwiftUI

/// The CarPlay-style dock: Apps, Drive and Settings. Sits along the bottom, or down the left edge in landscape.
struct DockBar: View {
    let landscape: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = landscape ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            DockButton(title: "Apps", symbol: "square.grid.2x2.fill", selected: model.tab == .apps) {
                model.tab = .apps
            }
            DockButton(title: "Drive", symbol: "speedometer", selected: model.tab == .drive) {
                model.tab = .drive
            }
            DockButton(title: "Settings", symbol: "gearshape.fill", selected: false) {
                model.settingsPresented = true
            }
        }
        .padding(8)
        .frame(width: landscape ? 92 : nil)
        .glass(radius: 28)
    }
}

private struct DockButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(height: 26)
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selected ? Theme.accent : Color.primary)
            .frame(minWidth: 72, maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
