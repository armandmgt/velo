package fr.armandmgt.velo.features.record

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme

/**
 * Hosts the native recording screen (#54, S6). Opening it *is* the start of a
 * recording for the skeleton: it kicks off the foreground service (so the ongoing
 * notification appears) and shows the Compose placeholder. Stop tears the service
 * back down and finishes, returning to the tabs.
 *
 * Unlike the iOS modal there's no accidental-dismiss gesture to guard against — an
 * Activity isn't swipe-dismissable — so Stop (and system back) are the only exits.
 */
class RecordingActivity : ComponentActivity() {
    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* notification just won't show if denied */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        requestNotificationPermissionIfNeeded()
        RecordingService.start(this)

        setContent {
            MaterialTheme {
                RecordingScreen(onStop = ::stopRecording)
            }
        }
    }

    private fun stopRecording() {
        RecordingService.stop(this)
        finish()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
