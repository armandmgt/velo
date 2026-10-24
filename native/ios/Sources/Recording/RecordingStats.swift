import CoreLocation
import Foundation

/// Live, derived stats for an in-progress recording.
///
/// Reuses the server-side `GpxExtractor` conventions so on-device numbers match
/// what the eventual upload would compute:
/// - distance accumulates the geodesic gap between consecutive fixes
///   (`CLLocation.distance(from:)` — Haversine-equivalent);
/// - a segment only counts toward *moving* time when its speed clears
///   `movingSpeedThreshold` and the gap is under `pauseGapSeconds`;
/// - average speed is distance over moving time (not wall-clock).
///
/// The totals are accumulated incrementally by `RecordingController` (O(1) per
/// fix) and read into this value type for display.
struct RecordingStats {
    /// Segments slower than this (m/s) don't count toward moving time. Mirrors
    /// `GpxExtractor::MOVING_SPEED_THRESHOLD`.
    static let movingSpeedThreshold: CLLocationSpeed = 0.5
    /// Segments spanning a longer gap (seconds) are treated as paused recording.
    /// Mirrors `GpxExtractor::PAUSE_GAP_SECONDS`.
    static let pauseGapSeconds: TimeInterval = 30

    /// Temps écoulé: wall-clock recording time, excluding paused stretches
    /// (seconds). The clock the rider watches, and the one that times a Tour.
    var elapsed: TimeInterval = 0
    /// Durée de déplacement: the stricter, speed-gated clock the server will
    /// store as the Activity's `active_time`. Shown beside temps écoulé on the
    /// review screen so the two numbers are never confused for each other.
    var movingTime: TimeInterval = 0
    /// Total distance over the ground (meters).
    var distance: CLLocationDistance = 0
    /// Latest instantaneous speed (m/s), or 0 when stationary/unknown.
    var currentSpeed: CLLocationSpeed = 0
    /// Distance / moving time (m/s); 0 until the first moving segment.
    var averageSpeed: CLLocationSpeed = 0

    static let zero = RecordingStats()
}

/// Running totals folded over the fix stream. Kept separate from the displayed
/// `RecordingStats` so the controller can mutate it in place per fix.
struct RecordingStatsAccumulator {
    private(set) var distance: CLLocationDistance = 0
    private(set) var movingSeconds: TimeInterval = 0
    private(set) var lastLocation: CLLocation?

    /// Fold one accepted fix in, returning the segment speed (for the per-point
    /// `speed` we persist). Distance/moving-time follow the GpxExtractor rules.
    mutating func add(_ location: CLLocation) -> CLLocationSpeed {
        defer { lastLocation = location }
        guard let previous = lastLocation else { return max(location.speed, 0) }

        let segment = location.distance(from: previous)
        let dt = location.timestamp.timeIntervalSince(previous.timestamp)
        distance += segment

        guard dt > 0 else { return max(location.speed, 0) }
        let segmentSpeed = segment / dt
        if segmentSpeed >= RecordingStats.movingSpeedThreshold, dt <= RecordingStats.pauseGapSeconds {
            movingSeconds += dt
        }
        // Prefer CoreLocation's Doppler speed when valid; fall back to the
        // position-derived segment speed (matching how GPX speed is computed).
        return location.speed >= 0 ? location.speed : segmentSpeed
    }

    /// Drop the running segment anchor so the next fix starts fresh — used on
    /// pause so the paused gap contributes neither distance nor moving time.
    mutating func breakSegment() {
        lastLocation = nil
    }

    /// Carry on from totals a recording already stored. There is no segment
    /// anchor, so the first fix after this adds nothing: a restored recording is
    /// paused, and the span the app was dead must not count as ridden.
    init(distance: CLLocationDistance, movingSeconds: TimeInterval) {
        self.distance = distance
        self.movingSeconds = movingSeconds
    }

    init() {}

    /// Fold stored fixes in order, ending without an anchor like a paused
    /// recording. Pauses leave no trace in the points, so a gap a pause skipped
    /// counts as ridden here where live folding broke the segment instead.
    static func replaying(_ fixes: [CLLocation]) -> RecordingStatsAccumulator {
        var accumulator = RecordingStatsAccumulator()
        for fix in fixes { _ = accumulator.add(fix) }
        accumulator.breakSegment()
        return accumulator
    }

    /// Snapshot for display. `elapsed` is supplied by the controller's clock so
    /// it keeps ticking between fixes.
    func snapshot(elapsed: TimeInterval, currentSpeed: CLLocationSpeed) -> RecordingStats {
        RecordingStats(
            elapsed: elapsed,
            movingTime: movingSeconds,
            distance: distance,
            currentSpeed: max(currentSpeed, 0),
            averageSpeed: movingSeconds > 0 ? distance / movingSeconds : 0
        )
    }
}

extension RecordingStats {
    /// Totals rebuilt from stored fixes alone, for a session that was stopped
    /// without them. Distance and durée de déplacement replay the accumulator;
    /// temps écoulé falls back to the first-to-last fix span, which counts any
    /// pause as riding because pauses leave no trace in the points.
    static func derived(from fixes: [CLLocation]) -> RecordingStats {
        let accumulator = RecordingStatsAccumulator.replaying(fixes)
        let span = fixes.last.map { last in fixes[0].timestamp.distance(to: last.timestamp) } ?? 0
        return accumulator.snapshot(elapsed: span, currentSpeed: 0)
    }
}
