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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The latest GPS readout for the recording screen's debug display (#55). */
data class RecordingUiState(
    val latitude: Double? = null,
    val longitude: Double? = null,
    val accuracy: Float? = null,
    val pointCount: Int = 0,
)

/**
 * Foreground service backing a recording session (#54 skeleton; #55 adds GPS).
 *
 * It runs as a `location` foreground service (the S6 `dataSync` placeholder is
 * gone now that location permission is requested) and streams fixes from the
 * Fused Location Provider for as long as it lives — so updates keep flowing while
 * the app is backgrounded / the screen is off, with only While-Using
 * (`ACCESS_FINE_LOCATION`) permission. The recording screen binds to read the
 * live [RecordingUiState]; the service stays alive because it's *started*
 * (foreground), so unbinding when the screen leaves doesn't tear it down.
 */
class RecordingService : Service() {
    private val _uiState = MutableStateFlow(RecordingUiState())

    private val binder = LocalBinder()

    private val fusedClient: FusedLocationProviderClient by lazy {
        LocationServices.getFusedLocationProviderClient(this)
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val location = result.lastLocation ?: return
            val current = _uiState.value
            _uiState.value = current.copy(
                latitude = location.latitude,
                longitude = location.longitude,
                accuracy = if (location.hasAccuracy()) location.accuracy else null,
                pointCount = current.pointCount + 1,
            )
        }
    }

    inner class LocalBinder : Binder() {
        val uiState: StateFlow<RecordingUiState> get() = _uiState.asStateFlow()
    }

    override fun onBind(intent: Intent?): IBinder = binder

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
        startLocationUpdates()

        // Not sticky: a recording is an explicit user session. We don't want the
        // system to silently resume GPS after a kill with no user present (kill
        // recovery is later work, mirroring iOS's no-auto-resume).
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        fusedClient.removeLocationUpdates(locationCallback)
        super.onDestroy()
    }

    private fun startLocationUpdates() {
        // ~1 Hz, high accuracy — matches the iOS kCLDistanceFilterNone ~1 Hz feed.
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MS)
            .setMinUpdateIntervalMillis(UPDATE_INTERVAL_MS)
            .build()

        if (!hasLocationPermission()) return
        fusedClient.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun buildNotification(): Notification {
        createChannel()

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, RecordingActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_record)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.recording_notification_text))
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

    companion object {
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
