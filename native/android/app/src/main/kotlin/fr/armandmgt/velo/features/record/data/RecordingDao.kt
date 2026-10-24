package fr.armandmgt.velo.features.record.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/** Reads/writes for the recording store. All suspending — Room runs them off the main thread. */
@Dao
interface RecordingDao {
    @Insert
    suspend fun insertSession(session: RecordingSessionEntity)

    @Query("UPDATE recording_sessions SET state = :state, elapsed = :elapsed WHERE id = :id")
    suspend fun updateState(id: String, state: Int, elapsed: Double)

    @Query("UPDATE recording_sessions SET elapsed = :elapsed WHERE id = :id")
    suspend fun updateElapsed(id: String, elapsed: Double)

    /** Arrêter: store the totals the handoff carries and mark the session stopped. */
    @Query(
        "UPDATE recording_sessions SET state = 2, distance = :distance, elapsed = :elapsed, " +
            "movingTime = :movingTime, averageSpeed = :averageSpeed, stoppedAt = :stoppedAt WHERE id = :id",
    )
    suspend fun finish(
        id: String,
        distance: Double,
        elapsed: Double,
        movingTime: Double,
        averageSpeed: Double,
        stoppedAt: Long,
    )

    @Query("SELECT * FROM recording_sessions WHERE id = :id")
    suspend fun session(id: String): RecordingSessionEntity?

    /**
     * Unsent recordings, newest first: stopped sessions are only deleted once the
     * review commits or the rider discards them. One with no points has nothing to
     * send, so it isn't one.
     */
    @Query(
        "SELECT * FROM recording_sessions WHERE state = 2 " +
            "AND EXISTS (SELECT 1 FROM recording_points WHERE sessionId = recording_sessions.id) " +
            "ORDER BY startedAt DESC",
    )
    fun stoppedSessions(): Flow<List<RecordingSessionEntity>>

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

    @Insert
    suspend fun insertLap(lap: RecordingLapEntity)

    /** A session's closed laps, oldest first — the boundaries splits are differenced from. */
    @Query("SELECT * FROM recording_laps WHERE sessionId = :sessionId ORDER BY ordinal ASC")
    suspend fun lapsFor(sessionId: String): List<RecordingLapEntity>

    /** Clear a session (and its points and laps, via the FK cascade) after a successful upload. */
    @Query("DELETE FROM recording_sessions WHERE id = :id")
    suspend fun deleteSession(id: String)
}
