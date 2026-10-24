import Compression
import CoreData
import CoreLocation
import Testing
@testable import Velo

/// The handoff is built against the *bundled* Core Data model, so these run on
/// a real `RecordingStore` (in-memory) rather than stubs: a model version that
/// omits an entity the Swift subclasses declare is invisible to the compiler and
/// only surfaces as an unrecognized-selector abort at the moment the review
/// screen asks for the payload.
@Suite("RecordingHandoff")
struct RecordingHandoffTests {
    @Test("a recording with no Tour taps still encodes for the review screen")
    func encodesSessionWithoutLaps() throws {
        let store = RecordingStore(inMemory: true)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = store.createSession(startedAt: startedAt)
        store.appendPoint(
            to: session,
            timestamp: startedAt,
            latitude: 48.8566,
            longitude: 2.3522,
            elevation: 35,
            speed: 5,
            horizontalAccuracy: 5,
            lap: 1
        )

        #expect(session.lapBoundaries.isEmpty)

        let handoff = RecordingHandoff(session: session)
        #expect(try !handoff.encoded().isEmpty)
    }

    @Test("a stopped recording encodes its points and laps for the review screen")
    func encodesSessionWithLaps() throws {
        let store = RecordingStore(inMemory: true)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = store.createSession(startedAt: startedAt)
        store.appendPoint(
            to: session,
            timestamp: startedAt,
            latitude: 48.8566,
            longitude: 2.3522,
            elevation: 35,
            speed: 5,
            horizontalAccuracy: 5,
            lap: 1
        )
        store.appendLap(to: session, ordinal: 1, endedAt: startedAt.addingTimeInterval(300),
                        cumulativeDistance: 1_000, cumulativeElapsed: 300)

        #expect(session.orderedPoints.count == 1)
        #expect(session.lapBoundaries == [LapBoundary(ordinal: 1, cumulativeDistance: 1_000, cumulativeElapsed: 300)])

        let handoff = RecordingHandoff(session: session)
        #expect(try !handoff.encoded().isEmpty)
    }
}

/// A stopped recording must be sendable long after Arrêter — after a failed
/// review page or a process kill — so its handoff is rebuilt from the store.
@Suite("Unsent recordings")
struct UnsentRecordingsTests {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a handoff rebuilt from a stored session carries the totals stored at Arrêter")
    func rebuildsHandoffFromStoredSession() throws {
        let store = RecordingStore(inMemory: true)
        let session = store.createSession(startedAt: startedAt, sport: .trailRun)
        appendPoints(to: session, in: store, count: 3)
        store.appendLap(to: session, ordinal: 1, endedAt: startedAt.addingTimeInterval(60),
                        cumulativeDistance: 120, cumulativeElapsed: 60)
        let stats = RecordingStats(elapsed: 754, movingTime: 600, distance: 2_345, averageSpeed: 3.9)
        store.finish(session, stats: stats, at: startedAt.addingTimeInterval(800))
        store.viewContext.refreshAllObjects()

        let stored = try #require(store.stoppedSessions().first)
        let payload = try decode(RecordingHandoff(session: stored))

        #expect(payload["recordingUuid"] as? String == session.id.uuidString.lowercased())
        #expect(payload["sport"] as? String == "trail_run")
        let payloadStats = try #require(payload["stats"] as? [String: Double])
        #expect(payloadStats == ["distance": 2_345, "elapsed": 754, "movingTime": 600, "averageSpeed": 3.9])
        #expect((payload["points"] as? [Any])?.count == 3)
        #expect((payload["laps"] as? [Any])?.count == 1)
    }

    @Test("a session stopped without stored totals falls back to totals derived from its points")
    func derivesTotalsForSessionsWithoutThem() throws {
        let store = RecordingStore(inMemory: true)
        let session = store.createSession(startedAt: startedAt)
        // ~111 m per 0.001° of latitude, one fix every 10 s: moving the whole way.
        appendPoints(to: session, in: store, count: 4, secondsApart: 10)
        session.recordingState = .stopped
        store.save()

        let handoff = RecordingHandoff(session: try #require(store.stoppedSessions().first))

        #expect(handoff.stats.elapsed == 30)
        #expect(handoff.stats.movingTime == 30)
        #expect(abs(handoff.stats.distance - 333.6) < 3)
        #expect(handoff.stats.averageSpeed == handoff.stats.distance / 30)
        #expect(handoff.sport == Sport.lastUsed)
    }

    @Test("the fallback prefers the running temps écoulé snapshot to the span of the points")
    func fallbackUsesElapsedSnapshot() throws {
        let store = RecordingStore(inMemory: true)
        let session = store.createSession(startedAt: startedAt, sport: .bike)
        appendPoints(to: session, in: store, count: 4, secondsApart: 10)
        session.elapsed = 42
        session.recordingState = .stopped
        store.save()

        #expect(session.finalStats.elapsed == 42)
        #expect(session.recordedSport == .bike)
    }

    @Test("a point carries heart rate only when the strap had a reading for it")
    func heartRateReachesTheHandoff() throws {
        let store = RecordingStore(inMemory: true)
        let session = store.createSession(startedAt: startedAt)
        for (index, heartRate) in [142, nil].enumerated() {
            store.appendPoint(
                to: session,
                timestamp: startedAt.addingTimeInterval(Double(index)),
                latitude: 48.8566,
                longitude: 2.3522,
                elevation: nil,
                speed: 0,
                horizontalAccuracy: 5,
                lap: 1,
                heartRate: heartRate
            )
        }
        store.finish(session, stats: .zero)

        let points = try #require(decode(RecordingHandoff(session: session))["points"] as? [[String: Any]])
        #expect(points.map { $0["hr"] as? Int } == [142, nil])
    }

    @Test("only stopped sessions with points are unsent, newest first")
    func listsStoppedSessionsNewestFirst() {
        let store = RecordingStore(inMemory: true)
        let older = store.createSession(startedAt: startedAt)
        appendPoints(to: older, in: store, count: 1)
        store.finish(older, stats: .zero)
        let newer = store.createSession(startedAt: startedAt.addingTimeInterval(3_600))
        appendPoints(to: newer, in: store, count: 1)
        store.finish(newer, stats: .zero)
        let empty = store.createSession(startedAt: startedAt.addingTimeInterval(5_400))
        store.finish(empty, stats: .zero)
        let active = store.createSession(startedAt: startedAt.addingTimeInterval(7_200))
        appendPoints(to: active, in: store, count: 1)

        #expect(store.stoppedSessions().map(\.id) == [newer.id, older.id])
        #expect(store.stoppedSessionCount() == 2)
    }

    @Test("deleting an unsent recording takes its points and laps with it")
    func deleteCascades() throws {
        let store = RecordingStore(inMemory: true)
        let session = store.createSession(startedAt: startedAt)
        appendPoints(to: session, in: store, count: 2)
        store.appendLap(to: session, ordinal: 1, endedAt: startedAt, cumulativeDistance: 0, cumulativeElapsed: 0)
        store.finish(session, stats: .zero)

        store.delete(session)

        #expect(store.stoppedSessions().isEmpty)
        #expect(try store.viewContext.count(for: NSFetchRequest<RecordingPoint>(entityName: "RecordingPoint")) == 0)
        #expect(try store.viewContext.count(for: NSFetchRequest<RecordingLap>(entityName: "RecordingLap")) == 0)
    }

    private func appendPoints(to session: RecordingSession, in store: RecordingStore, count: Int, secondsApart: TimeInterval = 1) {
        for index in 0..<count {
            store.appendPoint(
                to: session,
                timestamp: startedAt.addingTimeInterval(Double(index) * secondsApart),
                latitude: 48.8566 + Double(index) * 0.001,
                longitude: 2.3522,
                elevation: nil,
                speed: 0,
                horizontalAccuracy: 5,
                lap: 1
            )
        }
    }

    /// The wire format is DEFLATE + base64; unwrap it to read the JSON back.
    private func decode(_ handoff: RecordingHandoff) throws -> [String: Any] {
        let compressed = try #require(Data(base64Encoded: try handoff.encoded()))
        let capacity = 1 << 20
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        let json = try JSONSerialization.jsonObject(with: output.prefix(written))
        return try #require(json as? [String: Any])
    }
}

/// Every shipped model version may still hold an unsent recording when the app
/// upgrades. Adding entities, optional relationships and defaulted attributes is
/// inferrable, but `RecordingStore` turns a failed load into a `fatalError`, so an
/// uninferrable change would be a launch-crash loop rather than a lost recording —
/// worth pinning down.
@Suite("Recording store migration")
struct RecordingStoreMigrationTests {
    @Test("a store written by the previous model version migrates in place", arguments: ["Recording", "Recording 2"])
    func migratesFromPreviousVersion(version: String) throws {
        let momd = try #require(Bundle.main.url(forResource: "Recording", withExtension: "momd"))
        let previous = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("\(version).mom")))
        let current = try #require(NSManagedObjectModel(contentsOf: momd))

        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let sessionID = UUID()
        // Insert by entity name, not `RecordingSession(context:)`: two models are
        // loaded in this process and `+entity` can't tell which one the subclass
        // belongs to.
        try withContainer(model: previous, at: storeURL) { context in
            let session = NSEntityDescription.insertNewObject(forEntityName: "RecordingSession", into: context)
            session.setValue(sessionID, forKey: "id")
            session.setValue(Date(), forKey: "startedAt")
            session.setValue(RecordingState.stopped.rawValue, forKey: "state")
            session.setValue(Int16(1), forKey: "lapCount")
            for index in 0..<4 {
                let point = NSEntityDescription.insertNewObject(forEntityName: "RecordingPoint", into: context)
                point.setValue(Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 10), forKey: "timestamp")
                point.setValue(48.8566 + Double(index) * 0.001, forKey: "latitude")
                point.setValue(2.3522, forKey: "longitude")
                point.setValue(session, forKey: "session")
            }
            try context.save()
        }

        try withContainer(model: current, at: storeURL) { context in
            // Listed as unsent, through the same query the list uses.
            let sessions = try context.fetch(RecordingStore.stoppedSessionsRequest())
            #expect(sessions.map(\.id) == [sessionID])
            // The relationship the lap-less model lacked: reading it is what aborted.
            #expect(sessions.first?.lapBoundaries.isEmpty == true)
            // Stopped before the totals were stored: still unsent, with derived totals.
            #expect(sessions.first?.stoppedAt == nil)
            #expect(sessions.first?.finalStats.elapsed == 30)
        }
    }

    private func withContainer(
        model: NSManagedObjectModel,
        at url: URL,
        body: (NSManagedObjectContext) throws -> Void
    ) throws {
        let container = NSPersistentContainer(name: "Recording", managedObjectModel: model)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        try body(container.viewContext)
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
