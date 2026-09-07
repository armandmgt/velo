import CoreLocation
import Testing
@testable import Velo

/// Framing the review screen's route preview. The awkward case is a recording
/// that never moved: its bounding box has no area, and asking a map to fit that
/// zooms to nonsense.
@Suite("RouteBounds")
struct RouteBoundsTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    @Test("nothing recorded is nothing to frame")
    func empty() {
        #expect(RouteBounds.framing(for: []) == .none)
    }

    @Test("a single fix is centred, not fitted")
    func singlePoint() {
        let framing = RouteBounds.framing(for: [coordinate(48.8566, 2.3522)])

        #expect(framing == .center(latitude: 48.8566, longitude: 2.3522))
    }

    @Test("a recording that never moved is centred on where it stood")
    func degenerate() {
        let still = Array(repeating: coordinate(48.8566, 2.3522), count: 40)

        let framing = RouteBounds.framing(for: still)

        #expect(framing == .center(latitude: 48.8566, longitude: 2.3522))
    }

    @Test("a real route is fitted to its bounding box")
    func box() {
        let route = [
            coordinate(48.8566, 2.3522),
            coordinate(48.8600, 2.3400),
            coordinate(48.8500, 2.3600),
        ]

        #expect(
            RouteBounds.framing(for: route)
                == .box(minLat: 48.8500, minLon: 2.3400, maxLat: 48.8600, maxLon: 2.3600)
        )
    }

    @Test("a route smaller than the minimum span is centred rather than fitted")
    func tinySpread() {
        // A few metres of GPS jitter while stationary must not fill the frame.
        let route = [
            coordinate(48.856600, 2.352200),
            coordinate(48.856601, 2.352201),
        ]

        guard case .center = RouteBounds.framing(for: route) else {
            Issue.record("expected jitter to be centred, not fitted")
            return
        }
    }
}
