import CoreLocation
import Foundation

/// The cumulative totals at the moment the rider tapped Tour, closing lap
/// `ordinal` (S12a — #60).
///
/// Snapshots rather than per-lap deltas: writing one row per tap is O(1) and
/// exact, and the deltas fall out as differences. Persisted (see `RecordingLap`)
/// so splits survive the force-quit that S5 already recovers the recording from.
struct LapBoundary: Equatable {
    let ordinal: Int
    let cumulativeDistance: CLLocationDistance
    let cumulativeElapsed: TimeInterval
}

/// One Tour's own numbers, as shown in the lap sheet and on the review screen.
///
/// Timed by **temps écoulé**, not durée de déplacement, so a split always agrees
/// with the timer the rider watched (see `CONTEXT.md`).
struct LapSplit: Equatable, Identifiable {
    let ordinal: Int
    let distance: CLLocationDistance
    let elapsed: TimeInterval
    /// The lap currently being ridden — the last one, until Tour or Arrêter.
    let isInProgress: Bool

    var id: Int { ordinal }

    var averageSpeed: CLLocationSpeed {
        elapsed > 0 ? distance / elapsed : 0
    }
}

enum LapSplits {
    /// Below this a trailing lap is an artefact of tapping Tour just before
    /// Arrêter, not a lap anyone rode.
    private static let emptyLapDistance: CLLocationDistance = 1
    private static let emptyLapElapsed: TimeInterval = 1

    /// Expand the persisted boundaries plus the recording's totals into one split
    /// per Tour. While recording, the last one is the lap in progress; once
    /// `isFinished`, nothing is in progress and an empty trailing lap is dropped.
    ///
    /// Always returns at least one split for a recording that covered ground: one
    /// that was never lapped is a single lap covering the whole ride.
    static func splits(
        boundaries: [LapBoundary],
        totalDistance: CLLocationDistance,
        totalElapsed: TimeInterval,
        isFinished: Bool = false
    ) -> [LapSplit] {
        let ordered = boundaries.sorted { $0.ordinal < $1.ordinal }

        var splits: [LapSplit] = []
        var previousDistance: CLLocationDistance = 0
        var previousElapsed: TimeInterval = 0

        for boundary in ordered {
            splits.append(
                LapSplit(
                    ordinal: boundary.ordinal,
                    distance: max(boundary.cumulativeDistance - previousDistance, 0),
                    elapsed: max(boundary.cumulativeElapsed - previousElapsed, 0),
                    isInProgress: false
                )
            )
            previousDistance = boundary.cumulativeDistance
            previousElapsed = boundary.cumulativeElapsed
        }

        // The totals and the boundary rows are written a beat apart, so clamp: a
        // split must never render as a negative distance.
        let trailing = LapSplit(
            ordinal: (ordered.last?.ordinal ?? 0) + 1,
            distance: max(totalDistance - previousDistance, 0),
            elapsed: max(totalElapsed - previousElapsed, 0),
            isInProgress: !isFinished
        )

        let isPhantom = isFinished
            && !splits.isEmpty
            && trailing.distance < emptyLapDistance
            && trailing.elapsed < emptyLapElapsed
        if !isPhantom {
            splits.append(trailing)
        }

        return splits
    }
}
