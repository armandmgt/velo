import CoreData
import Foundation

/// The Core Data stack for in-progress recordings.
///
/// Thin wrapper over an `NSPersistentContainer` loaded from the bundled
/// `Recording.momd`. Everything runs on the `viewContext` (main queue): at the
/// recording's ~1 Hz cadence the writes are trivial, and a single context keeps
/// the live stats and the store trivially consistent.
///
/// Durability — surviving a force-quit — comes from saving after
/// every appended point — each `save()` flushes the SQLite WAL, so a kill loses
/// at most the in-flight fix.
final class RecordingStore {
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init() {
        guard let modelURL = Bundle.main.url(forResource: "Recording", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("[RecordingStore] Recording.momd not found in bundle")
        }
        container = NSPersistentContainer(name: "Recording", managedObjectModel: model)
        container.loadPersistentStores { _, error in
            if let error {
                // A corrupt/incompatible store is unrecoverable here; fail loudly
                // in development rather than silently dropping recordings.
                fatalError("[RecordingStore] failed to load store: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Sessions

    /// Start a fresh active session (`.recording`, lap 1).
    @discardableResult
    func createSession(startedAt: Date = Date()) -> RecordingSession {
        let session = RecordingSession(context: viewContext)
        session.id = UUID()
        session.startedAt = startedAt
        session.recordingState = .recording
        session.lapCount = 1
        save()
        return session
    }

    /// The single non-`.stopped` session, if one exists (e.g. orphaned by a kill).
    func activeSession() -> RecordingSession? {
        let request = NSFetchRequest<RecordingSession>(entityName: "RecordingSession")
        request.predicate = NSPredicate(format: "state != %d", RecordingState.stopped.rawValue)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    // MARK: - Points

    /// Append one fix to a session. Sensor fields are left absent (nullable for
    /// later); the `has*` flags stay false.
    @discardableResult
    func appendPoint(
        to session: RecordingSession,
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        elevation: Double?,
        speed: Double,
        horizontalAccuracy: Double,
        lap: Int16
    ) -> RecordingPoint {
        let point = RecordingPoint(context: viewContext)
        point.timestamp = timestamp
        point.latitude = latitude
        point.longitude = longitude
        if let elevation {
            point.elevation = elevation
            point.hasElevation = true
        }
        point.speed = speed
        point.horizontalAccuracy = horizontalAccuracy
        point.lap = lap
        point.session = session
        save()
        return point
    }

    // MARK: - Laps

    /// Close a lap: snapshot the cumulative totals at the instant Tour was tapped
    /// `LapSplits` differences consecutive rows into splits.
    @discardableResult
    func appendLap(
        to session: RecordingSession,
        ordinal: Int16,
        endedAt: Date,
        cumulativeDistance: Double,
        cumulativeElapsed: TimeInterval
    ) -> RecordingLap {
        let lap = RecordingLap(context: viewContext)
        lap.ordinal = ordinal
        lap.endedAt = endedAt
        lap.cumulativeDistance = cumulativeDistance
        lap.cumulativeElapsed = cumulativeElapsed
        lap.session = session
        save()
        return lap
    }

    /// Delete a finalized session (its points cascade away) — used to clear the
    /// local recording after a successful upload.
    func delete(_ session: RecordingSession) {
        viewContext.delete(session)
        save()
    }

    // MARK: - Persistence

    func save() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            NSLog("[RecordingStore] save failed: \(error.localizedDescription)")
        }
    }
}
