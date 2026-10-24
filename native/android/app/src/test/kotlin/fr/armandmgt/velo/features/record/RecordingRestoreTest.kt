package fr.armandmgt.velo.features.record

import android.app.Application
import android.content.Intent
import android.location.Location
import android.os.Looper
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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config

/**
 * A recording the process was killed during comes back paused, with the totals,
 * Tours and trace it had, and carries on into the same session. Mirrors the iOS
 * `RecordingRestoreTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class RecordingRestoreTest {
    private lateinit var db: RecordingDatabase
    private lateinit var dao: RecordingDao
    private var service: ServiceController<RecordingService>? = null

    private val startedAt = 1_700_000_000_000L

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), RecordingDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.recordingDao()
        RecordingDatabase.replaceForTesting(db)
    }

    @After
    fun tearDown() {
        service?.destroy()
        RecordingDatabase.replaceForTesting(null)
        db.close()
    }

    // Accumulator

    @Test
    fun `totals restored from a snapshot carry on without bridging the dead span`() {
        val accumulator = RecordingStatsAccumulator(distance = 2_345.0, movingSeconds = 600.0)

        accumulator.add(fix(latitude = 48.9, seconds = 9_000.0))
        assertEquals(2_345.0, accumulator.distance, 0.0)
        assertEquals(600.0, accumulator.movingSeconds, 0.0)

        accumulator.add(fix(latitude = 48.901, seconds = 9_010.0))
        assertEquals(2_345.0 + 111.2, accumulator.distance, 2.0)
        assertEquals(610.0, accumulator.movingSeconds, 0.0)
    }

    @Test
    fun `replaying stored points gives what live folding gave, and ends unanchored`() {
        val points = points("ride", count = 4, secondsApart = 10)
        val live = RecordingStatsAccumulator()
        points.forEach { live.add(fix(it.latitude, (it.timestamp - startedAt) / 1000.0)) }

        val replayed = RecordingStatsAccumulator.replaying(points)

        assertEquals(live.distance, replayed.distance, 1e-9)
        assertEquals(live.movingSeconds, replayed.movingSeconds, 0.0)
        replayed.add(fix(latitude = 49.5, seconds = 3_600.0))
        assertEquals(live.distance, replayed.distance, 1e-9)
    }

    @Test
    fun `a session restores from its running snapshot, not from its points`() {
        val session = session("ride").copy(distance = 150.0, movingTime = 20.0)

        val accumulator = session.restoredAccumulator(points("ride", count = 4, secondsApart = 10))

        assertEquals(150.0, accumulator.distance, 0.0)
        assertEquals(20.0, accumulator.movingSeconds, 0.0)
    }

    @Test
    fun `an orphan from a build that kept no snapshot replays its points`() {
        val accumulator = session("ride").restoredAccumulator(points("ride", count = 4, secondsApart = 10))

        assertEquals(333.6, accumulator.distance, 3.0)
        assertEquals(30.0, accumulator.movingSeconds, 0.0)
    }

    // Store

    @Test
    fun `the running totals are kept with every point, and an open session reads as in progress`() = runBlocking {
        assertFalse(dao.hasActiveSession().first())
        dao.insertSession(session("ride"))
        assertTrue(dao.hasActiveSession().first())

        dao.updateProgress("ride", elapsed = 12.0, distance = 80.0, movingTime = 10.0, averageSpeed = 8.0)

        val stored = dao.session("ride")!!
        assertEquals(12.0, stored.elapsed, 0.0)
        assertEquals(80.0, stored.distance, 0.0)
        assertEquals(10.0, stored.movingTime, 0.0)
        assertNull(stored.stoppedAt)
    }

    // Service

    @Test
    fun `a killed recording restores paused, with its clock, totals, Tours, sport and trace`() = runBlocking {
        killedRecording(RecordingState.RECORDING)

        val ui = startService().uiState.value

        assertEquals(RecordingState.PAUSED, ui.recordingState)
        assertFalse(ui.armed)
        assertEquals(Sport.TRAIL_RUN, ui.sport)
        assertEquals(754L, ui.elapsedSeconds)
        assertEquals(2_345.0, ui.distanceMeters, 0.0)
        assertEquals(600.0, ui.movingSeconds, 0.0)
        assertEquals(4, ui.pointCount)
        assertEquals(4, ui.routePoints.size)
        assertEquals(2, ui.lap)
        assertEquals(listOf(LapBoundary(1, 1_000.0, 300.0)), ui.lapBoundaries)
        assertEquals(RecordingState.PAUSED.ordinal, dao.session("ride")!!.state)
    }

    @Test
    fun `a recording killed while auto-paused restores as a manual pause`() = runBlocking {
        killedRecording(RecordingState.AUTO_PAUSED)

        val ui = startService().uiState.value

        assertEquals(RecordingState.PAUSED, ui.recordingState)
        assertEquals(RecordingState.PAUSED.ordinal, dao.session("ride")!!.state)
    }

    @Test
    fun `Démarrer can't open a second session beside a restored one`() = runBlocking {
        killedRecording(RecordingState.RECORDING)
        val binder = startService()

        binder.start(Sport.BIKE)
        settle { false }

        assertEquals("ride", binder.sessionId())
        assertEquals(RecordingState.PAUSED, binder.uiState.value.recordingState)
        assertEquals("ride", dao.activeSession()!!.id)
        assertEquals(Sport.TRAIL_RUN, binder.uiState.value.sport)
    }

    @Test
    fun `Reprendre records into the same session from the restored clock`() = runBlocking {
        killedRecording(RecordingState.RECORDING)
        val binder = startService()

        binder.resume()
        settle { runBlocking { dao.session("ride")!!.state } == RecordingState.RECORDING.ordinal }

        val ui = binder.uiState.value
        assertEquals(RecordingState.RECORDING, ui.recordingState)
        assertEquals("ride", binder.sessionId())
        assertTrue(ui.elapsedSeconds in 754L..755L)
        assertEquals(2_345.0, dao.session("ride")!!.distance, 0.0)
    }

    @Test
    fun `with nothing interrupted the service opens armed`() {
        val ui = startService().uiState.value

        assertTrue(ui.armed)
        assertNull(ui.sport)
    }

    // Helpers

    /** Starts the service and waits for its restore to land. */
    private fun startService(): RecordingService.LocalBinder {
        val controller = Robolectric.buildService(RecordingService::class.java).create()
        service = controller
        val binder = controller.get().onBind(Intent()) as RecordingService.LocalBinder
        settle { binder.sessionId() != null }
        return binder
    }

    /** Runs the main looper while the service's IO work finishes, up to a second. */
    private fun settle(done: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 1_000
        while (System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            if (done()) return
            Thread.sleep(10)
        }
    }

    /**
     * An active session as a kill leaves it: four fixes, one Tour closed, and
     * running snapshots that no longer match a straight replay of the points.
     */
    private suspend fun killedRecording(state: RecordingState) {
        dao.insertSession(
            session("ride", state = state, sport = Sport.TRAIL_RUN).copy(
                lapCount = 2,
                elapsed = 754.0,
                distance = 2_345.0,
                movingTime = 600.0,
                averageSpeed = 2_345.0 / 600,
            ),
        )
        points("ride", count = 4, secondsApart = 10).forEach { dao.insertPoint(it) }
        dao.insertLap(
            RecordingLapEntity(sessionId = "ride", ordinal = 1, endedAt = startedAt + 300_000, cumulativeDistance = 1_000.0, cumulativeElapsed = 300.0),
        )
    }

    private fun session(
        id: String,
        state: RecordingState = RecordingState.RECORDING,
        sport: Sport? = null,
    ) = RecordingSessionEntity(id = id, startedAt = startedAt, state = state.ordinal, sport = sport?.wire)

    private fun points(sessionId: String, count: Int, secondsApart: Long) = (0 until count).map { i ->
        RecordingPointEntity(
            sessionId = sessionId,
            timestamp = startedAt + i * secondsApart * 1000,
            latitude = 48.8566 + i * 0.001,
            longitude = 2.3522,
        )
    }

    private fun fix(latitude: Double, seconds: Double) = Location("test").apply {
        this.latitude = latitude
        longitude = 2.3522
        time = startedAt + (seconds * 1000).toLong()
    }
}
