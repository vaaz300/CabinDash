import SwiftUI
import CabinCore

/// An app icon: the real App Store artwork when it is known, a tinted letter tile until then.
struct AppIconView: View {
    let app: AppEntry
    var size: CGFloat = 64
    @Environment(AppModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        ZStack {
            if let image = model.icons.image(for: app) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.04)
        .task(id: app.iconKey) { await model.icons.ensureImage(for: app) }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [app.category.tint.opacity(0.95), app.category.tint.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            if app.isCustom && app.scheme == nil {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(String(app.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// An icon with its name underneath. Tapping opens the app.
struct AppTile: View {
    let app: AppEntry
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.launch(app)
        } label: {
            VStack(spacing: 7) {
                AppIconView(app: app, size: 64)
                Text(app.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button {
                model.launch(app)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button(role: .destructive) {
                model.remove(app)
            } label: {
                Label("Remove from Cabin Dash", systemImage: "minus.circle")
            }
        }
        .accessibilityLabel(app.name)
        .accessibilityHint("Opens \(app.name)")
    }
}
