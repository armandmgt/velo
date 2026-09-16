package fr.armandmgt.velo.features.record

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * One fix as the detector sees it. [speedMps] is null when the platform could not
 * measure a speed (`Location.hasSpeed()` false, the Android equivalent of
 * CoreLocation's -1).
 */
data class AutoPauseFix(
    val timeMs: Long,
    val latitude: Double,
    val longitude: Double,
    val speedMps: Double?,
)

/** What one fix tells the recording to do. */
enum class AutoPauseOutcome { NONE, SHOULD_AUTO_PAUSE, SHOULD_AUTO_RESUME }

/**
 * Decides when a recording enters and leaves **pause automatique**. Port of the
 * iOS `AutoPauseDetector`, constants included.
 *
 * Entering is deliberately slow (ten consecutive still seconds) and leaving is
 * eager, because a late pause costs a few seconds of temps écoulé while a late
 * resume loses real track (ADR 0002). Leaving keys primarily on **displacement**:
 * a stationary phone reports 0.3–0.8 m/s of Doppler noise, straddling the very
 * threshold used to enter, so a speed-based exit at that threshold would flap at
 * every traffic light.
 *
 * Kept free of `android.location` and of [RecordingService] so the hysteresis is
 * exercised directly by `AutoPauseDetectorTest` on the JVM.
 */
class AutoPauseDetector(
    /**
     * Whether pause automatique is switched on for this recording. Read once at
     * Démarrer, so a ride records under the setting it started with.
     */
    val isEnabled: Boolean,
) {
    private sealed interface Phase {
        /** Recording, watching for stillness. */
        data object Armed : Phase

        /** Auto-paused at [anchor], watching for the rider to move away from it. */
        data class AutoPaused(val anchor: AutoPauseFix) : Phase

        /**
         * Recording after a manual **Reprendre**, which outranks the detector:
         * nothing fires until the rider has genuinely left [anchor].
         */
        data class Suppressed(val anchor: AutoPauseFix) : Phase

        /**
         * The rider paused by hand, or no recording is running. The detector stays
         * silent — movement must not undo a pause someone asked for.
         */
        data object Inactive : Phase
    }

    private var phase: Phase = Phase.Inactive

    /** When the current unbroken run of still fixes began. */
    private var stillSinceMs: Long? = null

    /** The previous fix, for gap detection and for anchoring a manual pause. */
    private var lastFix: AutoPauseFix? = null

    /** Arm the detector for a fresh recording. */
    fun reset() {
        phase = Phase.Armed
        stillSinceMs = null
        lastFix = null
    }

    /**
     * Fold in one fix — including the ones the recording drops while paused, which
     * is exactly how the auto-resume is detected.
     */
    fun consider(fix: AutoPauseFix): AutoPauseOutcome {
        if (!isEnabled) return AutoPauseOutcome.NONE

        val previous = lastFix
        lastFix = fix

        return when (val current = phase) {
            is Phase.Inactive -> AutoPauseOutcome.NONE

            is Phase.Armed -> {
                val speed = fix.speedMps
                // An unmeasurable speed is not evidence of stillness — only positive
                // evidence may pause a recording, so it breaks the run.
                if (speed == null || speed >= STILL_SPEED_THRESHOLD) {
                    stillSinceMs = null
                    return AutoPauseOutcome.NONE
                }
                // A hole in the fix stream (backgrounding, a tunnel, re-acquisition)
                // leaves two isolated slow readings with an unobserved span between
                // them — the rider may have been moving the whole time. Start the run
                // over rather than counting the gap as stillness.
                if (previous != null && fix.timeMs - previous.timeMs > MAX_FIX_GAP_MS) {
                    stillSinceMs = fix.timeMs
                    return AutoPauseOutcome.NONE
                }
                val since = stillSinceMs
                if (since == null) {
                    stillSinceMs = fix.timeMs
                    return AutoPauseOutcome.NONE
                }
                if (fix.timeMs - since < STILL_DURATION_MS) return AutoPauseOutcome.NONE
                phase = Phase.AutoPaused(fix)
                stillSinceMs = null
                AutoPauseOutcome.SHOULD_AUTO_PAUSE
            }

            is Phase.AutoPaused -> {
                if (!hasLeft(current.anchor, fix)) return AutoPauseOutcome.NONE
                phase = Phase.Armed
                stillSinceMs = null
                AutoPauseOutcome.SHOULD_AUTO_RESUME
            }

            is Phase.Suppressed -> {
                if (!hasLeft(current.anchor, fix)) return AutoPauseOutcome.NONE
                phase = Phase.Armed
                stillSinceMs = null
                AutoPauseOutcome.NONE
            }
        }
    }

    /**
     * The rider tapped **Reprendre**. That suppresses the detector until they have
     * actually moved — re-pausing someone who just asked to be recorded is the
     * worst failure mode this feature has, and it applies just as much to a manual
     * pause taken at a start line as to an automatic one.
     */
    fun userDidResume() {
        val anchor = when (val current = phase) {
            is Phase.AutoPaused -> current.anchor
            else -> lastFix
        }
        phase = if (anchor != null) Phase.Suppressed(anchor) else Phase.Armed
        stillSinceMs = null
    }

    /**
     * The rider tapped **Pause**. An explicit pause outranks the detector in the
     * other direction too: no amount of movement may resume it.
     */
    fun userDidPause() {
        phase = Phase.Inactive
        stillSinceMs = null
    }

    /**
     * Has the rider genuinely left [anchor]? Either they have covered ground, or
     * they are measurably moving at a speed no stationary phone reports.
     */
    private fun hasLeft(anchor: AutoPauseFix, fix: AutoPauseFix): Boolean {
        if (metersBetween(anchor, fix) > RESUME_DISTANCE_METERS) return true
        return (fix.speedMps ?: 0.0) >= RESUME_SPEED
    }

    companion object {
        /**
         * Fixes at or above this (m/s) count as moving. Mirrors
         * [RecordingStatsAccumulator.MOVING_SPEED_THRESHOLD] — and so the server's
         * `GpxExtractor::MOVING_SPEED_THRESHOLD`.
         */
        const val STILL_SPEED_THRESHOLD = RecordingStatsAccumulator.MOVING_SPEED_THRESHOLD

        /** How long the rider must read as still before we pause them. */
        const val STILL_DURATION_MS = 10_000L

        /** How far from the pause anchor counts as genuinely moving again (meters). */
        const val RESUME_DISTANCE_METERS = 15.0

        /**
         * A measured speed this high (m/s, ~7 km/h) is unambiguous movement, far
         * above the stationary-noise band. Resuming on it as well as on displacement
         * matters because a paused recording drops its fixes: waiting to cover
         * [RESUME_DISTANCE_METERS] throws away the first seconds of the rider
         * pulling away.
         */
        const val RESUME_SPEED = 2.0

        /**
         * Consecutive fixes further apart than this say nothing about the span
         * between them, so they cannot build a still run. Mirrors the spirit of
         * [RecordingStatsAccumulator.PAUSE_GAP_SECONDS] in the distance accumulator.
         */
        const val MAX_FIX_GAP_MS = 5_000L

        private const val EARTH_RADIUS_METERS = 6_371_008.8

        /** Haversine, so the detector needs no `Location.distanceTo` to be testable. */
        private fun metersBetween(a: AutoPauseFix, b: AutoPauseFix): Double {
            val lat1 = Math.toRadians(a.latitude)
            val lat2 = Math.toRadians(b.latitude)
            val dLat = lat2 - lat1
            val dLon = Math.toRadians(b.longitude - a.longitude)
            val h = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
            return 2 * EARTH_RADIUS_METERS * asin(min(1.0, sqrt(h)))
        }
    }
}
