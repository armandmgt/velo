package fr.armandmgt.velo.features.record.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * An in-progress (or finished) recording session.
 *
 * Mirrors the iOS Core Data `RecordingSession` entity so the two platforms stay
 * in lock-step: exactly one session is active at a time (state != STOPPED), and a
 * session outlives the recording screen / process — it lives here in Room until
 * the review commits its upload or the rider discards it. Any number of stopped
 * sessions may wait meanwhile: those are the unsent recordings.
 *
 * The totals are stored because only the shell can compute temps écoulé, so a
 * review rebuilt after the process is gone needs them from here.
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
    /** [fr.armandmgt.velo.features.record.Sport.wire]; null on sessions recorded before it was stored. */
    val sport: String? = null,
    /**
     * Temps écoulé, seconds. Kept current while recording (on every persisted
     * point and state change), and final once [stoppedAt] is set.
     */
    @ColumnInfo(defaultValue = "0") val elapsed: Double = 0.0,
    /**
     * Totals kept current like [elapsed], so a killed recording restores them
     * exactly, and final once [stoppedAt] is set. Meters, seconds, m/s.
     */
    @ColumnInfo(defaultValue = "0") val distance: Double = 0.0,
    @ColumnInfo(defaultValue = "0") val movingTime: Double = 0.0,
    @ColumnInfo(defaultValue = "0") val averageSpeed: Double = 0.0,
    /**
     * Arrêter, epoch milliseconds. A stopped session without it was finalized some
     * other way (an orphan, or a recording made before the totals were stored), so
     * its totals have to be derived from its points.
     */
    val stoppedAt: Long? = null,
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
