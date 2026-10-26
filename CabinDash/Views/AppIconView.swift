import SwiftUI
import CabinCore

/// An app icon: the real App Store artwork when it is known, a tinted letter tile until then.
struct AppIconView: View {
    let app: AppEntry
    var size: CGFloat = 64
    /// An SF Symbol to show instead of the first letter while the artwork is still on its way.
    var placeholderSymbol: String?
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
            if let placeholderSymbol {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            } else if app.isCustom && app.scheme == nil {
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
