package fr.armandmgt.velo.features.record

import android.Manifest
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import fr.armandmgt.velo.features.record.data.RecordingDatabase
import fr.armandmgt.velo.ui.theme.VeloTheme
import kotlinx.coroutines.launch

/**
 * Hosts the native recording screen.
 *
 * Opening it *arms* GPS: once location permission is granted it starts the
 * [RecordingService] (an ongoing-notification `location` foreground service) and
 * binds to mirror the live GPS readout, but nothing is recorded until Démarrer.
 * Arrêter finalizes the session, parks its handoff and hands back to
 * [fr.armandmgt.velo.main.MainActivity] to open the web review. While armed, the
 * dock also leads to the unsent recordings, whose Envoyer takes the same way out
 * for a recording already in the store. The service keeps
 * streaming while this Activity is backgrounded; binding is only for the UI, so
 * system back leaves an in-progress recording running (the notification brings
 * the user back) and only tears the service down when merely armed.
 */
class RecordingActivity : ComponentActivity() {
    private var screenState by mutableStateOf<RecordingScreenState>(RecordingScreenState.RequestingPermission)

    /** The sport this recording uploads as; defaults to the last-used sport. */
    private var selectedSport by mutableStateOf(Sport.BIKE)

    /** Pause automatique, editable only while armed — the service reads it at Démarrer. */
    private var autoPauseEnabled by mutableStateOf(true)

    /** The unsent-recordings list is showing in place of the recording screen. */
    private var showingUnsent by mutableStateOf(false)

    private val dao by lazy { RecordingDatabase.get(this).recordingDao() }

    private var isBound = false
    private var binder: RecordingService.LocalBinder? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val localBinder = service as RecordingService.LocalBinder
            binder = localBinder
            lifecycleScope.launch {
                localBinder.uiState.collect { state ->
                    screenState = RecordingScreenState.Streaming(state)
                    // A restored recording brings its own sport back.
                    state.sport?.let { selectedSport = it }
                }
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
        autoPauseEnabled = AutoPauseSetting.isEnabled(this)

        requestNotificationPermissionIfNeeded()
        ensureLocationPermission()

        // Back press: while recording, leave the screen but keep the service running
        // in the background (the notification brings the user back) — mirrors iOS
        // "Fermer". While only armed (nothing recorded), tear the service down.
        onBackPressedDispatcher.addCallback(this) { handleBack() }

        val unsentRecordings = dao.unsentRecordings(Sport.lastUsed(this))

        setContent {
            VeloTheme {
                val unsent by unsentRecordings.collectAsState(initial = emptyList())
                // Nothing left to send: the armed card is the only useful place to be.
                LaunchedEffect(unsent.isEmpty()) { if (unsent.isEmpty()) showingUnsent = false }
                if (showingUnsent && unsent.isNotEmpty()) {
                    UnsentRecordingsScreen(
                        recordings = unsent,
                        onSend = ::send,
                        onDelete = { id -> lifecycleScope.launch { dao.deleteSession(id) } },
                        onBack = { showingUnsent = false },
                    )
                } else {
                    RecordingScreen(
                        state = screenState,
                        selectedSport = selectedSport,
                        onSelectSport = ::selectSport,
                        autoPauseEnabled = autoPauseEnabled,
                        onToggleAutoPause = ::toggleAutoPause,
                        unsentCount = unsent.size,
                        onOpenUnsent = { showingUnsent = true },
                        onStartStop = { checked -> if (checked) binder?.start(selectedSport) else stopRecording() },
                        onPause = { binder?.pause() },
                        onResume = { binder?.resume() },
                        onLap = { binder?.markLap() },
                        onOpenSettings = ::openAppSettings,
                    )
                }
            }
        }
    }

    private fun selectSport(sport: Sport) {
        selectedSport = sport
        Sport.setLastUsed(this, sport)
    }

    private fun toggleAutoPause(enabled: Boolean) {
        autoPauseEnabled = enabled
        AutoPauseSetting.setEnabled(this, enabled)
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
     * Arrêter: finalize the session, park the handoff, and ask
     * [fr.armandmgt.velo.main.MainActivity] to open the review. The upload runs
     * from that web page, not here.
     */
    private fun stopRecording() {
        val id = binder?.sessionId()
        val finalStats = (screenState as? RecordingScreenState.Streaming)?.state
        val stopped = binder?.stop()
        if (stopped == null) RecordingService.stop(this)
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
        lifecycleScope.launch {
            stopped?.join()
            // Read back from Room rather than from the (now stopped) service, so the
            // review shows what survived to disk — and so a resent review is the same.
            val handoff = RecordingHandoff.load(dao, id, selectedSport)
            if (handoff == null) {
                dao.deleteSession(id)
                finish()
                return@launch
            }
            openReview(handoff)
        }
    }

    /** Envoyer: the same way out as Arrêter, for a recording already in the store. */
    private fun send(sessionId: String) {
        lifecycleScope.launch {
            val handoff = RecordingHandoff.load(dao, sessionId, Sport.lastUsed(this@RecordingActivity)) ?: return@launch
            // Only armed here (the list is out of reach mid-ride): release the GPS.
            binder?.stop() ?: RecordingService.stop(this@RecordingActivity)
            unbindIfNeeded()
            openReview(handoff)
        }
    }

    private fun openReview(handoff: RecordingHandoff.Payload) {
        RecordingHandoff.pending = handoff
        setResult(RESULT_OK, Intent().putExtra(EXTRA_OPEN_REVIEW, true))
        finish()
    }

    private fun handleBack() {
        if (showingUnsent) {
            showingUnsent = false
            return
        }
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
        /** A recording is parked in [RecordingHandoff]; open the review. */
        const val EXTRA_OPEN_REVIEW = "fr.armandmgt.velo.OPEN_REVIEW"
    }
}
