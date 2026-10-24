import CoreData
import CoreLocation
import Testing
@testable import Velo

/// A recording the app was killed during comes back paused, with the totals,
/// Tours and trace it had, and carries on into the same session.
@Suite("Recording restore")
struct RecordingRestoreTests {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Accumulator

    @Test("totals restored from a snapshot carry on without bridging the dead span")
    func snapshotAccumulatorHasNoAnchor() {
        var accumulator = RecordingStatsAccumulator(distance: 2_345, movingSeconds: 600)

        _ = accumulator.add(fix(latitude: 48.9, seconds: 9_000))
        #expect(accumulator.distance == 2_345)
        #expect(accumulator.movingSeconds == 600)

        _ = accumulator.add(fix(latitude: 48.901, seconds: 9_010))
        #expect(abs(accumulator.distance - (2_345 + 111.2)) < 2)
        #expect(accumulator.movingSeconds == 610)
    }

    @Test("replaying stored fixes gives what live folding gave, and ends unanchored")
    func replayMatchesLiveFolding() {
        let fixes = (0..<4).map { fix(latitude: 48.8566 + Double($0) * 0.001, seconds: Double($0) * 10) }
        var live = RecordingStatsAccumulator()
        for fix in fixes { _ = live.add(fix) }

        var replayed = RecordingStatsAccumulator.replaying(fixes)

        #expect(replayed.distance == live.distance)
        #expect(replayed.movingSeconds == live.movingSeconds)
        #expect(replayed.lastLocation == nil)
        _ = replayed.add(fix(latitude: 49.5, seconds: 3_600))
        #expect(replayed.distance == live.distance)
    }

    @Test("a session restores from its running snapshot, not from its points")
    func sessionPrefersSnapshot() {
        let store = RecordingStore(inMemory: true)
        let session = store.createSession(startedAt: startedAt)
        appendPoints(to: session, in: store, count: 4)
        session.distance = 150
        session.movingTime = 20

        let accumulator = session.restoredAccumulator

        #expect(accumulator.distance == 150)
        #expect(accumulator.movingSeconds == 20)
        #expect(accumulator.lastLocation == nil)
    }

    @Test("an orphan from a build that kept no snapshot replays its points")
    func sessionWithoutSnapshotReplaysPoints() {
        let store = RecordingStore(inMemory: true)
        let session = store.createSession(startedAt: startedAt)
        appendPoints(to: session, in: store, count: 4)

        let accumulator = session.restoredAccumulator

        #expect(abs(accumulator.distance - 333.6) < 3)
        #expect(accumulator.movingSeconds == 30)
    }

    // MARK: - Controller

    @Test("a killed recording restores paused, with its clock, totals, Tours, sport and trace")
    func restoresPaused() throws {
        let store = RecordingStore(inMemory: true)
        let orphan = killedRecording(in: store, state: .recording)

        let controller = RecordingController(store: store)

        #expect(controller.state == .paused)
        #expect(controller.sport == .trailRun)
        #expect(controller.pointCount == 4)
        #expect(controller.routeCoordinates.count == 4)
        #expect(controller.currentLap == 2)
        #expect(controller.lapSplits.count == 2)
        let stats = controller.currentStats
        #expect(stats.elapsed == 754)
        #expect(stats.distance == 2_345)
        #expect(stats.movingTime == 600)
        #expect(orphan.recordingState == .paused)
    }

    @Test("a recording killed while auto-paused restores as a manual pause")
    func autoPausedRestoresAsManualPause() {
        let store = RecordingStore(inMemory: true)
        let orphan = killedRecording(in: store, state: .autoPaused)
        let controller = RecordingController(store: store)
        let recorder = LocationRecorder()

        // Movement alone would resume an automatic pause; it must not resume this one.
        controller.locationRecorder(recorder, didUpdate: fix(latitude: 48.9, seconds: 9_000, speed: 8))
        controller.locationRecorder(recorder, didUpdate: fix(latitude: 48.91, seconds: 9_001, speed: 8))

        #expect(controller.state == .paused)
        #expect(orphan.recordingState == .paused)
        #expect(controller.pointCount == 4)
    }

    @Test("Démarrer can't open a second session beside a restored one")
    func startIsUnavailableWhileRestored() throws {
        let store = RecordingStore(inMemory: true)
        _ = killedRecording(in: store, state: .recording)
        let controller = RecordingController(store: store)

        controller.start()

        #expect(controller.state == .paused)
        let request = NSFetchRequest<RecordingSession>(entityName: "RecordingSession")
        #expect(try store.viewContext.count(for: request) == 1)
    }

    @Test("Reprendre records into the same session; the killed span adds no time or distance")
    func resumeContinuesSameSession() throws {
        let store = RecordingStore(inMemory: true)
        let orphan = killedRecording(in: store, state: .recording)
        let controller = RecordingController(store: store)
        let recorder = LocationRecorder()

        controller.resume()
        #expect(controller.state == .recording)
        #expect(orphan.recordingState == .recording)

        // An hour after the last stored fix, a kilometre away: the first fix only anchors.
        controller.locationRecorder(recorder, didUpdate: fix(latitude: 48.87, seconds: 3_600))
        #expect(controller.currentStats.distance == 2_345)
        #expect(controller.currentStats.elapsed < 756)
        controller.locationRecorder(recorder, didUpdate: fix(latitude: 48.871, seconds: 3_610))
        #expect(abs(controller.currentStats.distance - (2_345 + 111.2)) < 2)
        #expect(abs(orphan.distance - controller.currentStats.distance) < 0.001)

        let finished = try #require(controller.stop())
        #expect(finished === orphan)
        #expect(controller.state == .idle)
        #expect(finished.orderedPoints.count == 6)
        #expect(controller.pendingHandoff?.session === orphan)
    }

    @Test("with nothing interrupted the controller starts idle")
    func startsIdleWithoutOrphan() {
        let store = RecordingStore(inMemory: true)
        let stopped = store.createSession(startedAt: startedAt)
        store.finish(stopped, stats: .zero)

        let controller = RecordingController(store: store)

        #expect(controller.state == .idle)
        #expect(controller.currentStats.distance == 0)
    }

    // MARK: - Helpers

    /// An active session as a kill leaves it: four fixes, one Tour closed, and
    /// running snapshots that no longer match a straight replay of the points.
    private func killedRecording(in store: RecordingStore, state: RecordingState) -> RecordingSession {
        let session = store.createSession(startedAt: startedAt, sport: .trailRun)
        appendPoints(to: session, in: store, count: 4)
        store.appendLap(to: session, ordinal: 1, endedAt: startedAt.addingTimeInterval(300),
                        cumulativeDistance: 1_000, cumulativeElapsed: 300)
        session.lapCount = 2
        session.recordingState = state
        session.elapsed = 754
        session.distance = 2_345
        session.movingTime = 600
        session.averageSpeed = 2_345.0 / 600
        store.save()
        return session
    }

    private func appendPoints(to session: RecordingSession, in store: RecordingStore, count: Int) {
        for index in 0..<count {
            store.appendPoint(
                to: session,
                timestamp: startedAt.addingTimeInterval(Double(index) * 10),
                latitude: 48.8566 + Double(index) * 0.001,
                longitude: 2.3522,
                elevation: nil,
                speed: 11,
                horizontalAccuracy: 5,
                lap: 1
            )
        }
    }

    private func fix(latitude: Double, seconds: TimeInterval, speed: CLLocationSpeed = -1) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 2.3522),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            course: -1,
            speed: speed,
            timestamp: startedAt.addingTimeInterval(seconds)
        )
    }
}
