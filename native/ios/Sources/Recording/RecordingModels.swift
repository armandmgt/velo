import CoreData
import Foundation

/// Core Data managed objects backing an in-progress recording.
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
///
/// `autoPaused` is deliberately **appended at 3** rather than slotted next to
/// `paused`: Android's mirror enum resolves by ordinal (`entries[value]`), so
/// renumbering `stopped` would invalidate stored rows on both platforms.
enum RecordingState: Int16 {
    case recording = 0
    case paused = 1
    case stopped = 2
    case autoPaused = 3

    var isActive: Bool { self != .stopped }

    /// Paused either way — the rider's clock is frozen and fixes are dropped.
    var isPaused: Bool { self == .paused || self == .autoPaused }
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
    /// Closed-lap boundaries, one per Tour tap. See `RecordingLap`.
    @NSManaged var laps: NSSet?

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

    /// The closed laps as plain values, ready for `LapSplits.splits(boundaries:…)`.
    var lapBoundaries: [LapBoundary] {
        let set = laps as? Set<RecordingLap> ?? []
        return set
            .map { LapBoundary(ordinal: Int($0.ordinal), cumulativeDistance: $0.cumulativeDistance, cumulativeElapsed: $0.cumulativeElapsed) }
            .sorted { $0.ordinal < $1.ordinal }
    }
}

/// One closed lap: the cumulative distance and temps écoulé at the instant the
/// rider tapped Tour.
///
/// Storing cumulative snapshots rather than per-lap deltas keeps the write O(1)
/// and exact; `LapSplits` turns consecutive rows into the splits the UI shows.
/// Laps never leave the device.
@objc(RecordingLap)
final class RecordingLap: NSManagedObject {
    /// The lap this row closes (1-based).
    @NSManaged var ordinal: Int16
    @NSManaged var endedAt: Date
    @NSManaged var cumulativeDistance: Double
    @NSManaged var cumulativeElapsed: TimeInterval
    @NSManaged var session: RecordingSession?
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
    /// at the time it was recorded). Laps are markers for now.
    @NSManaged var lap: Int16
    @NSManaged var heartRate: Int16
    @NSManaged var hasHeartRate: Bool
    @NSManaged var cadence: Double
    @NSManaged var hasCadence: Bool
    @NSManaged var power: Double
    @NSManaged var hasPower: Bool
    @NSManaged var session: RecordingSession?
}
