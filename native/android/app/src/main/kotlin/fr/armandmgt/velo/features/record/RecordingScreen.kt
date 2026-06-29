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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
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

    /** Recording (or armed, per [RecordingUiState.armed]): mirror the live stats from the service. */
    data class Streaming(val state: RecordingUiState) : RecordingScreenState

    /** Serializing + uploading the finished recording after Arrêter (#57). */
    data object Uploading : RecordingScreenState
}

/**
 * The native recording screen (#56): live stats dominate — elapsed, distance,
 * current/average speed and lap — with GPS signal as a slim top indicator
 * (diagnostics stay small). Controls run pause/resume, lap, and stop.
 */
@Composable
fun RecordingScreen(
    state: RecordingScreenState,
    selectedSport: Sport,
    onSelectSport: (Sport) -> Unit,
    onStartStop: (Boolean) -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
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
            // The body fills the space above the bottom action area.
            val bodyModifier = Modifier
                .fillMaxWidth()
                .weight(1f)

            when (state) {
                RecordingScreenState.RequestingPermission ->
                    CenteredMessage(bodyModifier, stringResource(R.string.recording_waiting_gps))

                RecordingScreenState.PermissionDenied ->
                    DeniedBody(bodyModifier, onOpenSettings)

                RecordingScreenState.Uploading ->
                    UploadingBody(bodyModifier)

                is RecordingScreenState.Streaming ->
                    if (state.state.armed) {
                        ArmedBody(bodyModifier, state.state)
                    } else {
                        StreamingBody(bodyModifier, state.state)
                    }
            }

            // Bottom action: Démarrer while armed, Arrêter while recording, nothing
            // during permission/upload states.
            if (state is RecordingScreenState.Streaming) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    if (state.state.armed) {
                        SportPicker(selectedSport, onSelectSport)
                    } else {
                        FilledIconToggleButton(
                            checked = state.state.recordingState != RecordingState.PAUSED,
                            onCheckedChange = { checked -> if (checked) onResume() else onPause() },
                        ) {
                            Icon(
                                painter = painterResource(
                                    if (state.state.recordingState == RecordingState.PAUSED) R.drawable.ic_play_arrow_filled_24px else R.drawable.ic_pause_outlined_24px,
                                ),
                                contentDescription = stringResource(
                                    if (state.state.recordingState == RecordingState.PAUSED) R.string.recording_resume else R.string.recording_pause,
                                )
                            )
                        }
                    }

                    StartStopButton(state.state.armed, onStartStop)

                    if (state.state.armed) {
                        Box(modifier = Modifier.width(40.dp)) { }
                    } else {
                        OutlinedIconButton(
                            onClick = onLap,
                            enabled = state.state.recordingState != RecordingState.PAUSED,
                        ) {
                            Icon(
                                painter = painterResource(id = R.drawable.ic_laps_24px),
                                contentDescription = stringResource(R.string.recording_mark_lap)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StreamingBody(
    modifier: Modifier,
    ui: RecordingUiState,
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
                Stat(
                    formatDistanceKm(ui.distanceMeters),
                    stringResource(R.string.recording_distance)
                )
                Stat(formatSpeedKmh(ui.currentSpeedMps), stringResource(R.string.recording_speed))
                Stat(
                    formatSpeedKmh(ui.averageSpeedMps),
                    stringResource(R.string.recording_average_speed)
                )
            }

            Spacer(Modifier.size(20.dp))

            Text(
                text = stringResource(R.string.recording_lap, ui.lap),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            )
        }
    }
}

/**
 * Armed (pre-Démarrer) body: GPS readiness + a zeroed stats preview, with the
 * sport picker pinned just above the Démarrer button (#57) — mirrors iOS's idle
 * state where the sport is chosen up front, defaulting to the last-used sport.
 */
@Composable
private fun ArmedBody(
    modifier: Modifier,
    ui: RecordingUiState,
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
            Hero(formatElapsed(0L), stringResource(R.string.recording_elapsed))

            Spacer(Modifier.size(32.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                Stat(formatDistanceKm(0.0), stringResource(R.string.recording_distance))
                Stat(formatSpeedKmh(0.0), stringResource(R.string.recording_speed))
                Stat(formatSpeedKmh(0.0), stringResource(R.string.recording_average_speed))
            }
        }
    }
}

/** A pull-down sport picker over [Sport.entries]; the chosen sport drives the upload's `activity[sport]`. */
@Composable
private fun SportPicker(selected: Sport, onSelect: (Sport) -> Unit) {
    var expanded by remember { mutableStateOf(false) }

    OutlinedIconButton(
        onClick = { expanded = true },
    ) {
        Icon(
            painter = painterResource(R.drawable.ic_bike),
            contentDescription = stringResource(selected.nameRes)
        )
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        Sport.entries.forEach { sport ->
            DropdownMenuItem(
                text = { Text(stringResource(sport.nameRes)) },
                onClick = {
                    onSelect(sport)
                    expanded = false
                },
            )
        }
    }
}

/**
 * Start/stop gate: a Material 3 Expressive [ToggleButton] — "checked" while
 * recording. Shows Démarrer while armed, Arrêter while recording. The current
 * [armed] flag is handed back so the caller decides start vs stop.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun StartStopButton(armed: Boolean, onStartStop: (Boolean) -> Unit) {
    ToggleButton(
        checked = armed,
        onCheckedChange = { onStartStop(armed) },
        contentPadding = ButtonDefaults.contentPaddingFor(ButtonDefaults.LargeContainerHeight),
    ) {
        Text(stringResource(if (armed) R.string.recording_start else R.string.recording_stop))
    }
}

/** Shown while the finished recording is serialized + uploaded after Arrêter (#57). */
@Composable
private fun UploadingBody(modifier: Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator()
        Spacer(Modifier.size(16.dp))
        Text(
            text = stringResource(R.string.recording_uploading),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
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
    val value =
        accuracy?.let { "%.0f m".format(it) } ?: stringResource(R.string.recording_gps_searching)

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

private fun formatSpeedKmh(metersPerSecond: Double): String =
    "%.1f km/h".format(metersPerSecond * 3.6)

@Preview(name = "Armed")
@Composable
private fun RecordingScreenArmedPreview() {
    VeloTheme {
        RecordingScreen(
            state = RecordingScreenState.Streaming(
                RecordingUiState(
                    recordingState = RecordingState.RECORDING,
                    armed = true,
                    accuracy = 6.5f,
                    pointCount = 0,
                    lap = 0,
                    elapsedSeconds = 0,
                    distanceMeters = 0.0,
                    currentSpeedMps = 0.0,
                    averageSpeedMps = 0.0,
                ),
            ),
            selectedSport = Sport.BIKE,
            onSelectSport = {},
            onStartStop = {},
            onPause = {},
            onResume = {},
            onLap = {},
            onOpenSettings = {},
        )
    }
}

@Preview(name = "Streaming")
@Composable
private fun RecordingScreenStreamingPreview() {
    VeloTheme {
        RecordingScreen(
            state = RecordingScreenState.Streaming(
                RecordingUiState(
                    recordingState = RecordingState.RECORDING,
                    armed = false,
                    accuracy = 6.5f,
                    pointCount = 184,
                    lap = 2,
                    elapsedSeconds = 3725,
                    distanceMeters = 12_840.0,
                    currentSpeedMps = 7.4,
                    averageSpeedMps = 6.1,
                ),
            ),
            selectedSport = Sport.BIKE,
            onSelectSport = {},
            onStartStop = {},
            onPause = {},
            onResume = {},
            onLap = {},
            onOpenSettings = {},
        )
    }
}

