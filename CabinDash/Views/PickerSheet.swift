import SwiftUI
import CabinCore

/// Add or remove apps: the supported list, an App Store search, and links to anything else.
struct PickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var found: [AppEntry] = []
    @State private var searchState = SearchState.idle

    private enum SearchState {
        case idle
        case searching
        case failed
        case done
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    browse
                } else {
                    searchResults
                }
            }
            .navigationTitle("Add apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "App name or website")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .presentationDragIndicator(.visible)
        .task { await model.icons.sync(Catalog.all) }
        .task(id: trimmed) { await runSearch() }
    }

    // MARK: Browsing

    @ViewBuilder private var browse: some View {
        let onShelf = model.shelf
        if !onShelf.isEmpty {
            Section {
                ForEach(onShelf) { app in
                    row(app)
                }
            } header: {
                Text("On your shelf")
            }
        }
        ForEach(AppCategory.allCases, id: \.self) { category in
            let available = Catalog.apps(in: category).filter { !model.isOnShelf($0) }
            if !available.isEmpty {
                Section {
                    ForEach(available) { app in
                        row(app)
                    }
                } header: {
                    Text(category.title)
                }
            }
        }
        Section {
            Text("Apps Cabin Dash recognises show up by themselves. Anything else you add opens its web page or App Store page when tapped. To open an app directly, type its link below, like myapp://")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Searching

    @ViewBuilder private var searchResults: some View {
        let links = linkEntries
        let supported = Catalog.all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        if !links.isEmpty {
            Section {
                ForEach(links) { app in
                    row(app)
                }
            } header: {
                Text("Add a link")
            }
        }
        if !supported.isEmpty {
            Section {
                ForEach(supported) { app in
                    row(app)
                }
            } header: {
                Text("Supported apps")
            }
        }
        Section {
            switch searchState {
            case .searching:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching\u{2026}")
                        .foregroundStyle(.secondary)
                }
            case .failed:
                Label("Couldn't reach the App Store", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            case .idle, .done:
                let extra = found.filter { result in !supported.contains { $0.id == result.id } }
                if extra.isEmpty {
                    Text(trimmed.count < 2 ? "Type at least two letters to search the App Store" : "No other apps found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(extra) { app in
                        row(app)
                    }
                }
            }
        } header: {
            Text("App Store")
        }
    }

    /// What the typed text could be as a link: "myapp://" is an app's own link, "example.com" a website.
    private var linkEntries: [AppEntry] {
        if let scheme = WebLink.appScheme(from: trimmed) {
            return [AppEntry(id: "link-\(scheme)", name: scheme, category: .more, scheme: scheme, isCustom: true)]
        }
        if trimmed.contains("."), let url = WebLink.clean(trimmed) {
            var host = url.host ?? trimmed
            if host.hasPrefix("www.") { host.removeFirst(4) }
            return [AppEntry(id: "web-\(host)", name: host, category: .more, web: url.absoluteString, isCustom: true)]
        }
        return []
    }

    private func runSearch() async {
        found = []
        guard trimmed.count >= 2 else {
            searchState = .idle
            return
        }
        searchState = .searching
        try? await Task.sleep(for: .milliseconds(450))
        if Task.isCancelled { return }
        if let entries = await model.icons.search(trimmed) {
            if Task.isCancelled { return }
            found = entries
            searchState = .done
        } else if !Task.isCancelled {
            searchState = .failed
        }
    }

    // MARK: Rows

    private func row(_ app: AppEntry) -> some View {
        let onShelf = model.isOnShelf(app)
        return Button {
            if onShelf {
                model.remove(app)
            } else {
                model.add(app)
            }
        } label: {
            HStack(spacing: 14) {
                AppIconView(app: app, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(detail(for: app))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: onShelf ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(onShelf ? Theme.good : Theme.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .accessibilityValue(onShelf ? "On your shelf" : "Not added")
        .accessibilityHint(onShelf ? "Removes it" : "Adds it")
    }

    private func detail(for app: AppEntry) -> String {
        if app.isCustom { return app.web ?? ((app.scheme ?? "") + "://") }
        if model.isDetected(app) {
            return model.isOnShelf(app) ? "Found on this iPhone" : "Found on this iPhone, hidden"
        }
        if let publisher = app.publisher, !publisher.isEmpty { return publisher }
        return app.canBeDetected ? "Not found on this iPhone" : "Add it yourself"
    }
}
