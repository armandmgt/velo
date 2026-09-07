import CoreLocation
import Foundation

/// How the review screen's map should frame a recorded route (S12a — #60).
enum RouteFraming: Equatable {
    /// Nothing was recorded — leave the camera alone.
    case none
    /// A single position, or a box too small to be worth fitting.
    case center(latitude: Double, longitude: Double)
    /// A real route, to be fitted with padding.
    case box(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double)
}

enum RouteBounds {
    /// Below this span (degrees, ~1 m) a route is jitter, not a shape. Fitting it
    /// would zoom the preview to street-furniture scale.
    static let minimumSpan = 0.00001

    static func framing(for coordinates: [CLLocationCoordinate2D]) -> RouteFraming {
        guard let first = coordinates.first else { return .none }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return .none }

        guard maxLat - minLat > minimumSpan || maxLon - minLon > minimumSpan else {
            return .center(latitude: first.latitude, longitude: first.longitude)
        }
        return .box(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon)
    }
}
