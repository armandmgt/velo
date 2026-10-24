package fr.armandmgt.velo.features.record

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.data.RecordingDao
import fr.armandmgt.velo.features.record.data.RecordingDatabase
import fr.armandmgt.velo.features.record.data.RecordingLapEntity
import fr.armandmgt.velo.features.record.data.RecordingPointEntity
import fr.armandmgt.velo.features.record.data.RecordingSessionEntity
import fr.armandmgt.velo.features.record.data.RecordingState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

/** A recorded fix as a plain lat/lng, for drawing the live map trace. Kept free of
 *  MapLibre types so the service (and its unit tests) don't depend on the map SDK. */
data class RoutePoint(val latitude: Double, val longitude: Double)

/** The live state the recording screen renders: GPS readout + derived stats. */
data class RecordingUiState(
    val recordingState: RecordingState = RecordingState.RECORDING,
    /** True before Démarrer: GPS is armed for readiness but nothing is recorded yet. */
    val armed: Boolean = true,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val accuracy: Float? = null,
    val pointCount: Int = 0,
    val lap: Int = 1,
    val elapsedSeconds: Long = 0,
    /**
     * Durée de déplacement — the stricter, speed-gated clock. Carried so the
     * handoff can send it precomputed: a paused recording drops its fixes, so
     * nothing downstream can separate it from temps écoulé.
     */
    val movingSeconds: Double = 0.0,
    val distanceMeters: Double = 0.0,
    val currentSpeedMps: Double = 0.0,
    val averageSpeedMps: Double = 0.0,
    /** The recorded trace so far, oldest-first, for the live map line (map-centric redesign). */
    val routePoints: List<RoutePoint> = emptyList(),
    /** Closed laps, oldest first — what the split sheet differences into splits. */
    val lapBoundaries: List<LapBoundary> = emptyList(),
    /** The open session's sport, which a restored recording brings back; null while armed. */
    val sport: Sport? = null,
)

/**
 * Foreground service that owns an in-progress recording ( skeleton; GPS;
 * persistence + live stats).
 *
 * It's the long-lived owner of the recording (the role iOS gives its
 * `RecordingController`): it streams Fused-Location fixes, persists each one to
 * the Room [RecordingDatabase], folds live stats from the fix stream, and exposes
 * the result as [uiState]. Running as a *started* `location` foreground service
 * means GPS keeps flowing — and points keep persisting — while the app is
 * backgrounded or the screen is off, with only While-Using
 * (`ACCESS_FINE_LOCATION`) permission. The recording screen binds purely to read
 * live state and drive the [LocalBinder] controls (pause/resume/lap/stop).
 *
 * Exactly one session is active (state != STOPPED) at a time. One a process kill
 * left behind is restored when the service is created, as a manual pause, so
 * Démarrer never has one to set aside (mirroring iOS's launch-time restore).
 */
class RecordingService : Service() {
    private val _uiState = MutableStateFlow(RecordingUiState())

    private val binder = LocalBinder()

    // One writer, so the store applies the running snapshots in the order they were taken.
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val dao: RecordingDao by lazy { RecordingDatabase.get(this).recordingDao() }

    private val fusedClient: FusedLocationProviderClient by lazy {
        LocationServices.getFusedLocationProviderClient(this)
    }

    private val heartRate: HeartRateMonitor by lazy { HeartRateMonitor.get(this) }

    // In-memory recording state — only touched on the main thread (location
    // callback, ticker, and binder controls all run there), so no locking needed.
    private var armed = false
    private var session: RecordingSessionEntity? = null
    private var sport: Sport? = null
    private var recordingState = RecordingState.RECORDING
    private var accumulator = RecordingStatsAccumulator()
    private var pointCount = 0
    private var lap = 1
    private var lastFixSpeed = 0.0
    private var lastPersistedSecond: Long? = null
    private var lastLatitude: Double? = null
    private var lastLongitude: Double? = null
    private var lastAccuracy: Float? = null

    /** The latest point write, so Arrêter's totals land after it. */
    private var lastPointWrite: Job? = null

    /** The kill-recovery read, which Démarrer waits for so it can't race a restore. */
    private var restoreJob: Job? = null

    /**
     * Watches the fix stream for pause automatique. Inert until [startRecording]
     * arms it from the preference as it stood at Démarrer, so a ride records under
     * the setting it began with.
     */
    private var autoPause = AutoPauseDetector(isEnabled = false)

    // Closed laps, mirrored in memory so the split sheet doesn't wait on Room. A
    // new immutable snapshot is published on each Tour so StateFlow re-emits.
    private val lapBoundaries = mutableListOf<LapBoundary>()
    private var lapBoundarySnapshot: List<LapBoundary> = emptyList()

    // The recorded trace, oldest-first, for the live map line. A new immutable
    // snapshot is published whenever a point is appended so StateFlow re-emits.
    private val routePoints = mutableListOf<RoutePoint>()
    private var routeSnapshot: List<RoutePoint> = emptyList()

    // Elapsed clock: wall-clock recording time minus paused stretches, on a
    // monotonic base so a system clock change can't skew it.
    private var accumulatedElapsedMs = 0L
    private var stretchStartMs: Long? = null
    private var tickerJob: Job? = null

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            onFix(result.lastLocation ?: return)
        }
    }

    inner class LocalBinder : Binder() {
        val uiState: StateFlow<RecordingUiState> get() = _uiState.asStateFlow()
        fun start(sport: Sport) = this@RecordingService.startRecording(sport)
        fun pause() = this@RecordingService.pause()
        fun resume() = this@RecordingService.resume()
        fun markLap() = this@RecordingService.markLap()
        /** Completes once the session's totals are stored, so the handoff can be built from them. */
        fun stop(): Job = this@RecordingService.stopRecording()

        /** The in-progress session id (main thread), so Stop can locate its points to encode. */
        fun sessionId(): String? = this@RecordingService.session?.id
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        restoreJob = ioScope.launch { restoreInterrupted() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Defensive: the Activity only starts us once fine-location is granted, but
        // a `location` foreground service throws SecurityException from
        // startForeground without it. Bail cleanly rather than crash.
        if (!hasLocationPermission()) {
            stopSelf()
            return START_NOT_STICKY
        }

        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
        )

        // Opening the screen arms GPS for readiness but does NOT record yet — the
        // session begins only on start (the Démarrer gate). onFix already
        // no-ops persistence while there's no session, so arming just feeds the
        // GPS-signal indicator. Re-issued start (rotation / redelivery) is a no-op.
        if (!armed) {
            armed = true
            startLocationUpdates()
            heartRate.activate()
            emitState()
        }

        // Not sticky: a recording is an explicit user session. We don't want the
        // system to silently resume GPS after a kill with no user present; the
        // interrupted ride waits, paused, for the rider to reopen the screen.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        fusedClient.removeLocationUpdates(locationCallback)
        heartRate.deactivate()
        stopTicker()
        ioScope.cancel()
        mainScope.cancel()
        super.onDestroy()
    }

    /**
     * Kill recovery: pick an interrupted recording back up as a manual pause, so
     * only the rider's own Reprendre carries on recording into it. The clock and
     * totals resume from the session's snapshots, which stopped moving when the
     * process died, so the dead span counts as paused.
     */
    private suspend fun restoreInterrupted() {
        val orphan = dao.activeSession() ?: return
        val points = dao.pointsFor(orphan.id)
        val laps = dao.lapsFor(orphan.id)
        val restoredAccumulator = orphan.restoredAccumulator(points)
        val elapsedSeconds = if (orphan.elapsed > 0) {
            orphan.elapsed
        } else {
            // An orphan from a build that kept no running snapshot.
            ((points.lastOrNull()?.timestamp ?: 0L) - (points.firstOrNull()?.timestamp ?: 0L)) / 1000.0
        }
        val restoredSport = RecordingHandoff.sportOf(orphan, Sport.lastUsed(this))
        val autoPauseEnabled = AutoPauseSetting.isEnabled(this)
        dao.updateState(
            orphan.id,
            RecordingState.PAUSED.ordinal,
            elapsedSeconds,
            restoredAccumulator.distance,
            restoredAccumulator.movingSeconds,
            restoredAccumulator.averageSpeed(),
        )
        Log.i(TAG, "restored session ${orphan.id} with ${points.size} points, paused")

        withContext(Dispatchers.Main) {
            session = orphan
            sport = restoredSport
            recordingState = RecordingState.PAUSED
            accumulator = restoredAccumulator
            pointCount = points.size
            lap = orphan.lapCount
            lastFixSpeed = 0.0
            lastPersistedSecond = points.lastOrNull()?.let { it.timestamp / 1000 }
            routePoints.clear()
            points.mapTo(routePoints) { RoutePoint(it.latitude, it.longitude) }
            routeSnapshot = routePoints.toList()
            lapBoundaries.clear()
            laps.mapTo(lapBoundaries) { LapBoundary(it.ordinal, it.cumulativeDistance, it.cumulativeElapsed) }
            lapBoundarySnapshot = lapBoundaries.toList()
            accumulatedElapsedMs = (elapsedSeconds * 1000).toLong()
            stretchStartMs = null
            // A fresh detector is inactive until Reprendre, like after a manual pause.
            autoPause = AutoPauseDetector(autoPauseEnabled)
            if (armed) updateNotification()
            emitState()
        }
    }

    /**
     * Begin a fresh recording on Démarrer: insert the new row, reset the live
     * stats, and start the elapsed ticker. GPS is already streaming from arming,
     * and the row exists before the next fix so points always have a session to
     * attach to. A no-op once a session is open, restored ones included (only one
     * may be active), and against a double tap.
     */
    private fun startRecording(sport: Sport) {
        if (session != null) return
        val autoPauseEnabled = AutoPauseSetting.isEnabled(this)
        ioScope.launch {
            restoreJob?.join()
            if (dao.activeSession() != null) return@launch

            val newSession = RecordingSessionEntity(
                id = UUID.randomUUID().toString(),
                startedAt = System.currentTimeMillis(),
                state = RecordingState.RECORDING.ordinal,
                lapCount = 1,
                sport = sport.wire,
            )
            dao.insertSession(newSession)

            withContext(Dispatchers.Main) {
                session = newSession
                this@RecordingService.sport = sport
                recordingState = RecordingState.RECORDING
                accumulator = RecordingStatsAccumulator()
                pointCount = 0
                lap = 1
                lastFixSpeed = 0.0
                lastPersistedSecond = null
                routePoints.clear()
                routeSnapshot = emptyList()
                lapBoundaries.clear()
                lapBoundarySnapshot = emptyList()
                accumulatedElapsedMs = 0L
                stretchStartMs = SystemClock.elapsedRealtime()
                autoPause = AutoPauseDetector(autoPauseEnabled).also { it.reset() }
                startTicker()
                updateNotification()
                emitState()
            }
        }
    }

    private fun onFix(location: android.location.Location) {
        // Always surface the latest fix for the GPS-signal indicator.
        lastLatitude = location.latitude
        lastLongitude = location.longitude
        lastAccuracy = if (location.hasAccuracy()) location.accuracy else null

        // Every fix feeds the detector, including the ones a paused recording drops
        // — watching them is exactly how the auto-resume is spotted.
        when (autoPause.consider(location.toAutoPauseFix())) {
            AutoPauseOutcome.SHOULD_AUTO_PAUSE -> autoPauseRecording()
            AutoPauseOutcome.SHOULD_AUTO_RESUME -> autoResumeRecording()
            AutoPauseOutcome.NONE -> Unit
        }

        val current = session
        if (recordingState != RecordingState.RECORDING || current == null) {
            emitState()
            return
        }

        // Keep at most one fix per wall-clock second (the ~1 Hz contract): the
        // provider can burst sub-second, and the eventual GPX emits whole-second
        // timestamps that would collide on the server's unique recorded_at.
        val second = location.time / 1000
        if (second == lastPersistedSecond) {
            emitState()
            return
        }
        lastPersistedSecond = second

        val segmentSpeed = accumulator.add(location)
        lastFixSpeed = if (location.hasSpeed()) location.speed.toDouble() else segmentSpeed
        pointCount++
        routePoints.add(RoutePoint(location.latitude, location.longitude))
        routeSnapshot = routePoints.toList()

        val point = RecordingPointEntity(
            sessionId = current.id,
            timestamp = location.time,
            latitude = location.latitude,
            longitude = location.longitude,
            elevation = if (location.hasAltitude()) location.altitude else null,
            speed = segmentSpeed,
            horizontalAccuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0,
            lap = lap,
            heartRate = heartRate.latestReading?.bpmAt(location.time),
        )
        lastPointWrite = ioScope.launch { dao.insertPoint(point) }
        persistProgress(current)

        emitState()
    }

    /**
     * The rider tapped **Pause**. Also the way out of an automatic pause into a
     * manual one: an explicit pause outranks the detector, so no amount of movement
     * will resume it.
     */
    private fun pause() {
        if (recordingState != RecordingState.RECORDING && recordingState != RecordingState.AUTO_PAUSED) return
        autoPause.userDidPause()
        enterPause(RecordingState.PAUSED)
    }

    /**
     * The rider tapped **Reprendre**, from either kind of pause. That also disarms
     * the detector until they have genuinely moved.
     */
    private fun resume() {
        if (!recordingState.isPaused) return
        autoPause.userDidResume()
        leavePause()
    }

    /** Ten still seconds: enter pause automatique. */
    private fun autoPauseRecording() {
        if (recordingState != RecordingState.RECORDING) return
        enterPause(RecordingState.AUTO_PAUSED)
    }

    /** Genuine movement away from where we paused: back to recording. */
    private fun autoResumeRecording() {
        if (recordingState != RecordingState.AUTO_PAUSED) return
        leavePause()
    }

    private fun enterPause(target: RecordingState) {
        val current = session ?: return
        accumulatedElapsedMs = elapsedMs()
        stretchStartMs = null
        lastFixSpeed = 0.0
        // Break the segment so the paused gap adds neither distance nor moving time.
        accumulator.breakSegment()
        recordingState = target
        stopTicker()
        persistState(current, target)
        updateNotification()
        emitState()
    }

    private fun leavePause() {
        val current = session ?: return
        stretchStartMs = SystemClock.elapsedRealtime()
        recordingState = RecordingState.RECORDING
        startTicker()
        persistState(current, RecordingState.RECORDING)
        updateNotification()
        emitState()
    }

    private fun persistProgress(current: RecordingSessionEntity) {
        val elapsed = elapsedMs() / 1000.0
        val distance = accumulator.distance
        val movingTime = accumulator.movingSeconds
        val averageSpeed = accumulator.averageSpeed()
        ioScope.launch { dao.updateProgress(current.id, elapsed, distance, movingTime, averageSpeed) }
    }

    private fun persistState(current: RecordingSessionEntity, target: RecordingState) {
        val elapsed = accumulatedElapsedMs / 1000.0
        val distance = accumulator.distance
        val movingTime = accumulator.movingSeconds
        val averageSpeed = accumulator.averageSpeed()
        ioScope.launch { dao.updateState(current.id, target.ordinal, elapsed, distance, movingTime, averageSpeed) }
    }

    /**
     * Close the running Tour and open the next one.
     *
     * Snapshots the cumulative totals *before* bumping the counter, so the row
     * closes the lap that was running; [LapSplits] differences consecutive rows into
     * splits. Only while actually recording — Tour is hidden in both paused states,
     * so a zero-distance lap can't be minted at a red light.
     */
    private fun markLap() {
        if (recordingState != RecordingState.RECORDING) return
        val current = session ?: return
        val boundary = LapBoundary(
            ordinal = lap,
            cumulativeDistance = accumulator.distance,
            cumulativeElapsed = elapsedMs() / 1000.0,
        )
        lapBoundaries.add(boundary)
        lapBoundarySnapshot = lapBoundaries.toList()
        lap += 1
        val ordinal = lap
        val row = RecordingLapEntity(
            sessionId = current.id,
            ordinal = boundary.ordinal,
            endedAt = System.currentTimeMillis(),
            cumulativeDistance = boundary.cumulativeDistance,
            cumulativeElapsed = boundary.cumulativeElapsed,
        )
        ioScope.launch {
            dao.insertLap(row)
            dao.updateLapCount(current.id, ordinal)
        }
        emitState()
    }

    /**
     * Store the session's totals and finalize it to STOPPED, then tear the service
     * down. With no session (merely armed) it only tears down.
     */
    private fun stopRecording(): Job {
        val id = session?.id
        // Snapshot before the clock below stops.
        val elapsed = elapsedMs() / 1000.0
        val distance = accumulator.distance
        val movingTime = accumulator.movingSeconds
        val averageSpeed = accumulator.averageSpeed()
        val pendingPoint = lastPointWrite
        session = null
        sport = null
        recordingState = RecordingState.STOPPED
        stopTicker()
        fusedClient.removeLocationUpdates(locationCallback)
        heartRate.deactivate()
        return ioScope.launch {
            pendingPoint?.join()
            if (id != null) {
                dao.finish(id, distance, elapsed, movingTime, averageSpeed, System.currentTimeMillis())
            }
            withContext(Dispatchers.Main) { stopSelf() }
        }
    }

    private fun startLocationUpdates() {
        // ~1 Hz, high accuracy — matches the iOS kCLDistanceFilterNone ~1 Hz feed.
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MS)
            .setMinUpdateIntervalMillis(UPDATE_INTERVAL_MS)
            .build()

        if (!hasLocationPermission()) return
        fusedClient.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
    }

    private fun startTicker() {
        stopTicker()
        tickerJob = mainScope.launch {
            while (isActive) {
                delay(1000)
                // Not only with points: through a GPS gap the clock would otherwise
                // restore to the last fix rather than to the kill.
                session?.let(::persistProgress)
                emitState()
            }
        }
    }

    private fun stopTicker() {
        tickerJob?.cancel()
        tickerJob = null
    }

    private fun elapsedMs(): Long {
        val start = stretchStartMs
        return accumulatedElapsedMs + if (start != null) SystemClock.elapsedRealtime() - start else 0L
    }

    private fun emitState() {
        _uiState.value = RecordingUiState(
            recordingState = recordingState,
            armed = session == null,
            latitude = lastLatitude,
            longitude = lastLongitude,
            accuracy = lastAccuracy,
            pointCount = pointCount,
            lap = lap,
            elapsedSeconds = elapsedMs() / 1000,
            movingSeconds = accumulator.movingSeconds,
            distanceMeters = accumulator.distance,
            currentSpeedMps = lastFixSpeed,
            averageSpeedMps = accumulator.averageSpeed(),
            routePoints = routeSnapshot,
            lapBoundaries = lapBoundarySnapshot,
            sport = sport,
        )
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** Re-post the ongoing notification so its text follows the recording state. */
    private fun updateNotification() {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        createChannel()

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, RecordingActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )

        // Honest about pause automatique: a rider glancing at the shade must not be
        // told the ride is still recording when the clock is frozen.
        val text = when {
            session == null -> R.string.recording_notification_text_armed
            recordingState == RecordingState.AUTO_PAUSED -> R.string.recording_notification_text_auto_paused
            recordingState == RecordingState.PAUSED -> R.string.recording_notification_text_paused
            else -> R.string.recording_notification_text
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_record)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(text))
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.recording_notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** The detector takes plain values, so it stays testable off-device. */
    private fun android.location.Location.toAutoPauseFix() = AutoPauseFix(
        timeMs = time,
        latitude = latitude,
        longitude = longitude,
        speedMps = if (hasSpeed()) speed.toDouble() else null,
    )

    companion object {
        private const val TAG = "RecordingService"
        private const val CHANNEL_ID = "recording"
        private const val NOTIFICATION_ID = 1
        private const val UPDATE_INTERVAL_MS = 1000L

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, RecordingService::class.java),
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RecordingService::class.java))
        }
    }
}
