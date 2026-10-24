package fr.armandmgt.velo.features.record

import android.location.Location
import fr.armandmgt.velo.features.record.data.RecordingPointEntity
import fr.armandmgt.velo.features.record.data.RecordingSessionEntity

/**
 * Live, derived stats for an in-progress recording.
 *
 * Mirrors the iOS `RecordingStatsAccumulator` (and the server-side `GpxExtractor`
 * conventions) so on-device numbers match the eventual upload:
 * - distance accumulates the geodesic gap between consecutive fixes
 *   (`Location.distanceTo`, the Android equivalent of `CLLocation.distance(from:)`);
 * - a segment only counts toward *moving* time when its speed clears
 *   [MOVING_SPEED_THRESHOLD] and the gap is under [PAUSE_GAP_SECONDS];
 * - average speed is distance over moving time (not wall-clock).
 *
 * Folded incrementally (O(1) per fix) by [RecordingService].
 *
 * Constructed from totals a recording already stored, it carries on from them
 * with no segment anchor, so the first fix after adds nothing: a restored
 * recording is paused, and the span the app was dead must not count as ridden.
 */
class RecordingStatsAccumulator(distance: Double = 0.0, movingSeconds: Double = 0.0) {
    /** Total distance over the ground, meters. */
    var distance: Double = distance
        private set

    /** Seconds spent actually moving (excludes paused/stationary stretches). */
    var movingSeconds: Double = movingSeconds
        private set

    private var lastLocation: Location? = null

    /**
     * Fold one accepted fix in, returning the segment speed (m/s) for the
     * per-point `speed` we persist. Distance / moving-time follow the GPX rules.
     */
    fun add(location: Location): Double {
        val previous = lastLocation
        lastLocation = location
        if (previous == null) return if (location.hasSpeed()) location.speed.toDouble() else 0.0

        val segment = location.distanceTo(previous).toDouble()
        val dt = (location.time - previous.time) / 1000.0
        distance += segment

        if (dt <= 0) return if (location.hasSpeed()) location.speed.toDouble() else 0.0
        val segmentSpeed = segment / dt
        if (segmentSpeed >= MOVING_SPEED_THRESHOLD && dt <= PAUSE_GAP_SECONDS) {
            movingSeconds += dt
        }
        // Prefer the platform's Doppler speed when present; fall back to the
        // position-derived segment speed (matching how GPX speed is computed).
        return if (location.hasSpeed()) location.speed.toDouble() else segmentSpeed
    }

    /**
     * Drop the running segment anchor so the next fix starts fresh — used on pause
     * so the paused gap contributes neither distance nor moving time.
     */
    fun breakSegment() {
        lastLocation = null
    }

    /** Distance / moving time (m/s); 0 until the first moving segment. */
    fun averageSpeed(): Double = if (movingSeconds > 0) distance / movingSeconds else 0.0

    companion object {
        /** Segments slower than this (m/s) don't count toward moving time. */
        const val MOVING_SPEED_THRESHOLD = 0.5

        /** Segments spanning a longer gap (seconds) are treated as paused. */
        const val PAUSE_GAP_SECONDS = 30.0

        /**
         * Fold stored points in order, ending without an anchor like a paused
         * recording. Pauses leave no trace in the points, so a gap a pause skipped
         * counts as ridden here where live folding broke the segment instead.
         */
        fun replaying(points: List<RecordingPointEntity>): RecordingStatsAccumulator =
            RecordingStatsAccumulator().apply {
                for (point in points) {
                    add(
                        Location("recording").apply {
                            latitude = point.latitude
                            longitude = point.longitude
                            time = point.timestamp
                        },
                    )
                }
                breakSegment()
            }
    }
}

/**
 * The running totals an interrupted recording picks up from: the snapshot kept
 * current with every point. An orphan from a build that kept no snapshot replays
 * its [points] instead, which may overcount across the pauses it took before the kill.
 */
fun RecordingSessionEntity.restoredAccumulator(points: List<RecordingPointEntity>): RecordingStatsAccumulator =
    if (distance == 0.0 && movingTime == 0.0 && points.size > 1) {
        RecordingStatsAccumulator.replaying(points)
    } else {
        RecordingStatsAccumulator(distance, movingTime)
    }
