package fr.armandmgt.velo.features.record

import android.app.Application
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import fr.armandmgt.velo.features.record.data.RecordingDao
import fr.armandmgt.velo.features.record.data.RecordingDatabase
import fr.armandmgt.velo.features.record.data.RecordingLapEntity
import fr.armandmgt.velo.features.record.data.RecordingPointEntity
import fr.armandmgt.velo.features.record.data.RecordingSessionEntity
import fr.armandmgt.velo.features.record.data.RecordingState
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A stopped recording must be sendable long after Arrêter — after a failed review
 * page or a process kill — so its handoff is rebuilt from the store. Mirrors the
 * iOS `UnsentRecordingsTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class UnsentRecordingsTest {
    private lateinit var db: RecordingDatabase
    private lateinit var dao: RecordingDao

    private val startedAt = 1_700_000_000_000L

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), RecordingDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.recordingDao()
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun `a handoff rebuilt from a stored session carries the totals stored at Arrêter`() = runBlocking {
        dao.insertSession(session("ride", sport = Sport.TRAIL_RUN))
        insertPoints("ride", count = 3)
        dao.insertLap(RecordingLapEntity(sessionId = "ride", ordinal = 1, endedAt = startedAt + 60_000, cumulativeDistance = 120.0, cumulativeElapsed = 60.0))
        dao.finish("ride", distance = 2_345.0, elapsed = 754.0, movingTime = 600.0, averageSpeed = 3.9, stoppedAt = startedAt + 800_000)

        val handoff = RecordingHandoff.load(dao, "ride", fallbackSport = Sport.BIKE)!!

        assertEquals("ride", handoff.recordingUuid)
        assertEquals("trail_run", handoff.sport)
        assertEquals(RecordingHandoff.Stats(distance = 2_345.0, elapsed = 754.0, movingTime = 600.0, averageSpeed = 3.9), handoff.stats)
        assertEquals(3, handoff.points.size)
        assertEquals(1, handoff.laps.size)
        assertTrue(RecordingHandoff.encode(handoff).isNotEmpty())
    }

    @Test
    fun `a session stopped without stored totals falls back to totals derived from its points`() = runBlocking {
        dao.insertSession(session("legacy", state = RecordingState.STOPPED))
        // ~111 m per 0.001° of latitude, one fix every 10 s: moving the whole way.
        insertPoints("legacy", count = 4, secondsApart = 10)

        val handoff = RecordingHandoff.load(dao, "legacy", fallbackSport = Sport.HIKE)!!

        assertEquals(30.0, handoff.stats.elapsed, 0.0)
        assertEquals(30.0, handoff.stats.movingTime, 0.0)
        assertEquals(333.6, handoff.stats.distance, 3.0)
        assertEquals(handoff.stats.distance / 30, handoff.stats.averageSpeed, 1e-9)
        assertEquals("hike", handoff.sport)
    }

    @Test
    fun `the fallback prefers the running temps écoulé snapshot to the span of the points`() = runBlocking {
        dao.insertSession(session("orphan", state = RecordingState.STOPPED, sport = Sport.BIKE))
        insertPoints("orphan", count = 4, secondsApart = 10)
        dao.updateProgress("orphan", elapsed = 42.0, distance = 0.0, movingTime = 0.0, averageSpeed = 0.0)

        val handoff = RecordingHandoff.load(dao, "orphan", fallbackSport = Sport.HIKE)!!

        assertEquals(42.0, handoff.stats.elapsed, 0.0)
        assertEquals("bike", handoff.sport)
    }

    @Test
    fun `only stopped sessions with points are unsent, newest first`() = runBlocking {
        dao.insertSession(session("older", startedAt = startedAt, state = RecordingState.STOPPED))
        insertPoints("older", count = 1)
        dao.insertSession(session("newer", startedAt = startedAt + 3_600_000, state = RecordingState.STOPPED))
        insertPoints("newer", count = 1)
        dao.insertSession(session("empty", startedAt = startedAt + 5_400_000, state = RecordingState.STOPPED))
        dao.insertSession(session("active", startedAt = startedAt + 7_200_000))
        insertPoints("active", count = 1)

        assertEquals(listOf("newer", "older"), dao.stoppedSessions().first().map { it.id })
        assertEquals(listOf("newer", "older"), dao.unsentRecordings(Sport.BIKE).first().map { it.id })
    }

    @Test
    fun `deleting an unsent recording takes its points and laps with it`() = runBlocking {
        dao.insertSession(session("ride", state = RecordingState.STOPPED))
        insertPoints("ride", count = 2)
        dao.insertLap(RecordingLapEntity(sessionId = "ride", ordinal = 1, endedAt = startedAt, cumulativeDistance = 0.0, cumulativeElapsed = 0.0))

        dao.deleteSession("ride")

        assertTrue(dao.stoppedSessions().first().isEmpty())
        assertTrue(dao.pointsFor("ride").isEmpty())
        assertTrue(dao.lapsFor("ride").isEmpty())
        assertNull(RecordingHandoff.load(dao, "ride", Sport.BIKE))
    }

    /**
     * A phone upgrading from version 2 may be holding exactly the recording this
     * change exists to rescue, and Room has no destructive fallback configured.
     */
    @Test
    fun `a version 2 store migrates and its unsent recording is listed`() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Application>()
        val file = context.getDatabasePath("migration-test.db").apply { parentFile?.mkdirs(); delete() }
        SQLiteDatabase.openOrCreateDatabase(file, null).use { v2 ->
            VERSION_2_SCHEMA.forEach(v2::execSQL)
            v2.execSQL("INSERT INTO recording_sessions (id, startedAt, state, lapCount) VALUES ('legacy', $startedAt, 2, 1)")
            for (i in 0 until 4) {
                v2.execSQL(
                    "INSERT INTO recording_points (sessionId, timestamp, latitude, longitude, speed, horizontalAccuracy, lap) " +
                        "VALUES ('legacy', ${startedAt + i * 10_000}, ${48.8566 + i * 0.001}, 2.3522, 0, 5, 1)",
                )
            }
            v2.version = 2
        }

        val migrated = Room.databaseBuilder(context, RecordingDatabase::class.java, file.path)
            .addMigrations(*RecordingDatabase.MIGRATIONS)
            .allowMainThreadQueries()
            .build()
        try {
            val migratedDao = migrated.recordingDao()
            val unsent = migratedDao.unsentRecordings(Sport.BIKE).first()
            assertEquals(listOf("legacy"), unsent.map { it.id })
            assertEquals(30.0, unsent.single().stats.elapsed, 0.0)
            assertNotNull(RecordingHandoff.load(migratedDao, "legacy", Sport.BIKE))
        } finally {
            migrated.close()
            file.delete()
        }
    }

    private fun session(
        id: String,
        startedAt: Long = this.startedAt,
        state: RecordingState = RecordingState.RECORDING,
        sport: Sport? = null,
    ) = RecordingSessionEntity(id = id, startedAt = startedAt, state = state.ordinal, sport = sport?.wire)

    private suspend fun insertPoints(sessionId: String, count: Int, secondsApart: Long = 1) {
        for (i in 0 until count) {
            dao.insertPoint(
                RecordingPointEntity(
                    sessionId = sessionId,
                    timestamp = startedAt + i * secondsApart * 1000,
                    latitude = 48.8566 + i * 0.001,
                    longitude = 2.3522,
                ),
            )
        }
    }

    private companion object {
        /** The schema Room generated at version 2, before the session stored its totals. */
        val VERSION_2_SCHEMA = listOf(
            "CREATE TABLE IF NOT EXISTS `recording_sessions` (`id` TEXT NOT NULL, `startedAt` INTEGER NOT NULL, " +
                "`state` INTEGER NOT NULL, `lapCount` INTEGER NOT NULL, PRIMARY KEY(`id`))",
            "CREATE TABLE IF NOT EXISTS `recording_points` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "`sessionId` TEXT NOT NULL, `timestamp` INTEGER NOT NULL, `latitude` REAL NOT NULL, `longitude` REAL NOT NULL, " +
                "`elevation` REAL, `speed` REAL NOT NULL, `horizontalAccuracy` REAL NOT NULL, `lap` INTEGER NOT NULL, " +
                "`heartRate` INTEGER, `cadence` REAL, `power` REAL, FOREIGN KEY(`sessionId`) REFERENCES " +
                "`recording_sessions`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )",
            "CREATE INDEX IF NOT EXISTS `index_recording_points_sessionId_timestamp` ON `recording_points` (`sessionId`, `timestamp`)",
            "CREATE TABLE IF NOT EXISTS `recording_laps` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "`sessionId` TEXT NOT NULL, `ordinal` INTEGER NOT NULL, `endedAt` INTEGER NOT NULL, " +
                "`cumulativeDistance` REAL NOT NULL, `cumulativeElapsed` REAL NOT NULL, FOREIGN KEY(`sessionId`) " +
                "REFERENCES `recording_sessions`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )",
            "CREATE INDEX IF NOT EXISTS `index_recording_laps_sessionId_ordinal` ON `recording_laps` (`sessionId`, `ordinal`)",
        )
    }
}
