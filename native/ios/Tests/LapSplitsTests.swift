import CoreLocation
import Testing
@testable import Velo

/// Splits are differences between the cumulative snapshots taken each time the
/// rider taps Tour, plus whatever the lap in progress has accrued since the last
/// one. See `CONTEXT.md` for Tour / split, and ADR 0001 for why they stay local.
@Suite("LapSplits")
struct LapSplitsTests {
    @Test("a recording with no Tour taps is a single lap in progress")
    func singleLap() {
        let splits = LapSplits.splits(boundaries: [], totalDistance: 4_200, totalElapsed: 900)

        #expect(splits == [LapSplit(ordinal: 1, distance: 4_200, elapsed: 900, isInProgress: true)])
    }

    @Test("one Tour tap closes lap 1 and opens lap 2")
    func oneBoundary() {
        let boundaries = [LapBoundary(ordinal: 1, cumulativeDistance: 1_000, cumulativeElapsed: 300)]

        let splits = LapSplits.splits(boundaries: boundaries, totalDistance: 2_500, totalElapsed: 700)

        #expect(splits == [
            LapSplit(ordinal: 1, distance: 1_000, elapsed: 300, isInProgress: false),
            LapSplit(ordinal: 2, distance: 1_500, elapsed: 400, isInProgress: true),
        ])
    }

    @Test("each split is the difference from the previous boundary")
    func successiveDifferences() {
        let boundaries = [
            LapBoundary(ordinal: 1, cumulativeDistance: 1_000, cumulativeElapsed: 200),
            LapBoundary(ordinal: 2, cumulativeDistance: 2_100, cumulativeElapsed: 460),
            LapBoundary(ordinal: 3, cumulativeDistance: 3_000, cumulativeElapsed: 700),
        ]

        let splits = LapSplits.splits(boundaries: boundaries, totalDistance: 3_400, totalElapsed: 800)

        #expect(splits.map(\.distance) == [1_000, 1_100, 900, 400])
        #expect(splits.map(\.elapsed) == [200, 260, 240, 100])
        #expect(splits.map(\.ordinal) == [1, 2, 3, 4])
        #expect(splits.map(\.isInProgress) == [false, false, false, true])
    }

    @Test("boundaries are ordered by lap, whatever order they arrive in")
    func unorderedBoundaries() {
        let boundaries = [
            LapBoundary(ordinal: 2, cumulativeDistance: 2_100, cumulativeElapsed: 460),
            LapBoundary(ordinal: 1, cumulativeDistance: 1_000, cumulativeElapsed: 200),
        ]

        let splits = LapSplits.splits(boundaries: boundaries, totalDistance: 2_500, totalElapsed: 500)

        #expect(splits.map(\.distance) == [1_000, 1_100, 400])
    }

    @Test("average speed is the split's own distance over its own time")
    func averageSpeed() {
        let split = LapSplit(ordinal: 1, distance: 1_000, elapsed: 200, isInProgress: false)

        #expect(split.averageSpeed == 5)
    }

    @Test("a split with no elapsed time reads as zero, not infinity")
    func zeroElapsed() {
        let split = LapSplit(ordinal: 1, distance: 100, elapsed: 0, isInProgress: true)

        #expect(split.averageSpeed == 0)
    }

    @Test("a finished recording has no lap in progress")
    func finishedHasNoLapInProgress() {
        let boundaries = [LapBoundary(ordinal: 1, cumulativeDistance: 1_000, cumulativeElapsed: 300)]

        let splits = LapSplits.splits(
            boundaries: boundaries,
            totalDistance: 2_500,
            totalElapsed: 700,
            isFinished: true
        )

        #expect(splits.map(\.isInProgress) == [false, false])
        #expect(splits.last?.distance == 1_500)
    }

    @Test("a Tour tapped just before Arrêter leaves no phantom lap")
    func finishedDropsEmptyTrailingLap() {
        // Tour, then Arrêter a heartbeat later: the trailing delta is nothing, and
        // a "Tour 2 — 0,00 km / 00:00" row is noise on the review screen.
        let boundaries = [LapBoundary(ordinal: 1, cumulativeDistance: 4_000, cumulativeElapsed: 900)]

        let splits = LapSplits.splits(
            boundaries: boundaries,
            totalDistance: 4_000,
            totalElapsed: 900,
            isFinished: true
        )

        #expect(splits.map(\.ordinal) == [1])
    }

    @Test("an unlapped finished recording is still one lap")
    func finishedWithoutBoundaries() {
        let splits = LapSplits.splits(
            boundaries: [],
            totalDistance: 4_200,
            totalElapsed: 900,
            isFinished: true
        )

        #expect(splits == [LapSplit(ordinal: 1, distance: 4_200, elapsed: 900, isInProgress: false)])
    }

    @Test("totals that trail a boundary clamp to zero rather than going negative")
    func clampsNegatives() {
        // Defensive: the totals and the boundaries are written at slightly
        // different moments, so a split must never render as -0.2 km.
        let boundaries = [LapBoundary(ordinal: 1, cumulativeDistance: 1_000, cumulativeElapsed: 300)]

        let splits = LapSplits.splits(boundaries: boundaries, totalDistance: 999, totalElapsed: 299)

        #expect(splits.last == LapSplit(ordinal: 2, distance: 0, elapsed: 0, isInProgress: true))
    }
}
