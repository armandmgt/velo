package fr.armandmgt.velo.features.record.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

/** Reads/writes for the recording store. All suspending — Room runs them off the main thread. */
@Dao
interface RecordingDao {
    @Insert
    suspend fun insertSession(session: RecordingSessionEntity)

    @Query("UPDATE recording_sessions SET state = :state WHERE id = :id")
    suspend fun updateState(id: String, state: Int)

    @Query("UPDATE recording_sessions SET lapCount = :lapCount WHERE id = :id")
    suspend fun updateLapCount(id: String, lapCount: Int)

    /** The single active session (state != STOPPED), or null. Most recent wins. */
    @Query("SELECT * FROM recording_sessions WHERE state != 2 ORDER BY startedAt DESC LIMIT 1")
    suspend fun activeSession(): RecordingSessionEntity?

    /** Finalize any leftover active session — preserves the single-active invariant on a fresh start. */
    @Query("UPDATE recording_sessions SET state = 2 WHERE state != 2")
    suspend fun finalizeOrphans()

    @Insert
    suspend fun insertPoint(point: RecordingPointEntity)

    @Query("SELECT * FROM recording_points WHERE sessionId = :sessionId ORDER BY timestamp ASC")
    suspend fun pointsFor(sessionId: String): List<RecordingPointEntity>

    @Query("SELECT COUNT(*) FROM recording_points WHERE sessionId = :sessionId")
    suspend fun pointCountFor(sessionId: String): Int

    /** Clear a session (and its points, via the FK cascade) after a successful upload. */
    @Query("DELETE FROM recording_sessions WHERE id = :id")
    suspend fun deleteSession(id: String)
}
