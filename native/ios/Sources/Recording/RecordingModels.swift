import CoreData
import Foundation

/// Core Data managed objects backing an in-progress recording (#41, S3 — #51).
///
/// Hand-written subclasses so the schema stays fully deterministic under our
/// xcodegen/xcodebuild workflow — no reliance on Xcode's DerivedSources class
/// generation. The model expresses this "manual / none" codegen by *omitting* the
/// `codeGenerationType` attribute in `Recording.xcdatamodel/contents`. Do NOT set
/// it to the literal `codeGenerationType="manual"`: this toolchain's data-model
/// code generator asserts ("Unexpected code generation type in xml: manual") and
/// aborts the build. (Editing the model in the Xcode GUI may re-add it — strip it
/// back out if so.)

/// The lifecycle of a recording. Persisted as `RecordingSession.state` (Int16).
/// "Active" — what the single-active invariant and kill-recovery key on — means
/// any state that isn't `.stopped`.
enum RecordingState: Int16 {
    case recording = 0
    case paused = 1
    case stopped = 2

    var isActive: Bool { self != .stopped }
}

/// One recording attempt: a start time, a coarse state, a lap counter, and its
/// ordered points. Only one session is ever non-`.stopped` at a time.
@objc(RecordingSession)
final class RecordingSession: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var startedAt: Date
    @NSManaged var state: Int16
    /// Current lap ordinal (1-based). Tapping "Tour" bumps it; new points inherit it.
    @NSManaged var lapCount: Int16
    @NSManaged var points: NSSet?

    var recordingState: RecordingState {
        get { RecordingState(rawValue: state) ?? .stopped }
        set { state = newValue.rawValue }
    }

    /// Points oldest-first. The store sorts on `timestamp`, which is also the
    /// recording order at ~1 Hz.
    var orderedPoints: [RecordingPoint] {
        let set = points as? Set<RecordingPoint> ?? []
        return set.sorted { $0.timestamp < $1.timestamp }
    }
}

/// A single per-second fix. GPS fields are always present; sensor fields
/// (`heartRate`/`cadence`/`power`) are nullable-for-later via a `has*` companion
/// flag, keeping the stored attributes plain scalars.
@objc(RecordingPoint)
final class RecordingPoint: NSManagedObject {
    @NSManaged var timestamp: Date
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var elevation: Double
    @NSManaged var hasElevation: Bool
    @NSManaged var speed: Double
    @NSManaged var horizontalAccuracy: Double
    /// The lap ordinal this point belongs to (mirrors `RecordingSession.lapCount`
    /// at the time it was recorded). Laps are markers for now (S3).
    @NSManaged var lap: Int16
    @NSManaged var heartRate: Int16
    @NSManaged var hasHeartRate: Bool
    @NSManaged var cadence: Double
    @NSManaged var hasCadence: Bool
    @NSManaged var power: Double
    @NSManaged var hasPower: Bool
    @NSManaged var session: RecordingSession?
}
