package fr.armandmgt.velo.features.record.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * An in-progress (or finished) recording session (#56).
 *
 * Mirrors the iOS Core Data `RecordingSession` entity so the two platforms stay
 * in lock-step: exactly one session is active at a time (state != STOPPED), and a
 * session outlives the recording screen / process — it lives here in Room until
 * it's uploaded and discarded (upload is later work).
 */
@Entity(tableName = "recording_sessions")
data class RecordingSessionEntity(
    /** UUID string. */
    @PrimaryKey val id: String,
    /** Wall-clock start, epoch milliseconds. */
    val startedAt: Long,
    /** [RecordingState] ordinal: 0 recording, 1 paused, 2 stopped. */
    val state: Int,
    /** Current lap ordinal (1-based); bumped by "Tour". */
    val lapCount: Int = 1,
)

/** Persisted recording state. Ordinals match the iOS Core Data `state` Int16. */
enum class RecordingState {
    RECORDING,
    PAUSED,
    STOPPED;

    companion object {
        fun fromOrdinal(value: Int): RecordingState = entries[value]
    }
}
