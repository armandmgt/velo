import CoreLocation
import Foundation

/// Live, derived stats for an in-progress recording (#41, S3 — #51).
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

    /// Wall-clock recording time, excluding paused stretches (seconds).
    var elapsed: TimeInterval = 0
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

    /// Snapshot for display. `elapsed` is supplied by the controller's clock so
    /// it keeps ticking between fixes.
    func snapshot(elapsed: TimeInterval, currentSpeed: CLLocationSpeed) -> RecordingStats {
        RecordingStats(
            elapsed: elapsed,
            distance: distance,
            currentSpeed: max(currentSpeed, 0),
            averageSpeed: movingSeconds > 0 ? distance / movingSeconds : 0
        )
    }
}
