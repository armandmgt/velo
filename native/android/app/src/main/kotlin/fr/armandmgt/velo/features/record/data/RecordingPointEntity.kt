package fr.armandmgt.velo.features.record.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One GPS fix in a recording, stored oldest-first by [timestamp] (#56).
 *
 * Mirrors the iOS Core Data `RecordingPoint` shape. iOS marks optional sensors
 * with companion `has*` booleans (Core Data has no nullable scalars); Room does,
 * so the sensor fields are plain nullable columns — wired to real sensors later.
 * [speed] is the per-segment speed (m/s) computed on device, matching the GPX the
 * server expects.
 */
@Entity(
    tableName = "recording_points",
    foreignKeys = [
        ForeignKey(
            entity = RecordingSessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["sessionId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["sessionId", "timestamp"])],
)
data class RecordingPointEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sessionId: String,
    /** Fix time, epoch milliseconds. */
    val timestamp: Long,
    val latitude: Double,
    val longitude: Double,
    /** Altitude in meters, or null when the fix had no valid vertical accuracy. */
    val elevation: Double? = null,
    /** Segment speed in m/s. */
    val speed: Double = 0.0,
    /** Horizontal accuracy in meters. */
    val horizontalAccuracy: Double = 0.0,
    /** Lap ordinal this point belongs to (denormalized from the session). */
    val lap: Int = 1,
    // Sensor fields — nullable, populated when sensors are wired up later (#56).
    val heartRate: Int? = null,
    val cadence: Double? = null,
    val power: Double? = null,
)
