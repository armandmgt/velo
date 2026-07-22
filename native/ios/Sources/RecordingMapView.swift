import CoreLocation
import HotwireNative
import MapLibre
import UIKit

/// The full-bleed live map behind the recording screen (redesign per
/// `Recording.dc.html`).
///
/// Shows the route trace as it's recorded — an accent line with a white casing
/// underneath, mirroring the web `map_controller.js` — and a pulsing position
/// marker. The marker/trace are fed from our own GPS fixes (see
/// `RecordingViewController`), **not** MapLibre's location engine, so we keep the
/// single `LocationRecorder` owner and the While-Using-only posture.
///
/// The basemap style URL + accent colour come from `settings.map` in the path
/// configuration (`ConfigurationsController`), read via `MapConfig` — the native
/// shell has no webview here to bridge them over.
final class RecordingMapView: UIView {
    private let mapView = MLNMapView(frame: .zero)
    private let accentColor: UIColor
    private let marker = MLNPointAnnotation()
    private var hasMarker = false

    private var routeSource: MLNShapeSource?
    private var route: [CLLocationCoordinate2D] = []
    private var styleLoaded = false

    /// Deferred camera target if a fix arrives before the style finishes loading.
    private var pendingCenter: CLLocationCoordinate2D?
    /// Space the dock occupies at the bottom, so the followed position sits above it.
    private var bottomInset: CGFloat = 320

    init() {
        let config = MapConfig.current
        accentColor = config.accentColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.backgroundColor = .secondarySystemBackground
        mapView.delegate = self
        mapView.allowsTilting = false
        mapView.compassView.compassVisibility = .hidden
        // The recording screen owns the camera (follow mode); scroll/zoom stay on
        // for the user, but attribution must remain visible per the tile licence.
        if let url = config.styleURL { mapView.styleURL = url }

        addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Public API

    /// Replace the whole trace (used to seed from an in-progress recording, then on
    /// every appended fix while recording).
    func setRoute(_ coordinates: [CLLocationCoordinate2D]) {
        route = coordinates
        guard styleLoaded, let source = routeSource else { return }
        if coordinates.count >= 2 {
            source.shape = MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
        } else {
            source.shape = nil
        }
    }

    /// Move the pulsing position marker to the latest fix (also while armed/paused).
    func setPosition(_ coordinate: CLLocationCoordinate2D) {
        marker.coordinate = coordinate
        if !hasMarker {
            mapView.addAnnotation(marker)
            hasMarker = true
        }
    }

    /// Ease the camera to keep `coordinate` visible above the dock.
    func follow(_ coordinate: CLLocationCoordinate2D) {
        guard styleLoaded else { pendingCenter = coordinate; return }
        applyContentInset()
        let zoom = max(mapView.zoomLevel, 15)
        mapView.setCenter(coordinate, zoomLevel: zoom, animated: true)
    }

    /// Dim the trace + marker while paused, hide the trace while idle (mirrors the
    /// design's `applyMapMode`).
    func setMode(paused: Bool, idle: Bool) {
        guard styleLoaded,
              let line = mapView.style?.layer(withIdentifier: "route-line") as? MLNLineStyleLayer else { return }
        line.lineOpacity = NSExpression(forConstantValue: idle ? 0 : (paused ? 0.4 : 0.95))
        if let view = mapView.view(for: marker) {
            view.alpha = paused ? 0.55 : 1
        }
    }

    /// The dock height changed (collapsed ⇄ expanded); re-centre with new padding.
    func setBottomInset(_ inset: CGFloat) {
        bottomInset = inset
        guard styleLoaded else { return }
        applyContentInset()
        if let last = route.last ?? pendingCenter { mapView.setCenter(last, animated: true) }
    }

    private func applyContentInset() {
        mapView.contentInset = UIEdgeInsets(top: 96, left: 24, bottom: bottomInset, right: 24)
    }
}

// MARK: - MLNMapViewDelegate

extension RecordingMapView: MLNMapViewDelegate {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        // White casing under the accent line, matching the web route styling.
        let source = MLNShapeSource(identifier: "route", shape: nil, options: nil)
        style.addSource(source)
        routeSource = source

        let casing = MLNLineStyleLayer(identifier: "route-casing", source: source)
        casing.lineColor = NSExpression(forConstantValue: UIColor.white)
        casing.lineWidth = NSExpression(forConstantValue: 8)
        casing.lineOpacity = NSExpression(forConstantValue: 0.9)
        casing.lineCap = NSExpression(forConstantValue: "round")
        casing.lineJoin = NSExpression(forConstantValue: "round")
        style.addLayer(casing)

        let line = MLNLineStyleLayer(identifier: "route-line", source: source)
        line.lineColor = NSExpression(forConstantValue: accentColor)
        line.lineWidth = NSExpression(forConstantValue: 5)
        line.lineCap = NSExpression(forConstantValue: "round")
        line.lineJoin = NSExpression(forConstantValue: "round")
        style.addLayer(line)

        styleLoaded = true
        setRoute(route)
        applyContentInset()
        if let center = pendingCenter ?? route.last {
            mapView.setCenter(center, zoomLevel: 15, animated: false)
            pendingCenter = nil
        }
    }

    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        guard annotation === marker else { return nil }
        let identifier = "velo-position"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? PositionMarkerView
            ?? PositionMarkerView(reuseIdentifier: identifier, color: accentColor)
        return view
    }
}

// MARK: - PositionMarkerView

/// The current-position marker: a white-ringed accent dot with an expanding
/// pulse halo (mirrors the design's `.velo-pos`).
private final class PositionMarkerView: MLNAnnotationView {
    init(reuseIdentifier: String, color: UIColor) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        isEnabled = false // not tappable; purely indicative

        let pulse = CALayer()
        pulse.frame = bounds
        pulse.cornerRadius = 11
        pulse.backgroundColor = color.cgColor
        layer.addSublayer(pulse)

        let dot = CALayer()
        dot.frame = CGRect(x: 2, y: 2, width: 18, height: 18)
        dot.cornerRadius = 9
        dot.backgroundColor = color.cgColor
        dot.borderWidth = 3
        dot.borderColor = UIColor.white.cgColor
        dot.shadowColor = UIColor.black.cgColor
        dot.shadowOpacity = 0.35
        dot.shadowRadius = 2
        dot.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(dot)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.9
        scale.toValue = 2.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.8
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.add(group, forKey: "pulse")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - MapConfig

/// Map settings delivered by the server through the path configuration's
/// `settings.map` block (see `ConfigurationsController`). Read defensively — if the
/// server config hasn't loaded yet the map simply has no style until it does.
struct MapConfig {
    let styleURL: URL?
    let accentColor: UIColor

    static let fallbackAccent = UIColor(red: 0.965, green: 0.60, blue: 0.0, alpha: 1) // #f69900

    static var current: MapConfig {
        let settings = Hotwire.config.pathConfiguration.settings
        let url = (settings["map_style_url"] as? String).flatMap(URL.init(string:))
        let accent = (settings["map_accent"] as? String).flatMap(colorFromHex) ?? fallbackAccent
        return MapConfig(styleURL: url, accentColor: accent)
    }

    private static func colorFromHex(_ hex: String) -> UIColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
