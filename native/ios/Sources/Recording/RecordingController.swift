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
/// State machine: `idle → recording ⇄ paused/autoPaused → stopped(→ idle)`. Fixes
/// are only persisted while `.recording`; both paused states drop them (and break
/// the distance segment so the paused gap isn't counted).
///
/// `.autoPaused` is pause automatique — identical in effect to `.paused`,
/// differing only in who triggered it and who may end it. See
/// `docs/adr/0002-auto-pause-is-a-distinct-persisted-state.md`.
final class RecordingController: NSObject {
    static let shared = RecordingController()

    enum State {
        case idle
        case recording
        case paused
        case autoPaused

        var isActive: Bool { self != .idle }

        /// Paused either way — the clock is frozen and fixes are dropped. The UI
        /// renders the two identically apart from the state pill, which names
        /// which kind of pause it is.
        var isPaused: Bool { self == .paused || self == .autoPaused }
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

    /// The sport the recording uploads as (S4 — #52). Chosen on the recording
    /// screen; defaults to the last-used sport and becomes the new last-used when
    /// a recording starts. Held here (not on the VC) so it survives Fermer/reopen
    /// while the recording keeps running.
    var sport: Sport = .lastUsed

    /// Current lap ordinal (1-based) while active, else 0. Laps are markers (S3).
    var currentLap: Int { Int(session?.lapCount ?? 0) }

    /// Lives here until the review page reports the upload committed, or the
    /// rider discards it: `stop()` releases the controller's own reference, and
    /// the review is a web page rather than a VC that could hold one.
    var pendingHandoff: RecordingHandoff?

    /// Points persisted in the current session so far (debug readout / stats).
    private(set) var pointCount: Int = 0

    /// Point count of an active session recovered from a previous launch (kill
    /// recovery). Read-only here; the S5 resume/finish prompt consumes it.
    private(set) var recoveredPointCount: Int = 0

    private let recorder = LocationRecorder()
    private let store = RecordingStore()

    /// Watches the fix stream for pause automatique. Inert until `start()` arms it,
    /// and configured from the preference as it stood at Démarrer, so a ride
    /// records under the setting it began with.
    private var detector = AutoPauseDetector(isEnabled: false)

    private var session: RecordingSession?
    private var accumulator = RecordingStatsAccumulator()
    private var lastFixSpeed: CLLocationSpeed = 0
    /// Wall-clock second of the last persisted fix, to keep at most one point per
    /// second (the ~1 Hz contract; see `locationRecorder(_:didUpdate:)`).
    private var lastPersistedSecond: TimeInterval?

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
        // Remember this sport so the next recording's picker defaults to it.
        Sport.lastUsed = sport

        session = store.createSession()
        pointCount = 0
        accumulator = RecordingStatsAccumulator()
        lastFixSpeed = 0
        lastPersistedSecond = nil
        accumulatedElapsed = 0
        stretchStart = Date()
        detector = AutoPauseDetector(isEnabled: AutoPauseDetector.isEnabledPreference)
        detector.reset()

        recorder.start()
        startTicker()
        state = .recording
        emitStats()
    }

    /// The rider tapped **Pause**. Also the way out of an automatic pause into a
    /// manual one: an explicit pause outranks the detector, so no amount of
    /// movement will resume it.
    func pause() {
        guard state == .recording || state == .autoPaused else { return }
        detector.userDidPause()
        enterPause(.paused)
    }

    /// The rider tapped **Reprendre**, from either kind of pause. From an
    /// automatic one this also disarms the detector until they have genuinely
    /// moved — re-pausing someone who just asked to be recorded is the worst
    /// failure mode this feature has.
    func resume() {
        guard state.isPaused else { return }
        detector.userDidResume()
        leavePause()
    }

    /// Ten still seconds: enter pause automatique (ADR 0002).
    private func autoPause() {
        guard state == .recording else { return }
        enterPause(.autoPaused)
    }

    /// Fifteen metres from where we auto-paused: back to recording.
    private func autoResume() {
        guard state == .autoPaused else { return }
        leavePause()
    }

    private func enterPause(_ target: State) {
        accumulatedElapsed = elapsed
        stretchStart = nil
        lastFixSpeed = 0
        // Break the segment so the paused gap adds neither distance nor moving time.
        accumulator.breakSegment()
        stopTicker()
        session?.recordingState = target == .autoPaused ? .autoPaused : .paused
        store.save()
        state = target
        emitStats()
    }

    private func leavePause() {
        stretchStart = Date()
        startTicker()
        session?.recordingState = .recording
        store.save()
        state = .recording
        emitStats()
    }

    /// Close the running Tour and open the next one (S12a — #60).
    ///
    /// Snapshots the cumulative totals *before* bumping the counter, so the row
    /// closes the lap that was running; `LapSplits` differences consecutive rows
    /// into splits. Only available while actually recording — Tour is hidden in
    /// both paused states, so a zero-distance lap can't be minted at a red light.
    func markLap() {
        guard state == .recording, let session else { return }
        store.appendLap(
            to: session,
            ordinal: session.lapCount,
            endedAt: Date(),
            cumulativeDistance: accumulator.distance,
            cumulativeElapsed: elapsed
        )
        session.lapCount += 1
        store.save()
    }

    /// Splits for the recording in progress: one per Tour, the last in progress.
    var lapSplits: [LapSplit] {
        let stats = currentStats
        return LapSplits.splits(
            boundaries: session?.lapBoundaries ?? [],
            totalDistance: stats.distance,
            totalElapsed: stats.elapsed
        )
    }

    /// Finalize the recording: mark it stopped, stop streaming, and return the
    /// finalized session so the caller can serialize and upload it (S4 — #52).
    /// The session stays in the store until the upload succeeds (`discard`).
    @discardableResult
    func stop() -> RecordingSession? {
        guard isActive, let finished = session else { return nil }
        // Snapshot before the clock below resets it.
        let handoff = RecordingHandoff(session: finished, stats: currentStats, sport: sport)
        finished.recordingState = .stopped
        store.save()
        stopTicker()
        recorder.stop()
        // A fresh detector starts inert, so no fix can move a finished recording.
        detector = AutoPauseDetector(isEnabled: false)
        session = nil
        accumulatedElapsed = 0
        stretchStart = nil
        state = .idle
        pendingHandoff = handoff
        return finished
    }

    func discard(_ session: RecordingSession) {
        if pendingHandoff?.session === session {
            pendingHandoff = nil
        }
        store.delete(session)
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

    /// The current session's recorded points as map coordinates, oldest-first.
    /// Used to seed the live trace when the recording screen is reopened onto an
    /// in-progress recording (the map view is recreated but the route persists).
    var routeCoordinates: [CLLocationCoordinate2D] {
        (session?.orderedPoints ?? []).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}

// MARK: - LocationRecorderDelegate

extension RecordingController: LocationRecorderDelegate {
    func locationRecorder(_ recorder: LocationRecorder, didChange status: LocationRecorder.Status) {
        delegate?.recordingController(self, didChangeAuthorization: status)
    }

    func locationRecorder(_ recorder: LocationRecorder, didUpdate location: CLLocation) {
        // Every fix feeds the detector, including the ones a paused recording drops
        // — watching them is exactly how the auto-resume is spotted (ADR 0002).
        switch detector.consider(location) {
        case .shouldAutoPause: autoPause()
        case .shouldAutoResume: autoResume()
        case .none: break
        }

        // Armed (idle) or paused: surface the fix for the debug readout, but don't
        // record it.
        guard state == .recording, let session else {
            delegate?.recordingController(self, didReceiveFix: location, pointCount: pointCount)
            return
        }

        // Keep at most one fix per wall-clock second (the ~1 Hz contract, S0 §2).
        // `distanceFilter = kCLDistanceFilterNone` can deliver sub-second bursts;
        // since the GPX emits whole-second `<time>`s, two points in the same second
        // would carry identical timestamps and collide on the server's unique
        // `recorded_at`. Surface the fix in the readout but don't persist it.
        let second = location.timestamp.timeIntervalSince1970.rounded(.down)
        guard second != lastPersistedSecond else {
            delegate?.recordingController(self, didReceiveFix: location, pointCount: pointCount)
            return
        }
        lastPersistedSecond = second

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
