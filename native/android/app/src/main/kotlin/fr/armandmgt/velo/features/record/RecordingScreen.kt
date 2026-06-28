package fr.armandmgt.velo.features.record

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.data.RecordingState
import fr.armandmgt.velo.ui.theme.VeloTheme

/** What the recording screen shows (#56) — driven by the permission flow + GPS feed. */
sealed interface RecordingScreenState {
    /** Waiting on the location-permission dialog result. */
    data object RequestingPermission : RecordingScreenState

    /** Location was denied — show why, with a shortcut to app settings. */
    data object PermissionDenied : RecordingScreenState

    /** Recording: mirror the live stats from the service. */
    data class Streaming(val state: RecordingUiState) : RecordingScreenState
}

/**
 * The native recording screen (#56): live stats dominate — elapsed, distance,
 * current/average speed and lap — with GPS signal as a slim top indicator
 * (diagnostics stay small). Controls run pause/resume, lap, and stop.
 */
@Composable
fun RecordingScreen(
    state: RecordingScreenState,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
    onStop: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Scaffold { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // The body fills the space above the always-present Stop button.
            val bodyModifier = Modifier
                .fillMaxWidth()
                .weight(1f)

            when (state) {
                RecordingScreenState.RequestingPermission ->
                    CenteredMessage(bodyModifier, stringResource(R.string.recording_waiting_gps))

                RecordingScreenState.PermissionDenied ->
                    DeniedBody(bodyModifier, onOpenSettings)

                is RecordingScreenState.Streaming ->
                    StreamingBody(bodyModifier, state.state, onPause, onResume, onLap)
            }

            StopButton(onStop)
        }
    }
}

@Composable
private fun StreamingBody(
    modifier: Modifier,
    ui: RecordingUiState,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        GpsSignal(ui.accuracy)

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Hero(formatElapsed(ui.elapsedSeconds), stringResource(R.string.recording_elapsed))

            Spacer(Modifier.size(32.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                Stat(formatDistanceKm(ui.distanceMeters), stringResource(R.string.recording_distance))
                Stat(formatSpeedKmh(ui.currentSpeedMps), stringResource(R.string.recording_speed))
                Stat(formatSpeedKmh(ui.averageSpeedMps), stringResource(R.string.recording_average_speed))
            }

            Spacer(Modifier.size(20.dp))

            Text(
                text = stringResource(R.string.recording_lap, ui.lap),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            )
        }

        Controls(
            paused = ui.recordingState == RecordingState.PAUSED,
            onPause = onPause,
            onResume = onResume,
            onLap = onLap,
        )
    }
}

/** Slim GPS-signal indicator: a coloured dot + the current horizontal accuracy. */
@Composable
private fun GpsSignal(accuracy: Float?) {
    val color = when {
        accuracy == null -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
        accuracy <= 15f -> MaterialTheme.colorScheme.secondary
        accuracy <= 40f -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.error
    }
    val value = accuracy?.let { "%.0f m".format(it) } ?: stringResource(R.string.recording_gps_searching)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(color = color, shape = CircleShape, modifier = Modifier.size(8.dp)) {}
        Spacer(Modifier.size(8.dp))
        Text(
            text = stringResource(R.string.recording_gps_signal, value),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}

@Composable
private fun Hero(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.displayLarge.copy(fontFeatureSettings = "tnum"),
        )
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}

@Composable
private fun Stat(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.headlineSmall.copy(fontFeatureSettings = "tnum"),
        )
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}

@Composable
private fun Controls(
    paused: Boolean,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        OutlinedButton(
            onClick = if (paused) onResume else onPause,
            modifier = Modifier.weight(1f),
        ) {
            Text(
                text = stringResource(
                    if (paused) R.string.recording_resume else R.string.recording_pause,
                ),
            )
        }
        OutlinedButton(
            onClick = onLap,
            enabled = !paused,
            modifier = Modifier.weight(1f),
        ) {
            Text(text = stringResource(R.string.recording_mark_lap))
        }
    }
}

@Composable
private fun StopButton(onStop: () -> Unit) {
    Button(
        onClick = onStop,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.error,
            contentColor = MaterialTheme.colorScheme.onError,
        ),
        modifier = Modifier
            .padding(top = 16.dp)
            .fillMaxWidth()
            .size(height = 56.dp, width = 200.dp),
    ) {
        Text(text = stringResource(R.string.recording_stop))
    }
}

@Composable
private fun CenteredMessage(modifier: Modifier, text: String) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}

@Composable
private fun DeniedBody(modifier: Modifier, onOpenSettings: () -> Unit) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = stringResource(R.string.recording_permission_denied),
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
        OutlinedButton(
            onClick = onOpenSettings,
            modifier = Modifier.padding(top = 16.dp),
        ) {
            Text(text = stringResource(R.string.recording_open_settings))
        }
    }
}

private fun formatElapsed(totalSeconds: Long): String {
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%02d:%02d".format(minutes, seconds)
    }
}

private fun formatDistanceKm(meters: Double): String = "%.2f km".format(meters / 1000)

private fun formatSpeedKmh(metersPerSecond: Double): String = "%.1f km/h".format(metersPerSecond * 3.6)

@Preview
@Composable
private fun RecordingScreenPreview() {
    VeloTheme {
        RecordingScreen(
            state = RecordingScreenState.Streaming(
                RecordingUiState(
                    recordingState = RecordingState.RECORDING,
                    accuracy = 6.5f,
                    pointCount = 184,
                    lap = 2,
                    elapsedSeconds = 3725,
                    distanceMeters = 12_840.0,
                    currentSpeedMps = 7.4,
                    averageSpeedMps = 6.1,
                ),
            ),
            onPause = {},
            onResume = {},
            onLap = {},
            onStop = {},
            onOpenSettings = {},
        )
    }
}
