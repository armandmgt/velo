// PROTOTYPE — throwaway (wayfinder #21). Raw MLNMapView in a representable, plus
// the gestures under test: long-press to add, tap or drag the line to insert, and
// MapLibre's own draggable annotations for the "SDK handles" variant.
import MapLibre
import Observation
import SwiftUI
import UIKit

/// The seam between the map and the SwiftUI overlay: converts coordinates to
/// screen points and ticks on every camera frame so overlay handles re-place.
@Observable
final class MapProjection {
    private(set) var tick = 0
    @ObservationIgnored weak var mapView: MLNMapView?

    func bump() { tick &+= 1 }

    func point(_ c: Coord) -> CGPoint {
        _ = tick
        guard let mapView else { return .zero }
        return mapView.convert(c.cl, toPointTo: mapView)
    }

    func coordinate(at p: CGPoint) -> Coord {
        guard let mapView else { return Coord(lng: 0, lat: 0) }
        return Coord(mapView.convert(p, toCoordinateFrom: mapView))
    }
}

struct PlannerMapView: UIViewRepresentable {
    let model: PlannerModel
    let projection: MapProjection
    var bottomInset: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(model: model, projection: projection) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        let config = MapConfig.current
        if let url = config.styleURL { map.styleURL = url }
        map.delegate = context.coordinator
        map.allowsTilting = false
        map.compassView.compassVisibility = .hidden
        map.showsUserLocation = true
        map.setCenter(CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), zoomLevel: 11, animated: false)
        context.coordinator.attach(to: map, accent: config.accentColor)
        projection.mapView = map
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        map.contentInset = UIEdgeInsets(top: 120, left: 24, bottom: bottomInset, right: 24)
        context.coordinator.sync()
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        let model: PlannerModel
        let projection: MapProjection
        private weak var map: MLNMapView?
        private var accent: UIColor = .orange
        private var routeSource: MLNShapeSource?
        private var bandSource: MLNShapeSource?
        private var syncedRoute: [Coord] = []
        private var syncedAnnotations: [Coord] = []
        private var syncedStyle: HandleStyle?
        private var annotations: [WaypointAnnotation] = []
        private var centeredOnUser = false
        private var linePan: UIPanGestureRecognizer!
        private var lineSlot: Int?

        /// Finger-sized: the web uses 8px around a 5px line; a thumb needs more.
        static let lineTolerance: CGFloat = 18
        static let handleRadius: CGFloat = 26

        init(model: PlannerModel, projection: MapProjection) {
            self.model = model
            self.projection = projection
        }

        func attach(to map: MLNMapView, accent: UIColor) {
            self.map = map
            self.accent = accent

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
            longPress.delegate = self
            map.addGestureRecognizer(longPress)

            let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
            tap.delegate = self
            map.addGestureRecognizer(tap)

            linePan = UIPanGestureRecognizer(target: self, action: #selector(onLinePan(_:)))
            linePan.delegate = self
            linePan.maximumNumberOfTouches = 1
            map.addGestureRecognizer(linePan)
            // The map's own pan waits for ours to fail, which it does at once
            // unless the touch started on the route line.
            for recognizer in map.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer && recognizer !== linePan {
                recognizer.require(toFail: linePan)
            }
        }

        // MARK: Sync model → map

        func sync() {
            guard let map, let routeSource, let bandSource else { return }
            if model.route != syncedRoute {
                syncedRoute = model.route
                routeSource.shape = model.route.count >= 2 ? polyline(model.route) : nil
                if model.pendingFit, model.route.count >= 2 {
                    fit(model.route)
                    DispatchQueue.main.async { self.model.pendingFit = false }
                }
            }
            bandSource.shape = band().map(polyline)

            if model.handleStyle != syncedStyle || (model.handleStyle == .sdk && model.waypoints != syncedAnnotations) {
                syncedStyle = model.handleStyle
                syncedAnnotations = model.waypoints
                map.removeAnnotations(annotations)
                annotations = []
                if model.handleStyle == .sdk {
                    annotations = model.waypoints.enumerated().map { WaypointAnnotation(index: $0.offset, coordinate: $0.element.cl) }
                    map.addAnnotations(annotations)
                }
            }
        }

        private func band() -> [Coord]? {
            guard let drag = model.dragPreview else { return nil }
            let w = model.waypoints
            var points: [Coord] = []
            if let i = drag.movingIndex {
                if i > 0 { points.append(w[i - 1]) }
                points.append(drag.coordinate)
                if i + 1 < w.count { points.append(w[i + 1]) }
            } else if let k = drag.insertAt {
                if k > 0 { points.append(w[k - 1]) }
                points.append(drag.coordinate)
                if k < w.count { points.append(w[k]) }
            }
            return points.count >= 2 ? points : nil
        }

        private func polyline(_ coords: [Coord]) -> MLNPolylineFeature {
            var cl = coords.map(\.cl)
            return MLNPolylineFeature(coordinates: &cl, count: UInt(cl.count))
        }

        private func fit(_ coords: [Coord]) {
            guard let map else { return }
            var cl = coords.map(\.cl)
            map.setVisibleCoordinates(&cl, count: UInt(cl.count), edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: true)
        }

        // MARK: Hit-tests in screen space

        private func distanceToLine(_ p: CGPoint) -> CGFloat {
            guard let map, model.route.count >= 2 else { return .infinity }
            let pts = model.route.map { map.convert($0.cl, toPointTo: map) }
            var best = CGFloat.infinity
            for i in 0..<(pts.count - 1) { best = min(best, segmentDistance(p, pts[i], pts[i + 1])) }
            return best
        }

        private func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }

        private func nearHandle(_ p: CGPoint) -> Bool {
            guard let map else { return false }
            return model.waypoints.contains { hypot(map.convert($0.cl, toPointTo: map).x - p.x, map.convert($0.cl, toPointTo: map).y - p.y) < Self.handleRadius }
        }

        // MARK: Gestures

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let map else { return false }
            let p = g.location(in: map)
            if g === linePan {
                return model.insertStyle == .drag && model.waypoints.count >= 2 && !nearHandle(p) && distanceToLine(p) < Self.lineTolerance
            }
            if g is UILongPressGestureRecognizer { return !nearHandle(p) }
            return true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            g !== linePan
        }

        @objc private func onLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.add(Coord(map.convert(g.location(in: map), toCoordinateFrom: map)))
        }

        @objc private func onTap(_ g: UITapGestureRecognizer) {
            guard let map else { return }
            let p = g.location(in: map)
            if nearHandle(p) { return }
            if model.insertStyle == .tap, model.waypoints.count >= 2, distanceToLine(p) < Self.lineTolerance {
                let c = Coord(map.convert(p, toCoordinateFrom: map))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.insert(at: model.insertionIndex(for: c), c)
                return
            }
            model.selectedIndex = nil
        }

        @objc private func onLinePan(_ g: UIPanGestureRecognizer) {
            guard let map else { return }
            let c = Coord(map.convert(g.location(in: map), toCoordinateFrom: map))
            switch g.state {
            case .began:
                lineSlot = model.insertionIndex(for: c)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.dragPreview = DragPreview(movingIndex: nil, insertAt: lineSlot, coordinate: c)
            case .changed:
                model.dragPreview = DragPreview(movingIndex: nil, insertAt: lineSlot, coordinate: c)
            case .ended:
                if let slot = lineSlot { model.insert(at: slot, c) }
                model.dragPreview = nil
                lineSlot = nil
            default:
                model.dragPreview = nil
                lineSlot = nil
            }
        }

        // MARK: MLNMapViewDelegate

        func mapView(_ map: MLNMapView, didFinishLoading style: MLNStyle) {
            let route = MLNShapeSource(identifier: "planner-route", shape: nil, options: nil)
            style.addSource(route)
            routeSource = route
            let casing = MLNLineStyleLayer(identifier: "planner-route-casing", source: route)
            casing.lineColor = NSExpression(forConstantValue: UIColor.white)
            casing.lineWidth = NSExpression(forConstantValue: 9)
            casing.lineCap = NSExpression(forConstantValue: "round")
            casing.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(casing)
            let line = MLNLineStyleLayer(identifier: "planner-route-line", source: route)
            line.lineColor = NSExpression(forConstantValue: accent)
            line.lineWidth = NSExpression(forConstantValue: 5)
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(line)

            let band = MLNShapeSource(identifier: "planner-band", shape: nil, options: nil)
            style.addSource(band)
            bandSource = band
            let bandLine = MLNLineStyleLayer(identifier: "planner-band-line", source: band)
            bandLine.lineColor = NSExpression(forConstantValue: accent)
            bandLine.lineWidth = NSExpression(forConstantValue: 3)
            bandLine.lineDashPattern = NSExpression(forConstantValue: [2, 1.5])
            style.addLayer(bandLine)

            syncedRoute = []
            observe()
        }

        /// Re-sync whenever anything `sync` reads on the model changes.
        private func observe() {
            withObservationTracking { sync() } onChange: { [weak self] in
                DispatchQueue.main.async { self?.observe() }
            }
        }

        func mapView(_ map: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            guard !centeredOnUser, model.waypoints.isEmpty, let c = userLocation?.location?.coordinate else { return }
            centeredOnUser = true
            map.setCenter(c, zoomLevel: 13, animated: false)
        }

        func mapViewRegionIsChanging(_ map: MLNMapView) { projection.bump() }
        func mapView(_ map: MLNMapView, regionDidChangeAnimated animated: Bool) { projection.bump() }
        func mapViewDidFinishRenderingFrame(_ map: MLNMapView, fullyRendered: Bool) { projection.bump() }

        func mapView(_ map: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let wp = annotation as? WaypointAnnotation else { return nil }
            let view = WaypointAnnotationView(annotation: wp, accent: accent)
            view.onDrag = { [weak self, weak map] state, view in
                guard let self, let map else { return }
                let c = Coord(map.convert(view.center, toCoordinateFrom: map))
                switch state {
                case .dragging: self.model.dragPreview = DragPreview(movingIndex: wp.index, insertAt: nil, coordinate: c)
                case .ending:
                    self.model.dragPreview = nil
                    self.model.move(wp.index, to: Coord(wp.coordinate))
                case .canceling: self.model.dragPreview = nil
                default: break
                }
            }
            return view
        }

        func mapView(_ map: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let wp = annotation as? WaypointAnnotation else { return }
            model.selectedIndex = wp.index
            map.deselectAnnotation(annotation, animated: false)
        }
    }
}

final class WaypointAnnotation: MLNPointAnnotation {
    let index: Int
    init(index: Int, coordinate: CLLocationCoordinate2D) {
        self.index = index
        super.init()
        self.coordinate = coordinate
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// MapLibre-managed draggable handle: the SDK needs a press-and-hold before it
/// lets go of the map pan and starts dragging.
final class WaypointAnnotationView: MLNAnnotationView {
    var onDrag: ((MLNAnnotationViewDragState, MLNAnnotationView) -> Void)?

    init(annotation: WaypointAnnotation, accent: UIColor) {
        super.init(reuseIdentifier: nil)
        self.annotation = annotation
        frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        isDraggable = true
        backgroundColor = annotation.index == 0 ? .white : accent
        layer.cornerRadius = 13
        layer.borderWidth = 3
        layer.borderColor = (annotation.index == 0 ? accent : .white).cgColor
        let label = UILabel(frame: bounds)
        label.text = "\(annotation.index + 1)"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.textColor = annotation.index == 0 ? accent : .white
        addSubview(label)
        isAccessibilityElement = true
        accessibilityIdentifier = "planner-waypoint-\(annotation.index + 1)"
    }

    required init?(coder: NSCoder) { fatalError() }

    override var center: CGPoint {
        didSet { if dragState == .dragging { onDrag?(.dragging, self) } }
    }

    override func setDragState(_ dragState: MLNAnnotationViewDragState, animated: Bool) {
        super.setDragState(dragState, animated: animated)
        switch dragState {
        case .starting:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        case .ending, .canceling:
            transform = .identity
            onDrag?(dragState, self)
        default: break
        }
    }
}
