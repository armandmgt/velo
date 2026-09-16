package fr.armandmgt.velo.features.record

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The pause automatique rules: enter after ten still seconds, leave on fifteen
 * metres of displacement (or unambiguous speed), and never override an explicit
 * instruction from the rider. Mirrors the iOS `AutoPauseDetectorTests`.
 */
class AutoPauseDetectorTest {
    private val originLatitude = 48.8566
    private val originLongitude = 2.3522

    /** A fix `seconds` into the recording, `metersNorth` from the origin. */
    private fun fix(seconds: Long, speed: Double?, metersNorth: Double = 0.0) = AutoPauseFix(
        timeMs = seconds * 1000,
        latitude = originLatitude + metersNorth / 111_320,
        longitude = originLongitude,
        speedMps = speed,
    )

    private fun armedDetector() = AutoPauseDetector(isEnabled = true).apply { reset() }

    /** Ten still seconds, leaving the detector auto-paused at the origin. */
    private fun pausedDetector(): AutoPauseDetector {
        val detector = armedDetector()
        for (second in 0..10L) detector.consider(fix(second, 0.1))
        return detector
    }

    @Test
    fun `a moving rider is never auto-paused`() {
        val detector = armedDetector()
        for (second in 0..30L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 5.0, second * 5.0)))
        }
    }

    @Test
    fun `ten still seconds trigger a pause, and not a second sooner`() {
        val detector = armedDetector()
        for (second in 0..9L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1)))
        }
        assertEquals(AutoPauseOutcome.SHOULD_AUTO_PAUSE, detector.consider(fix(10, 0.1)))
    }

    @Test
    fun `a fix at the moving threshold counts as moving`() {
        val detector = armedDetector()
        for (second in 0..30L) {
            assertEquals(
                AutoPauseOutcome.NONE,
                detector.consider(fix(second, AutoPauseDetector.STILL_SPEED_THRESHOLD)),
            )
        }
    }

    @Test
    fun `any movement restarts the still run`() {
        val detector = armedDetector()
        for (second in 0..8L) detector.consider(fix(second, 0.1))
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(9, 3.0)))
        // The run restarts at second 10, so the pause is due at second 20 — the nine
        // still seconds banked before the movement do not count.
        for (second in 10..19L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1)))
        }
        assertEquals(AutoPauseOutcome.SHOULD_AUTO_PAUSE, detector.consider(fix(20, 0.1)))
    }

    @Test
    fun `fifteen metres resumes even when the speed reads zero`() {
        val detector = pausedDetector()
        // Displacement stands on its own: a rider whose speed never reads valid still
        // gets resumed once they have covered ground.
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(11, 0.0, 3.0)))
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(12, 0.0, 14.0)))
        assertEquals(AutoPauseOutcome.SHOULD_AUTO_RESUME, detector.consider(fix(13, 0.0, 20.0)))
    }

    @Test
    fun `clear movement resumes without waiting to cover fifteen metres`() {
        val detector = pausedDetector()
        // Waiting for 15 m of displacement throws away the first seconds of the rider
        // pulling away, because a paused recording drops its fixes.
        assertEquals(AutoPauseOutcome.SHOULD_AUTO_RESUME, detector.consider(fix(11, 3.0, 2.0)))
    }

    @Test
    fun `noise-band speed alone does not resume`() {
        val detector = pausedDetector()
        // 0.3–0.8 m/s is what a stationary phone reports; so is an unmeasurable speed.
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(11, 0.8, 1.0)))
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(12, null, 1.0)))
    }

    @Test
    fun `a manual resume disarms the detector until the rider actually moves`() {
        val detector = pausedDetector()
        detector.userDidResume()

        // Still stationary, but the rider just said "record me" — leave them alone.
        for (second in 11..40L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1)))
        }
        // Once they've genuinely moved, the detector re-arms.
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(41, 3.0, 20.0)))
        for (second in 42..51L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1, 20.0)))
        }
        assertEquals(AutoPauseOutcome.SHOULD_AUTO_PAUSE, detector.consider(fix(52, 0.1, 20.0)))
    }

    @Test
    fun `resuming a manual pause also disarms the detector until the rider moves`() {
        val detector = armedDetector()
        detector.consider(fix(0, 3.0))
        detector.userDidPause()
        detector.userDidResume()

        // Stopped at a start line, told to record: leave them alone.
        for (second in 1..40L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1)))
        }
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(41, 3.0, 20.0)))
        for (second in 42..51L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1, 20.0)))
        }
        assertEquals(AutoPauseOutcome.SHOULD_AUTO_PAUSE, detector.consider(fix(52, 0.1, 20.0)))
    }

    @Test
    fun `a manual pause takes the detector out of play entirely`() {
        val detector = armedDetector()
        detector.userDidPause()
        for (second in 0..30L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1)))
        }
        // Movement must not auto-resume a pause the rider asked for.
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(31, 5.0, 500.0)))
    }

    @Test
    fun `an unmeasurable speed is not evidence of stillness`() {
        val detector = armedDetector()
        // The platform reports no speed while a fix is still settling. Pausing on
        // that would stop a moving rider.
        for (second in 0..30L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, null)))
        }
    }

    @Test
    fun `an unmeasurable speed breaks a still run rather than extending it`() {
        val detector = armedDetector()
        for (second in 0..8L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1)))
        }
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(9, null)))
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(10, 0.1)))
    }

    @Test
    fun `a broken fix stream does not count as ten still seconds`() {
        val detector = armedDetector()
        // Two isolated slow readings a minute apart say nothing about the minute
        // between them — the rider may have ridden the whole way.
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(0, 0.1)))
        assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(60, 0.1)))
        // A genuine unbroken run still pauses — timed from the fix that restarted it
        // at t=60, so the pause is due at t=70.
        for (second in 61..69L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.1)))
        }
        assertEquals(AutoPauseOutcome.SHOULD_AUTO_PAUSE, detector.consider(fix(70, 0.1)))
    }

    @Test
    fun `a disabled detector never fires`() {
        val detector = AutoPauseDetector(isEnabled = false).apply { reset() }
        for (second in 0..30L) {
            assertEquals(AutoPauseOutcome.NONE, detector.consider(fix(second, 0.0)))
        }
    }
}
