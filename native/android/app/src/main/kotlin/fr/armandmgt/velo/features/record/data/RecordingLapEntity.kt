package fr.armandmgt.velo.features.record.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One closed lap: the cumulative distance and temps écoulé at the instant the
 * rider tapped Tour.
 *
 * Mirrors the iOS Core Data `RecordingLap`. Storing cumulative snapshots rather
 * than per-lap deltas keeps the write O(1) and exact; [fr.armandmgt.velo.features.record.LapSplits]
 * turns consecutive rows into the splits the rider reads. Laps never leave the
 * device (ADR 0001) — these rows die with the session.
 */
@Entity(
    tableName = "recording_laps",
    foreignKeys = [
        ForeignKey(
            entity = RecordingSessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["sessionId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["sessionId", "ordinal"])],
)
data class RecordingLapEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sessionId: String,
    /** The lap this row closes (1-based). */
    val ordinal: Int,
    /** When Tour was tapped, epoch milliseconds. */
    val endedAt: Long,
    /** Total distance at that instant, meters. */
    val cumulativeDistance: Double,
    /** Temps écoulé at that instant, seconds. */
    val cumulativeElapsed: Double,
)
