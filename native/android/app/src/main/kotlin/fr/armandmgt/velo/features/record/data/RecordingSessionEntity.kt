package fr.armandmgt.velo.features.record.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * An in-progress (or finished) recording session.
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
    /** [RecordingState] ordinal: 0 recording, 1 paused, 2 stopped, 3 auto-paused. */
    val state: Int,
    /** Current lap ordinal (1-based); bumped by "Tour". */
    val lapCount: Int = 1,
)

/**
 * Persisted recording state. Ordinals match the iOS Core Data `state` Int16.
 *
 * [AUTO_PAUSED] is appended after [STOPPED] rather than slotted beside [PAUSED]
 * (ADR 0002): [fromOrdinal] resolves by position, so renumbering [STOPPED] would
 * invalidate stored rows on both platforms.
 */
enum class RecordingState {
    RECORDING,
    PAUSED,
    STOPPED,
    AUTO_PAUSED;

    /** Paused either way — the clock is frozen and incoming fixes are dropped. */
    val isPaused: Boolean get() = this == PAUSED || this == AUTO_PAUSED

    companion object {
        fun fromOrdinal(value: Int): RecordingState = entries[value]
    }
}
