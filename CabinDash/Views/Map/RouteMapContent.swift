import CoreLocation
import MapKit
import SwiftUI

/// What Cabin Dash draws on a map above the base map: the route, and a flag where it ends.
///
/// The Map screen and the Home map widget both use this, so the two cannot disagree about what a route looks like.
/// It holds plain values. `init(route:)` copies them out of the route model when the view that draws the map is built,
/// so that view is the one that gets redrawn when the route changes.
struct RouteMapContent: MapContent {
    let line: MKPolyline?
    let destination: CLLocationCoordinate2D?
    let destinationName: String

    var body: some MapContent {
        if let line {
            // A white casing under the blue line keeps it readable on dark and green map areas.
            MapPolyline(line)
                .stroke(Color.white.opacity(0.92), lineWidth: 11)
            MapPolyline(line)
                .stroke(Theme.route, lineWidth: 7)
        }
        if let destination {
            Marker(destinationName, systemImage: "flag.checkered", coordinate: destination)
                .tint(Color.red)
        }
    }
}

extension RouteMapContent {
    @MainActor
    init(route: RouteModel) {
        self.init(
            line: route.route?.polyline,
            destination: route.destination?.placemark.coordinate,
            destinationName: route.destinationName
        )
    }
}
