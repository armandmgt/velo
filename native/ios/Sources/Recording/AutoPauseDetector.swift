import CoreLocation
import Foundation

/// Decides when a recording enters and leaves **pause automatique**.
///
/// Entering is deliberately slow (ten consecutive still seconds) and leaving is
/// instant,
/// because a late pause costs a few seconds of temps écoulé while a late resume
/// loses real track. Leaving keys on **displacement**, not on speed — a stationary
/// phone reports 0.3–0.8 m/s of Doppler noise, straddling the very threshold used
/// to enter, so a speed-based exit flaps at every traffic light.
///
/// Kept free of Core Data and of `RecordingController` so the hysteresis is
/// exercised directly by `AutoPauseDetectorTests`.
struct AutoPauseDetector {
    enum Outcome: Equatable {
        case none
        case shouldAutoPause
        case shouldAutoResume
    }

    /// Fixes at or above this (m/s) count as moving. Mirrors
    /// `RecordingStats.movingSpeedThreshold` — and so the server's
    /// `GpxExtractor::MOVING_SPEED_THRESHOLD`.
    static let stillSpeedThreshold: CLLocationSpeed = RecordingStats.movingSpeedThreshold
    /// How long the rider must read as still before we pause them (seconds).
    static let stillDuration: TimeInterval = 10
    /// How far from the pause anchor counts as genuinely moving again (metres).
    static let resumeDistance: CLLocationDistance = 15
    /// A measured speed this high (m/s, ~7 km/h) is unambiguous movement, far above
    /// the stationary-noise band. Resuming on it as well as on displacement matters
    /// because a paused recording drops its fixes: waiting to cover
    /// `resumeDistance` throws away the first seconds of the rider pulling away.
    static let resumeSpeed: CLLocationSpeed = 2.0
    /// Consecutive fixes further apart than this (seconds) say nothing about the
    /// span between them, so they cannot build a still run. Mirrors the spirit of
    /// `RecordingStats.pauseGapSeconds` in the distance accumulator.
    static let maxFixGap: TimeInterval = 5

    /// What the detector is currently watching for.
    private enum Phase {
        /// Recording, watching for stillness.
        case armed
        /// Auto-paused at `anchor`, watching for the rider to move away from it.
        case autoPaused(anchor: CLLocation)
        /// Recording after a manual **Reprendre**, which outranks the detector:
        /// nothing fires until the rider has genuinely left `anchor`.
        case suppressed(anchor: CLLocation)
        /// The rider paused by hand, or no recording is running. The detector
        /// stays silent — movement must not undo a pause someone asked for.
        case inactive
    }

    /// Whether pause automatique is switched on for this recording. Read once at
    /// Démarrer, so a ride records under the setting it started with.
    let isEnabled: Bool

    private var phase: Phase = .inactive
    /// When the current unbroken run of still fixes began.
    private var stillSince: Date?
    /// The previous fix, for gap detection and for anchoring a manual pause.
    private var lastFix: CLLocation?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Arm the detector for a fresh recording.
    mutating func reset() {
        phase = .armed
        stillSince = nil
        lastFix = nil
    }

    /// Fold in one fix — including the ones the recording drops while paused, which
    /// is exactly how the auto-resume is detected.
    mutating func consider(_ location: CLLocation) -> Outcome {
        guard isEnabled else { return .none }

        let previous = lastFix
        lastFix = location

        switch phase {
        case .inactive:
            return .none

        case .armed:
            // A negative speed is CoreLocation saying it could not measure one —
            // common while a fix settles, and *not* evidence of stillness. Only
            // positive evidence pauses a recording, so an unmeasurable fix breaks
            // the run rather than extending it.
            guard location.speed >= 0, location.speed < Self.stillSpeedThreshold else {
                stillSince = nil
                return .none
            }
            // A hole in the fix stream (backgrounding, a tunnel, re-acquisition)
            // leaves us with two isolated slow readings and no idea what happened
            // between them — the rider may have been moving the whole time. Start
            // the run over rather than counting the gap as stillness.
            if let previous, location.timestamp.timeIntervalSince(previous.timestamp) > Self.maxFixGap {
                stillSince = location.timestamp
                return .none
            }
            guard let since = stillSince else {
                stillSince = location.timestamp
                return .none
            }
            guard location.timestamp.timeIntervalSince(since) >= Self.stillDuration else { return .none }
            phase = .autoPaused(anchor: location)
            stillSince = nil
            return .shouldAutoPause

        case .autoPaused(let anchor):
            guard hasLeft(anchor, location) else { return .none }
            phase = .armed
            stillSince = nil
            return .shouldAutoResume

        case .suppressed(let anchor):
            guard hasLeft(anchor, location) else { return .none }
            phase = .armed
            stillSince = nil
            return .none
        }
    }

    /// Has the rider genuinely left `anchor`? Either they have covered ground, or
    /// they are measurably moving at a speed no stationary phone reports.
    private func hasLeft(_ anchor: CLLocation, _ location: CLLocation) -> Bool {
        if location.distance(from: anchor) > Self.resumeDistance { return true }
        return location.speed >= Self.resumeSpeed
    }

    /// The rider tapped **Reprendre**. From an automatic pause that suppresses the
    /// detector until they've actually moved — re-pausing someone who just asked to
    /// be recorded is the worst failure mode this feature has.
    mutating func userDidResume() {
        switch phase {
        case .autoPaused(let anchor):
            phase = .suppressed(anchor: anchor)
        default:
            // A manual pause deserves the same courtesy: someone who taps Reprendre
            // at a start line has said they want to be recorded, so don't pause them
            // again ten seconds later just because they haven't set off yet.
            phase = lastFix.map { .suppressed(anchor: $0) } ?? .armed
        }
        stillSince = nil
    }

    /// The rider tapped **Pause**. An explicit pause outranks the detector in the
    /// other direction too: no amount of movement may resume it.
    mutating func userDidPause() {
        phase = .inactive
        stillSince = nil
    }
}

// MARK: - Preference

extension AutoPauseDetector {
    private static let enabledKey = "recording.autoPauseEnabled"

    /// Whether pause automatique is switched on, stored per device like
    /// `Sport.lastUsed`. Defaults to **on** — the setting exists to let a rider
    /// turn it off, not to make them find it first.
    static var isEnabledPreference: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}
