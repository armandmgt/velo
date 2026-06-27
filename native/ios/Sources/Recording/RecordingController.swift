import CoreLocation
import Foundation

extension Notification.Name {
    /// Posted whenever the recording becomes active/idle (or pauses/resumes), so
    /// coarse observers — the tab-bar Record button — can refresh. Mirrors the
    /// `.didSignIn` NotificationCenter pattern in `SceneDelegate`.
    static let recordingStateDidChange = Notification.Name("RecordingStateDidChange")
}

/// The long-lived owner of an in-progress recording (#41, S3 — #51).
///
/// This is the "longer-lived owner" the S2 comments anticipated: it owns the
/// `LocationRecorder` and the Core Data `RecordingStore`, so a recording outlives
/// any one `RecordingViewController` — **Fermer** can leave the screen while GPS
/// keeps streaming and points keep persisting. A singleton because exactly one
/// recording exists at a time and three places share it: the recording screen
/// (live stats), the tab-bar button (active/idle), and launch (kill recovery).
///
/// State machine: `idle → recording ⇄ paused → stopped(→ idle)`. Fixes are only
/// persisted while `.recording`; `.paused` drops them (and breaks the distance
/// segment so the paused gap isn't counted).
final class RecordingController: NSObject {
    static let shared = RecordingController()

    enum State {
        case idle
        case recording
        case paused

        var isActive: Bool { self != .idle }
    }

    weak var delegate: RecordingControllerDelegate?

    private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            delegate?.recordingController(self, didChangeState: state)
            NotificationCenter.default.post(name: .recordingStateDidChange, object: self)
        }
    }

    var isActive: Bool { state.isActive }

    /// Current lap ordinal (1-based) while active, else 0. Laps are markers (S3).
    var currentLap: Int { Int(session?.lapCount ?? 0) }

    /// Points persisted in the current session so far (debug readout / stats).
    private(set) var pointCount: Int = 0

    /// Point count of an active session recovered from a previous launch (kill
    /// recovery). Read-only here; the S5 resume/finish prompt consumes it.
    private(set) var recoveredPointCount: Int = 0

    private let recorder = LocationRecorder()
    private let store = RecordingStore()

    private var session: RecordingSession?
    private var accumulator = RecordingStatsAccumulator()
    private var lastFixSpeed: CLLocationSpeed = 0

    // Elapsed clock: wall-clock recording time minus paused stretches.
    private var accumulatedElapsed: TimeInterval = 0
    private var stretchStart: Date?
    private var ticker: Timer?

    private override init() {
        super.init()
        recorder.delegate = self
        // Kill recovery: surface any orphaned active session's point count. We do
        // NOT resume it (the resume/finish prompt is S5) — the data simply stays
        // in the store, which is the S3 acceptance.
        if let orphan = store.activeSession() {
            recoveredPointCount = orphan.orderedPoints.count
            NSLog("[RecordingController] recovered active session with \(recoveredPointCount) points")
        }
    }

    // MARK: - Screen readiness

    /// Begin streaming GPS for readiness ("GPS prêt") without recording. Called
    /// when the screen appears; harmless (idempotent) if a recording is already
    /// in progress.
    func arm() {
        recorder.start()
    }

    /// Stop the readiness stream when the screen leaves — but only if no recording
    /// is in progress (otherwise GPS must keep flowing in the background).
    func disarmIfIdle() {
        guard !isActive else { return }
        recorder.stop()
    }

    // MARK: - Recording controls

    /// Start a fresh recording.
    func start() {
        guard state == .idle else { return }
        // Preserve the single-active invariant: finalize any orphan recovered from
        // a kill before opening a new session (S5 will prompt instead of dropping).
        if let orphan = store.activeSession() {
            orphan.recordingState = .stopped
            store.save()
        }
        recoveredPointCount = 0

        session = store.createSession()
        pointCount = 0
        accumulator = RecordingStatsAccumulator()
        lastFixSpeed = 0
        accumulatedElapsed = 0
        stretchStart = Date()

        recorder.start()
        startTicker()
        state = .recording
        emitStats()
    }

    func pause() {
        guard state == .recording else { return }
        accumulatedElapsed = elapsed
        stretchStart = nil
        lastFixSpeed = 0
        // Break the segment so the paused gap adds neither distance nor moving time.
        accumulator.breakSegment()
        stopTicker()
        session?.recordingState = .paused
        store.save()
        state = .paused
        emitStats()
    }

    func resume() {
        guard state == .paused else { return }
        stretchStart = Date()
        startTicker()
        session?.recordingState = .recording
        store.save()
        state = .recording
        emitStats()
    }

    /// Mark a lap boundary — a marker for now (S3). Bumps the session's lap
    /// counter; subsequent points inherit the new ordinal.
    func markLap() {
        guard isActive, let session else { return }
        session.lapCount += 1
        store.save()
    }

    /// Finalize the recording: mark it stopped and stop streaming.
    func stop() {
        guard isActive else { return }
        session?.recordingState = .stopped
        store.save()
        stopTicker()
        recorder.stop()
        session = nil
        accumulatedElapsed = 0
        stretchStart = nil
        state = .idle
    }

    // MARK: - Elapsed clock

    private var elapsed: TimeInterval {
        var total = accumulatedElapsed
        if let stretchStart { total += Date().timeIntervalSince(stretchStart) }
        return total
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.emitStats()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func emitStats() {
        delegate?.recordingController(self, didUpdate: currentStats)
    }

    var currentStats: RecordingStats {
        accumulator.snapshot(elapsed: elapsed, currentSpeed: lastFixSpeed)
    }
}

// MARK: - LocationRecorderDelegate

extension RecordingController: LocationRecorderDelegate {
    func locationRecorder(_ recorder: LocationRecorder, didChange status: LocationRecorder.Status) {
        delegate?.recordingController(self, didChangeAuthorization: status)
    }

    func locationRecorder(_ recorder: LocationRecorder, didUpdate location: CLLocation) {
        // Armed (idle) or paused: surface the fix for the debug readout, but don't
        // record it.
        guard state == .recording, let session else {
            delegate?.recordingController(self, didReceiveFix: location, pointCount: pointCount)
            return
        }

        let segmentSpeed = accumulator.add(location)
        lastFixSpeed = location.speed >= 0 ? location.speed : segmentSpeed
        let elevation = location.verticalAccuracy >= 0 ? location.altitude : nil

        store.appendPoint(
            to: session,
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: elevation,
            speed: segmentSpeed,
            horizontalAccuracy: location.horizontalAccuracy,
            lap: session.lapCount
        )
        pointCount += 1

        emitStats()
        delegate?.recordingController(self, didReceiveFix: location, pointCount: pointCount)
    }
}

/// Updates from a `RecordingController`. Same delegate style as
/// `LocationRecorderDelegate` — no Combine.
protocol RecordingControllerDelegate: AnyObject {
    func recordingController(_ controller: RecordingController, didChangeAuthorization status: LocationRecorder.Status)
    func recordingController(_ controller: RecordingController, didChangeState state: RecordingController.State)
    func recordingController(_ controller: RecordingController, didUpdate stats: RecordingStats)
    func recordingController(_ controller: RecordingController, didReceiveFix location: CLLocation, pointCount: Int)
}
