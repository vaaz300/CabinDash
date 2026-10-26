import CabinCore
import CoreLocation
import MapKit
import Observation
import SwiftUI
import UIKit

/// Looks up places by name or address with Apple Maps, favouring results near the car.
@MainActor @Observable
final class DestinationSearch {
    private(set) var results: [MKMapItem] = []
    private(set) var searching = false
    private(set) var failed = false

    func clear() {
        results = []
        searching = false
        failed = false
    }

    func run(_ text: String, near center: CLLocationCoordinate2D?) async {
        searching = true
        failed = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            if Task.isCancelled { return }
            results = response.mapItems
            searching = false
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            results = []
            failed = true
            searching = false
        }
    }
}

/// Type a place, pick a result, and the map plans a route to it.
@MainActor
struct DestinationSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var search = DestinationSearch()

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var center: CLLocationCoordinate2D? {
        guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        NavigationStack {
            List {
                if search.failed {
                    Label("Couldn't search. Check the connection and try again.", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                } else if trimmed.count >= 2, !search.searching, search.results.isEmpty {
                    Text("No places found for \u{201C}\(trimmed)\u{201D}.")
                        .foregroundStyle(.secondary)
                }
                ForEach(search.results, id: \.self) { item in
                    Button {
                        choose(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.route)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let address = Self.address(of: item) {
                                    Text(address)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if search.searching && search.results.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Address, place or business")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                let text = trimmed
                guard text.count >= 2 else {
                    search.clear()
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
                if Task.isCancelled { return }
                await search.run(text, near: center)
            }
        }
    }

    private func choose(_ item: MKMapItem) {
        // Take the model out of the environment now: this sheet is about to go away.
        let route = model.route
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
        Task { await route.plan(to: item) }
    }

    private static func address(of item: MKMapItem) -> String? {
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street, placemark.locality ?? "", placemark.administrativeArea ?? ""].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
