import SwiftUI

/// The short message with an optional action (Undo), shown above the dock.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let center = model.toast
        ZStack {
            if let toast = center.current {
                HStack(spacing: 16) {
                    Text(toast.message)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if let title = toast.actionTitle {
                        Button(title) { center.performAction() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.easeOut(duration: 0.22), value: center.current)
    }
}
