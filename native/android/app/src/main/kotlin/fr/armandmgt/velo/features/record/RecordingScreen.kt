package fr.armandmgt.velo.features.record

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import fr.armandmgt.velo.R
import fr.armandmgt.velo.ui.theme.VeloTheme

/** What the recording screen shows (#55) — driven by the permission flow + GPS feed. */
sealed interface RecordingScreenState {
    /** Waiting on the location-permission dialog result. */
    data object RequestingPermission : RecordingScreenState

    /** Location was denied — show why, with a shortcut to app settings. */
    data object PermissionDenied : RecordingScreenState

    /** Recording: mirror the live GPS readout from the service. */
    data class Streaming(val location: RecordingUiState) : RecordingScreenState
}

/**
 * The native recording screen (#54 skeleton; #55 adds a debug GPS readout).
 *
 * Still deliberately minimal — a title, a live lat/lon/accuracy/point-count
 * readout (or a "waiting for GPS" / "permission denied" state), and a Stop
 * button. The polished live-stats / map UI is later-stage work.
 */
@Composable
fun RecordingScreen(
    state: RecordingScreenState,
    onStop: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Scaffold { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = "Enregistrement",
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
            )

            when (state) {
                is RecordingScreenState.PermissionDenied -> DeniedBody(onOpenSettings)
                is RecordingScreenState.Streaming -> GpsReadout(state.location)
                RecordingScreenState.RequestingPermission -> WaitingForGps()
            }

            Button(
                onClick = onStop,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError,
                ),
                modifier = Modifier
                    .padding(top = 48.dp)
                    .size(width = 200.dp, height = 56.dp),
            ) {
                Text(text = "Arrêter")
            }
        }
    }
}

@Composable
private fun GpsReadout(location: RecordingUiState) {
    val latitude = location.latitude
    val longitude = location.longitude
    if (latitude == null || longitude == null) {
        WaitingForGps()
        return
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ReadoutRow(stringResource(R.string.recording_latitude), "%.6f".format(latitude))
        ReadoutRow(stringResource(R.string.recording_longitude), "%.6f".format(longitude))
        ReadoutRow(
            stringResource(R.string.recording_accuracy),
            location.accuracy?.let { "%.1f m".format(it) } ?: "—",
        )
        ReadoutRow(stringResource(R.string.recording_point_count), location.pointCount.toString())
    }
}

@Composable
private fun ReadoutRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

@Composable
private fun WaitingForGps() {
    Text(
        text = stringResource(R.string.recording_waiting_gps),
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        modifier = Modifier.padding(top = 8.dp),
    )
}

@Composable
private fun DeniedBody(onOpenSettings: () -> Unit) {
    Text(
        text = stringResource(R.string.recording_permission_denied),
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        modifier = Modifier.padding(top = 8.dp),
    )
    OutlinedButton(
        onClick = onOpenSettings,
        modifier = Modifier.padding(top = 16.dp),
    ) {
        Text(text = stringResource(R.string.recording_open_settings))
    }
}

@Preview
@Composable
private fun RecordingScreenPreview() {
    VeloTheme {
        RecordingScreen(
            state = RecordingScreenState.Streaming(
                RecordingUiState(latitude = 48.8566, longitude = 2.3522, accuracy = 4.5f, pointCount = 42),
            ),
            onStop = {},
            onOpenSettings = {},
        )
    }
}
