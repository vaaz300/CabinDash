import SwiftUI
import CabinCore

/// Home: one large button for each of the screens you reach for while driving. The live widgets replace these tiles in the next step.
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            ForEach([Feature.map, .music, .drive], id: \.self) { feature in
                Button {
                    model.go(feature)
                } label: {
                    VStack(spacing: 14) {
                        FeatureIcon(feature: feature, size: 84)
                        Text(feature.title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glass(radius: 24)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .accessibilityLabel(feature.title)
            }
        }
        .padding(.leading, CarLayout.railReserve)
        .padding(.trailing, CarLayout.edge)
        .padding(.vertical, CarLayout.edge)
    }
}
