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

        let handoff = RecordingHandoff(session: session, stats: .zero, sport: .bike)
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

        let handoff = RecordingHandoff(session: session, stats: .zero, sport: .bike)
        #expect(try !handoff.encoded().isEmpty)
    }
}

/// The shipped build loaded the lap-less `Recording` model, so installs upgrading
/// to `Recording 2` carry a store built on the old schema. Adding an entity and an
/// optional to-many relationship is inferrable, but `RecordingStore` turns a failed
/// load into a `fatalError`, so an uninferrable change would be a launch-crash
/// loop rather than a lost recording — worth pinning down.
@Suite("Recording store migration")
struct RecordingStoreMigrationTests {
    @Test("a store written by the previous model version migrates in place")
    func migratesFromPreviousVersion() throws {
        let momd = try #require(Bundle.main.url(forResource: "Recording", withExtension: "momd"))
        let previous = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Recording.mom")))
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
            try context.save()
        }

        try withContainer(model: current, at: storeURL) { context in
            let request = NSFetchRequest<RecordingSession>(entityName: "RecordingSession")
            let sessions = try context.fetch(request)
            #expect(sessions.map(\.id) == [sessionID])
            // The relationship the lap-less model lacked: reading it is what aborted.
            #expect(sessions.first?.lapBoundaries.isEmpty == true)
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
