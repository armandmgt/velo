package fr.armandmgt.velo.features.record

import android.Manifest
import android.app.AlertDialog
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.data.RecordingDatabase
import fr.armandmgt.velo.ui.theme.VeloTheme
import kotlinx.coroutines.launch

/**
 * Hosts the native recording screen (#54 skeleton; #55 GPS feed; #57 upload).
 *
 * Opening it *arms* GPS: once location permission is granted it starts the
 * [RecordingService] (an ongoing-notification `location` foreground service) and
 * binds to mirror the live GPS readout, but nothing is recorded until Démarrer.
 * Arrêter finalizes the session, serializes its points to GPX and uploads them,
 * handing the new activity URL back to [fr.armandmgt.velo.main.MainActivity] on
 * success (the recording is kept for a retry on failure). The service keeps
 * streaming while this Activity is backgrounded; binding is only for the UI, so
 * system back leaves an in-progress recording running (the notification brings
 * the user back) and only tears the service down when merely armed.
 */
class RecordingActivity : ComponentActivity() {
    private var screenState by mutableStateOf<RecordingScreenState>(RecordingScreenState.RequestingPermission)

    /** The sport this recording uploads as; defaults to the last-used sport (#57). */
    private var selectedSport by mutableStateOf(Sport.BIKE)

    /** Optional name + visibility chosen on the review screen before upload (#67). */
    private var reviewName by mutableStateOf("")
    private var selectedVisibility by mutableStateOf(Visibility.DEFAULT)

    /** The finalized session under review, carried to its Enregistrer/Supprimer action (#67). */
    private var pendingSessionId: String? = null

    private val dao by lazy { RecordingDatabase.get(this).recordingDao() }

    private var isBound = false
    private var binder: RecordingService.LocalBinder? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val localBinder = service as RecordingService.LocalBinder
            binder = localBinder
            lifecycleScope.launch {
                localBinder.uiState.collect { screenState = RecordingScreenState.Streaming(it) }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            binder = null
        }
    }

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* notification just won't show if denied */ }

    private val requestLocationPermission =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            if (granted[Manifest.permission.ACCESS_FINE_LOCATION] == true) {
                startAndBindService()
            } else {
                screenState = RecordingScreenState.PermissionDenied
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        selectedSport = Sport.lastUsed(this)

        requestNotificationPermissionIfNeeded()
        ensureLocationPermission()

        // Back press: while recording, leave the screen but keep the service running
        // in the background (the notification brings the user back) — mirrors iOS
        // "Fermer". While only armed (nothing recorded), tear the service down.
        onBackPressedDispatcher.addCallback(this) { handleBack() }

        setContent {
            VeloTheme {
                RecordingScreen(
                    state = screenState,
                    selectedSport = selectedSport,
                    onSelectSport = ::selectSport,
                    onStartStop = { checked -> if (checked) binder?.start() else stopRecording() },
                    onPause = { binder?.pause() },
                    onResume = { binder?.resume() },
                    onLap = { binder?.markLap() },
                    onOpenSettings = ::openAppSettings,
                    reviewName = reviewName,
                    onReviewNameChange = { reviewName = it },
                    selectedVisibility = selectedVisibility,
                    onSelectVisibility = { selectedVisibility = it },
                    onSave = { pendingSessionId?.let(::uploadSession) },
                    onDiscard = { pendingSessionId?.let(::confirmDiscard) },
                )
            }
        }
    }

    private fun selectSport(sport: Sport) {
        selectedSport = sport
        Sport.setLastUsed(this, sport)
    }

    override fun onDestroy() {
        unbindIfNeeded()
        super.onDestroy()
    }

    private fun ensureLocationPermission() {
        if (hasFineLocation()) {
            startAndBindService()
        } else {
            requestLocationPermission.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    private fun startAndBindService() {
        screenState = RecordingScreenState.Streaming(RecordingUiState())
        RecordingService.start(this)
        bindService(Intent(this, RecordingService::class.java), connection, Context.BIND_AUTO_CREATE)
        isBound = true
    }

    /**
     * Arrêter: finalize the session (the service flips it to STOPPED and tears
     * down), then show the native review/confirm screen (#67) instead of uploading
     * immediately. The captured final stats feed the review summary; the upload only
     * runs on Enregistrer.
     */
    private fun stopRecording() {
        val id = binder?.sessionId()
        // Capture the live stats before the service is torn down — the review screen
        // shows this snapshot, not the (now stopped) service.
        val finalStats = (screenState as? RecordingScreenState.Streaming)?.state
        binder?.stop() ?: RecordingService.stop(this)
        unbindIfNeeded()
        if (id == null) {
            finish()
            return
        }
        // A stop with no fixes recorded has nothing to review — drop it and leave.
        if (finalStats != null && finalStats.pointCount == 0) {
            lifecycleScope.launch {
                dao.deleteSession(id)
                finish()
            }
            return
        }
        pendingSessionId = id
        screenState = RecordingScreenState.Reviewing(finalStats ?: RecordingUiState())
    }

    /**
     * Enregistrer: serialize the reviewed session to GPX and upload it with the
     * chosen sport/name/visibility. On success the local session is cleared and we
     * hand the new activity URL back to [MainActivity] to navigate the webview; on
     * failure the recording is kept for a retry (#57).
     */
    private fun uploadSession(id: String) {
        screenState = RecordingScreenState.Uploading
        val sport = selectedSport
        val name = reviewName
        val visibility = selectedVisibility
        lifecycleScope.launch {
            val points = dao.pointsFor(id)
            if (points.isEmpty()) {
                // A stop with no fixes has nothing to upload — drop it and leave.
                dao.deleteSession(id)
                finish()
                return@launch
            }

            val gpx = RecordingGpxEncoder.gpx(points.first().timestamp, points, sport)
            when (val result = ActivityUploader.upload(gpx, sport, name, visibility)) {
                is ActivityUploader.UploadResult.Success -> {
                    dao.deleteSession(id)
                    setResult(RESULT_OK, Intent().putExtra(EXTRA_ACTIVITY_URL, result.url))
                    finish()
                }
                is ActivityUploader.UploadResult.Validation ->
                    showUploadFailure(id, result.messages.joinToString("\n").ifBlank {
                        getString(R.string.recording_upload_failed_network)
                    })
                is ActivityUploader.UploadResult.Network ->
                    showUploadFailure(id, getString(R.string.recording_upload_failed_network))
            }
        }
    }

    private fun showUploadFailure(id: String, message: String) {
        AlertDialog.Builder(this)
            .setTitle(R.string.recording_upload_failed_title)
            .setMessage(message)
            .setCancelable(false)
            .setPositiveButton(R.string.recording_retry) { _, _ -> uploadSession(id) }
            .setNegativeButton(R.string.recording_later) { _, _ -> finish() }
            .show()
    }

    /**
     * Supprimer: confirm, then discard the local session — no activity is created
     * server-side (#67).
     */
    private fun confirmDiscard(id: String) {
        AlertDialog.Builder(this)
            .setTitle(R.string.recording_discard_confirm_title)
            .setMessage(R.string.recording_discard_confirm_message)
            .setPositiveButton(R.string.recording_discard) { _, _ ->
                lifecycleScope.launch {
                    dao.deleteSession(id)
                    finish()
                }
            }
            .setNegativeButton(R.string.recording_discard_cancel, null)
            .show()
    }

    private fun handleBack() {
        if (binder?.sessionId() != null) {
            // Recording in progress: keep it running in the background, just leave.
            unbindIfNeeded()
            finish()
        } else {
            // Armed only — nothing recorded yet; tear the readiness service down.
            binder?.stop() ?: RecordingService.stop(this)
            unbindIfNeeded()
            finish()
        }
    }

    private fun unbindIfNeeded() {
        if (isBound) {
            unbindService(connection)
            isBound = false
            binder = null
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null),
            ),
        )
    }

    private fun hasFineLocation(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    companion object {
        /** Result extra: the created activity's URL for [fr.armandmgt.velo.main.MainActivity] to open (#57). */
        const val EXTRA_ACTIVITY_URL = "fr.armandmgt.velo.ACTIVITY_URL"
    }
}
