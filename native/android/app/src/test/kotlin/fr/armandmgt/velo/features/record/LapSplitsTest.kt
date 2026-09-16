package fr.armandmgt.velo.features.record

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Splits are differences between the cumulative snapshots taken each time the
 * rider taps Tour, plus whatever the lap in progress has accrued since the last
 * one. Mirrors the iOS `LapSplitsTests` and the web's `lap_splits.js`, which
 * renders the same boundaries after the handoff.
 */
class LapSplitsTest {
    @Test
    fun `a recording with no Tour taps is a single lap in progress`() {
        val splits = LapSplits.splits(boundaries = emptyList(), totalDistance = 4_200.0, totalElapsed = 900.0)

        assertEquals(listOf(LapSplit(1, 4_200.0, 900.0, isInProgress = true)), splits)
    }

    @Test
    fun `one Tour tap closes lap 1 and opens lap 2`() {
        val boundaries = listOf(LapBoundary(1, 1_000.0, 300.0))

        val splits = LapSplits.splits(boundaries, totalDistance = 2_500.0, totalElapsed = 700.0)

        assertEquals(
            listOf(
                LapSplit(1, 1_000.0, 300.0, isInProgress = false),
                LapSplit(2, 1_500.0, 400.0, isInProgress = true),
            ),
            splits,
        )
    }

    @Test
    fun `each split is the difference from the previous boundary`() {
        val boundaries = listOf(
            LapBoundary(1, 1_000.0, 200.0),
            LapBoundary(2, 2_100.0, 460.0),
            LapBoundary(3, 3_000.0, 700.0),
        )

        val splits = LapSplits.splits(boundaries, totalDistance = 3_400.0, totalElapsed = 800.0)

        assertEquals(listOf(1_000.0, 1_100.0, 900.0, 400.0), splits.map { it.distance })
        assertEquals(listOf(200.0, 260.0, 240.0, 100.0), splits.map { it.elapsed })
        assertEquals(listOf(1, 2, 3, 4), splits.map { it.ordinal })
        assertEquals(listOf(false, false, false, true), splits.map { it.isInProgress })
    }

    @Test
    fun `boundaries are ordered by lap, whatever order they arrive in`() {
        val boundaries = listOf(LapBoundary(2, 2_100.0, 460.0), LapBoundary(1, 1_000.0, 200.0))

        val splits = LapSplits.splits(boundaries, totalDistance = 2_500.0, totalElapsed = 500.0)

        assertEquals(listOf(1_000.0, 1_100.0, 400.0), splits.map { it.distance })
    }

    @Test
    fun `average speed is the split's own distance over its own time`() {
        assertEquals(5.0, LapSplit(1, 1_000.0, 200.0, isInProgress = false).averageSpeed, 0.0)
    }

    @Test
    fun `a split with no elapsed time reads as zero, not infinity`() {
        assertEquals(0.0, LapSplit(1, 100.0, 0.0, isInProgress = true).averageSpeed, 0.0)
    }

    @Test
    fun `totals that trail a boundary clamp to zero rather than going negative`() {
        // Defensive: the totals and the boundaries are written at slightly different
        // moments, so a split must never render as -0.2 km.
        val boundaries = listOf(LapBoundary(1, 1_000.0, 300.0))

        val splits = LapSplits.splits(boundaries, totalDistance = 999.0, totalElapsed = 299.0)

        assertEquals(LapSplit(2, 0.0, 0.0, isInProgress = true), splits.last())
    }
}
