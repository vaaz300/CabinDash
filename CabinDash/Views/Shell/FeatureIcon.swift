import SwiftUI
import CabinCore

/// The icon of one of Cabin Dash's own screens, in the dock and on the Home screen.
struct FeatureIcon: View {
    let feature: Feature
    let size: CGFloat

    var body: some View {
        SymbolTile(symbol: feature.symbol, tone: feature.tone, size: size)
    }
}
