import CoreLocation

/// Drives Core Location for an in-progress recording (#41, S2 — #50; S3 — #51).
///
/// Deliberately a standalone object, *not* part of `RecordingViewController`:
/// it owns the `CLLocationManager` and streams fixes to its delegate. S3 lifted
/// ownership to `RecordingController` (the longer-lived owner) and moved point
/// storage into Core Data there — so this object is now purely the Core Location
/// pipe: it forwards every accepted fix and holds no points itself. Nothing here
/// touches UIKit.
///
/// **Permissions:** While-Using ("When In Use") *only* — we never request
/// "Always". With `allowsBackgroundLocationUpdates` + the `location` background
/// mode (Info.plist), While-Using already keeps updates flowing while the app is
/// backgrounded *during* a recording (the blue status-bar pill). "Always" would
/// only add background relaunch after termination, which we don't want.
final class LocationRecorder: NSObject {
    /// Authorization as the UI cares about it — collapses the CLAuthorization
    /// cases into "ask / good to go / blocked".
    enum Status {
        case notDetermined
        case authorized
        case denied
    }

    weak var delegate: LocationRecorderDelegate?

    private let manager = CLLocationManager()

    /// Set between `start()` and `stop()`. Guards the authorization callback so a
    /// late grant (user tapped "Allow" after we asked) only starts updates if a
    /// recording is actually in progress.
    private var isRecording = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        // Deliver every fix the GPS produces (~1 Hz) rather than gating on
        // distance — matches the ~1 Hz sampling the S0 GPX contract expects.
        manager.distanceFilter = kCLDistanceFilterNone
        // We decide when a recording is paused; don't let iOS auto-pause us.
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Lifecycle

    /// Begin (or resume) streaming, requesting permission if we've never asked.
    func start() {
        isRecording = true
        applyAuthorization(manager.authorizationStatus)
    }

    func stop() {
        isRecording = false
        manager.stopUpdatingLocation()
    }

    // MARK: - Authorization

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            // The only prompt we ever show. By decision we do NOT escalate to
            // `requestAlwaysAuthorization()`.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            delegate?.locationRecorder(self, didChange: .authorized)
            manager.startUpdatingLocation()
        case .denied, .restricted:
            delegate?.locationRecorder(self, didChange: .denied)
        @unknown default:
            break
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRecording else { return }
        applyAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 {
            // A negative `horizontalAccuracy` flags an invalid fix — drop it.
            delegate?.locationRecorder(self, didUpdate: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. `kCLErrorLocationUnknown` before the first fix
        // in the simulator) are expected; CoreLocation keeps trying, so just log.
        NSLog("[LocationRecorder] location update failed: \(error.localizedDescription)")
    }
}

/// Updates from a `LocationRecorder`. Mirrors the codebase's delegate style
/// (e.g. `NavigatorDelegate`) rather than reaching for Combine.
protocol LocationRecorderDelegate: AnyObject {
    func locationRecorder(_ recorder: LocationRecorder, didChange status: LocationRecorder.Status)
    func locationRecorder(_ recorder: LocationRecorder, didUpdate location: CLLocation)
}
