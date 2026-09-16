package fr.armandmgt.velo.features.record

import kotlin.math.max

/**
 * The cumulative totals at the moment the rider tapped Tour, closing lap
 * [ordinal].
 *
 * Snapshots rather than per-lap deltas: writing one row per tap is O(1) and
 * exact, and the deltas fall out as differences. Persisted as
 * [fr.armandmgt.velo.features.record.data.RecordingLapEntity], so splits survive
 * the process kill the recording itself is recovered from.
 */
data class LapBoundary(
    val ordinal: Int,
    val cumulativeDistance: Double,
    val cumulativeElapsed: Double,
)

/**
 * One Tour's own numbers, as shown in the in-ride lap sheet.
 *
 * Timed by **temps écoulé**, not durée de déplacement, so a split always agrees
 * with the timer the rider watched.
 */
data class LapSplit(
    val ordinal: Int,
    val distance: Double,
    val elapsed: Double,
    /** The lap currently being ridden — the last one, until Tour or Arrêter. */
    val isInProgress: Boolean,
) {
    val averageSpeed: Double get() = if (elapsed > 0) distance / elapsed else 0.0
}

/**
 * Mirrors the iOS `LapSplits` and the web's `lap_splits.js`, which renders the
 * same boundaries after the handoff — the in-ride sheet must not show a rider
 * different numbers from the review screen they see a minute later.
 */
object LapSplits {
    /**
     * Expand the persisted boundaries plus the recording's totals into one split
     * per Tour, the last being the lap in progress.
     *
     * Always returns at least one split for a recording that covered ground: one
     * that was never lapped is a single lap covering the whole ride.
     */
    fun splits(
        boundaries: List<LapBoundary>,
        totalDistance: Double,
        totalElapsed: Double,
    ): List<LapSplit> {
        val ordered = boundaries.sortedBy { it.ordinal }

        val splits = mutableListOf<LapSplit>()
        var previousDistance = 0.0
        var previousElapsed = 0.0

        for (boundary in ordered) {
            splits.add(
                LapSplit(
                    ordinal = boundary.ordinal,
                    // The totals and the boundary rows are written a beat apart, so
                    // clamp: a split must never render as a negative distance.
                    distance = max(boundary.cumulativeDistance - previousDistance, 0.0),
                    elapsed = max(boundary.cumulativeElapsed - previousElapsed, 0.0),
                    isInProgress = false,
                ),
            )
            previousDistance = boundary.cumulativeDistance
            previousElapsed = boundary.cumulativeElapsed
        }

        splits.add(
            LapSplit(
                ordinal = (ordered.lastOrNull()?.ordinal ?: 0) + 1,
                distance = max(totalDistance - previousDistance, 0.0),
                elapsed = max(totalElapsed - previousElapsed, 0.0),
                isInProgress = true,
            ),
        )

        return splits
    }
}
