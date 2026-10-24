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

    @Query(
        "UPDATE recording_sessions SET state = :state, elapsed = :elapsed, distance = :distance, " +
            "movingTime = :movingTime, averageSpeed = :averageSpeed WHERE id = :id",
    )
    suspend fun updateState(
        id: String,
        state: Int,
        elapsed: Double,
        distance: Double,
        movingTime: Double,
        averageSpeed: Double,
    )

    /** The running totals a killed recording is restored from, kept current with every point. */
    @Query(
        "UPDATE recording_sessions SET elapsed = :elapsed, distance = :distance, " +
            "movingTime = :movingTime, averageSpeed = :averageSpeed WHERE id = :id",
    )
    suspend fun updateProgress(id: String, elapsed: Double, distance: Double, movingTime: Double, averageSpeed: Double)

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

    /** Whether a recording is in progress, including one a kill left behind before the service restores it. */
    @Query("SELECT EXISTS(SELECT 1 FROM recording_sessions WHERE state != 2)")
    fun hasActiveSession(): Flow<Boolean>

    @Insert
    suspend fun insertPoint(point: RecordingPointEntity)

    @Query("SELECT * FROM recording_points WHERE sessionId = :sessionId ORDER BY timestamp ASC")
    suspend fun pointsFor(sessionId: String): List<RecordingPointEntity>

    @Insert
    suspend fun insertLap(lap: RecordingLapEntity)

    /** A session's closed laps, oldest first — the boundaries splits are differenced from. */
    @Query("SELECT * FROM recording_laps WHERE sessionId = :sessionId ORDER BY ordinal ASC")
    suspend fun lapsFor(sessionId: String): List<RecordingLapEntity>

    /** Clear a session (and its points and laps, via the FK cascade) after a successful upload. */
    @Query("DELETE FROM recording_sessions WHERE id = :id")
    suspend fun deleteSession(id: String)
}
