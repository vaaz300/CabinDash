import SwiftUI
import CabinCore

/// The home screen: places to go, then the apps found on this iPhone, grouped like CarPlay.
struct AppsView: View {
    let landscape: Bool
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 104), spacing: 12, alignment: .top)]

    var body: some View {
        let shelf = model.shelf
        let sections = Shelf.sections(shelf)
        let recents = shelf.count > 8 ? Shelf.recents(shelf, ids: model.prefs.recent) : []

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                PlacesRow()
                if shelf.isEmpty {
                    EmptyShelfCard()
                } else {
                    if !recents.isEmpty {
                        section(title: "Recent", symbol: "clock.fill", tint: Theme.accent, apps: recents)
                    }
                    ForEach(sections) { group in
                        section(title: group.category.title, symbol: group.category.symbol, tint: group.category.tint, apps: group.apps)
                    }
                    addAppsButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.reloadAll() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.pickerPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .glass(radius: 22)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Add apps")
        }
    }

    private func section(title: String, symbol: String, tint: Color, apps: [AppEntry]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint.gradient, in: Circle())
                Text(title)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(apps) { app in
                    AppTile(app: app)
                }
            }
        }
    }

    private var addAppsButton: some View {
        Button {
            model.pickerPresented = true
        } label: {
            Label("Add apps", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glass(radius: 16)
        }
        .buttonStyle(PressScaleStyle())
        .frame(maxWidth: .infinity)
    }
}

/// Home, work and any other saved places: one tap starts directions in the chosen maps app.
struct PlacesRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.prefs.places.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.prefs.places) { place in
                        chip(place)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(_ place: Place) -> some View {
        Button {
            model.navigate(to: place)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: place.kind.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(AppCategory.navigation.tint.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(place.hasAddress ? place.address : "Add address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 180, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .glass(radius: 22)
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityLabel(place.name)
        .accessibilityHint(place.hasAddress ? "Starts directions to \(place.address)" : "Needs an address in Settings")
    }
}

private struct EmptyShelfCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text("No apps yet")
                .font(.title3.weight(.semibold))
            Text("Cabin Dash shows the supported apps it finds on this iPhone. Pull down to look again, or add apps yourself.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                model.pickerPresented = true
            } label: {
                Text("Add apps")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glass(radius: 26)
    }
}
