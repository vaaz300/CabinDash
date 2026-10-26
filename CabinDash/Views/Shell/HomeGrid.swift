import SwiftUI
import CabinCore

/// The home screen: four icons across, two down, in pages you swipe between, with dots underneath.
struct HomeGrid: View {
    @Environment(AppModel.self) private var model
    @State private var page: Int? = 0

    var body: some View {
        let pages = HomeLayout.pages(model.homeItems)
        let current = min(max(page ?? 0, 0), max(pages.count - 1, 0))

        GeometryReader { proxy in
            let dotsHeight: CGFloat = 30
            let gridHeight = max(0, proxy.size.height - dotsHeight)
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            HomePage(items: pages[index], size: CGSize(width: proxy.size.width, height: gridHeight))
                                .frame(width: proxy.size.width, height: gridHeight)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .frame(height: gridHeight)

                PageDots(count: pages.count, current: current)
                    .frame(height: dotsHeight)
            }
        }
    }
}

/// One page: up to eight tiles, laid out in two rows of four. Missing tiles leave their space empty.
private struct HomePage: View {
    let items: [HomeItem]
    let size: CGSize

    var body: some View {
        let columns = 4
        let rows = HomeLayout.perPage / columns
        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)
        let icon = max(44, min(cellWidth * 0.62, cellHeight * 0.58))

        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        Group {
                            if index < items.count {
                                HomeTile(item: items[index], iconSize: icon)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: cellWidth, height: cellHeight)
                    }
                }
            }
        }
    }
}

/// An icon with its name in a small frosted pill underneath.
private struct HomeTile: View {
    let item: HomeItem
    let iconSize: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.open(item)
        } label: {
            VStack(spacing: max(6, iconSize * 0.08)) {
                HomeIcon(item: item, size: iconSize)
                LabelPill(text: item.title)
                    .frame(maxWidth: iconSize * 1.55)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button {
                model.open(item)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            if let app = item.app {
                Button(role: .destructive) {
                    model.remove(app)
                } label: {
                    Label("Remove from Cabin Dash", systemImage: "minus.circle")
                }
            }
        }
        .accessibilityLabel(item.title)
    }
}

struct LabelPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
    }
}

struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.primary.opacity(index == current ? 0.92 : 0.30))
                    .frame(width: 9, height: 9)
            }
        }
        .opacity(count > 1 ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: current)
        .accessibilityHidden(true)
    }
}

/// The picture on a tile or a rail button: App Store artwork when there is some, otherwise a flat glossy tile with a symbol.
struct HomeIcon: View {
    let item: HomeItem
    let size: CGFloat

    var body: some View {
        if let artwork = item.artwork {
            AppIconView(app: artwork, size: size, placeholderSymbol: item.app == nil ? item.symbol : nil)
        } else {
            SymbolTile(symbol: item.symbol, tone: item.tone, size: size)
        }
    }
}

/// An icon Cabin Dash draws itself. Apple's own apps have no App Store artwork to borrow, so these are original.
struct SymbolTile: View {
    let symbol: String
    let tone: HomeTone
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        ZStack {
            if tone == .red {
                // Like CarPlay's Now Playing: a white tile with a red symbol.
                Color.white
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: 0xFF5F6D), Color(hex: 0xFF2D55)], startPoint: .top, endPoint: .bottom)
                    )
            } else {
                LinearGradient(
                    colors: [tone.color.opacity(0.82), tone.color],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75
            )
        )
        .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }
}
