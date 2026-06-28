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
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import fr.armandmgt.velo.ui.theme.VeloTheme
import kotlinx.coroutines.launch

/**
 * Hosts the native recording screen (#54 skeleton; #55 adds the GPS feed).
 *
 * Opening it *is* the start of a recording: once location permission is granted
 * it starts the [RecordingService] (an ongoing-notification `location` foreground
 * service) and binds to it to mirror the live GPS readout. The service keeps
 * streaming while this Activity is backgrounded; binding is only for the UI, so
 * Stop (or system back) tears the service back down and finishes.
 */
class RecordingActivity : ComponentActivity() {
    private var screenState by mutableStateOf<RecordingScreenState>(RecordingScreenState.RequestingPermission)

    private var isBound = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as RecordingService.LocalBinder
            lifecycleScope.launch {
                binder.uiState.collect { screenState = RecordingScreenState.Streaming(it) }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {}
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

        requestNotificationPermissionIfNeeded()
        ensureLocationPermission()

        setContent {
            VeloTheme {
                RecordingScreen(
                    state = screenState,
                    onStop = ::stopRecording,
                    onOpenSettings = ::openAppSettings,
                )
            }
        }
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

    private fun stopRecording() {
        unbindIfNeeded()
        RecordingService.stop(this)
        finish()
    }

    private fun unbindIfNeeded() {
        if (isBound) {
            unbindService(connection)
            isBound = false
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
}
