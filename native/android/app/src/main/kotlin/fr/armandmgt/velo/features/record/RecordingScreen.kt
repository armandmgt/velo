package fr.armandmgt.velo.features.record

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
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

    /** Reviewing the finished recording before upload (#67): the captured final stats. */
    data class Reviewing(val stats: RecordingUiState) : RecordingScreenState

    /** Serializing + uploading the finished recording after Enregistrer (#57). */
    data object Uploading : RecordingScreenState
}

/** Amber used for the paused state (Material has no built-in "warning" role). */
private val PausedColor = Color(0xFFF59E0B)

/**
 * The native recording screen (#56), redesigned as a **dashboard**: a compact
 * header (sport chip ⟷ GPS chip), a pulsing state pill, a large **distance** hero,
 * and a filled 2×2 metric card (temps · vitesse/allure · moyenne · tours) that
 * gives the body weight. GPS signal stays a minor chip; recording state reads from
 * the pill. Controls run start, pause/resume, lap, and stop.
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
    reviewName: String,
    onReviewNameChange: (String) -> Unit,
    selectedVisibility: Visibility,
    onSelectVisibility: (Visibility) -> Unit,
    onSave: () -> Unit,
    onDiscard: () -> Unit,
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
                    DashboardBody(bodyModifier, state.state, selectedSport, onSelectSport)

                is RecordingScreenState.Reviewing ->
                    ReviewBody(
                        bodyModifier,
                        state.stats,
                        selectedSport,
                        onSelectSport,
                        reviewName,
                        onReviewNameChange,
                        selectedVisibility,
                        onSelectVisibility,
                    )
            }

            // Bottom action area: Démarrer while armed; Tour/Pause + Arrêter while
            // recording; Enregistrer/Supprimer while reviewing; nothing during the
            // permission/upload states.
            when (state) {
                is RecordingScreenState.Streaming -> Controls(
                    ui = state.state,
                    onStartStop = onStartStop,
                    onPause = onPause,
                    onResume = onResume,
                    onLap = onLap,
                )

                is RecordingScreenState.Reviewing -> ReviewControls(onSave = onSave, onDiscard = onDiscard)

                else -> Unit
            }
        }
    }
}

@Composable
private fun DashboardBody(
    modifier: Modifier,
    ui: RecordingUiState,
    selectedSport: Sport,
    onSelectSport: (Sport) -> Unit,
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Header(selectedSport, onSelectSport, ui.accuracy, armed = ui.armed)

        Spacer(Modifier.size(12.dp))

        // Reserve the pill's row even while armed (hidden) so the hero doesn't jump
        // vertically the moment recording starts.
        if (ui.armed) {
            Spacer(Modifier.size(20.dp))
        } else {
            StatePill(ui.recordingState)
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Hero(ui.distanceMeters)

            Spacer(Modifier.size(28.dp))

            MetricCard(ui, selectedSport.usesPace)
        }
    }
}

/** Sport chip (left) ⟷ GPS chip (right). */
@Composable
private fun Header(
    selectedSport: Sport,
    onSelectSport: (Sport) -> Unit,
    accuracy: Float?,
    armed: Boolean,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SportChip(selectedSport, onSelectSport, enabled = armed)
        GpsChip(accuracy)
    }
}

/**
 * Sport chip — an outlined button showing the sport's icon + name, with a pull-down
 * picker over [Sport.entries]. The picker only opens while [enabled] (pre-Démarrer);
 * once recording the sport is locked, but the chip stays a full-colour label.
 */
@Composable
private fun SportChip(selected: Sport, onSelect: (Sport) -> Unit, enabled: Boolean) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        OutlinedButton(
            onClick = { if (enabled) expanded = true },
            contentPadding = ButtonDefaults.TextButtonContentPadding,
        ) {
            Icon(
                painter = painterResource(selected.iconRes),
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(stringResource(selected.nameRes))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Sport.entries.forEach { sport ->
                DropdownMenuItem(
                    text = { Text(stringResource(sport.nameRes)) },
                    leadingIcon = {
                        Icon(
                            painter = painterResource(sport.iconRes),
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                        )
                    },
                    onClick = {
                        onSelect(sport)
                        expanded = false
                    },
                )
            }
        }
    }
}

/** Slim GPS-signal chip: a coloured dot + the current horizontal accuracy. */
@Composable
private fun GpsChip(accuracy: Float?) {
    val color = when {
        accuracy == null -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
        accuracy <= 15f -> MaterialTheme.colorScheme.secondary
        accuracy <= 40f -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.error
    }
    val value =
        accuracy?.let { "%.0f m".format(it) } ?: stringResource(R.string.recording_gps_searching)

    Surface(color = color.copy(alpha = 0.15f), shape = RoundedCornerShape(14.dp)) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(color = color, shape = CircleShape, modifier = Modifier.size(8.dp)) {}
            Spacer(Modifier.width(6.dp))
            Text(
                text = stringResource(R.string.recording_gps_signal, value),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f),
            )
        }
    }
}

/** Recording/paused state pill with a pulsing dot (red recording, amber paused). */
@Composable
private fun StatePill(recordingState: RecordingState) {
    val recording = recordingState != RecordingState.PAUSED
    val color = if (recording) MaterialTheme.colorScheme.error else PausedColor

    val transition = rememberInfiniteTransition(label = "pill")
    val pulse by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.25f,
        animationSpec = infiniteRepeatable(tween(800), RepeatMode.Reverse),
        label = "pulse",
    )
    val dotAlpha = if (recording) pulse else 1f

    Row(verticalAlignment = Alignment.CenterVertically) {
        Surface(
            color = color,
            shape = CircleShape,
            modifier = Modifier
                .size(10.dp)
                .alpha(dotAlpha),
        ) {}
        Spacer(Modifier.width(8.dp))
        Text(
            text = stringResource(
                if (recording) R.string.recording_state_recording else R.string.recording_state_paused,
            ),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
    }
}

/** The hero: a large distance number with a small unit, over a quiet caption. */
@Composable
private fun Hero(distanceMeters: Double) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "%.2f".format(distanceMeters / 1000),
                style = MaterialTheme.typography.displayLarge.copy(fontFeatureSettings = "tnum"),
            )
            Spacer(Modifier.width(6.dp))
            Text(
                text = "km",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }
        Text(
            text = stringResource(R.string.recording_distance).uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}

/** Filled 2×2 metric card with hairline dividers: temps · vitesse/allure · moyenne · tours. */
@Composable
private fun MetricCard(ui: RecordingUiState, usesPace: Boolean) {
    val speed = if (usesPace) formatPace(ui.currentSpeedMps) else formatSpeedKmh(ui.currentSpeedMps)
    val average = if (usesPace) formatPace(ui.averageSpeedMps) else formatSpeedKmh(ui.averageSpeedMps)
    val speedLabel = stringResource(if (usesPace) R.string.recording_pace else R.string.recording_speed)

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(20.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            MetricRow(
                left = formatElapsed(ui.elapsedSeconds) to stringResource(R.string.recording_elapsed),
                right = speed to speedLabel,
            )
            HorizontalDivider()
            MetricRow(
                left = average to stringResource(R.string.recording_average_speed),
                right = ui.lap.toString() to stringResource(R.string.recording_laps),
            )
        }
    }
}

/** One grid row: two equal stat cells split by a vertical hairline. */
@Composable
private fun MetricRow(left: Pair<String, String>, right: Pair<String, String>) {
    Row(modifier = Modifier.height(IntrinsicSize.Min)) {
        Stat(left.first, left.second, Modifier.weight(1f))
        VerticalDivider(modifier = Modifier.fillMaxHeight())
        Stat(right.first, right.second, Modifier.weight(1f))
    }
}

@Composable
private fun Stat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.headlineSmall.copy(fontFeatureSettings = "tnum"),
        )
        Spacer(Modifier.size(4.dp))
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}

/**
 * Bottom controls: a full-width Démarrer while armed, else a Tour ⟷ Pause/Reprendre
 * row above a full-width Arrêter. [onStartStop] is handed the current [armed] flag so
 * the caller decides start vs stop.
 */
@Composable
private fun Controls(
    ui: RecordingUiState,
    onStartStop: (Boolean) -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
) {
    Column(modifier = Modifier.padding(top = 12.dp, bottom = 16.dp)) {
        if (ui.armed) {
            Button(
                onClick = { onStartStop(true) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
            ) {
                Text(stringResource(R.string.recording_start))
            }
        } else {
            val paused = ui.recordingState == RecordingState.PAUSED
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedButton(
                    onClick = onLap,
                    enabled = !paused,
                    modifier = Modifier
                        .weight(1f)
                        .height(54.dp),
                ) {
                    // Visible text doubles as the contentDescription Maestro taps via
                    // "^Tour$" — kept distinct from the "Tours" metric caption.
                    Text(stringResource(R.string.recording_mark_lap))
                }
                OutlinedButton(
                    onClick = { if (paused) onResume() else onPause() },
                    modifier = Modifier
                        .weight(1f)
                        .height(54.dp),
                ) {
                    Text(
                        stringResource(
                            if (paused) R.string.recording_resume else R.string.recording_pause,
                        ),
                    )
                }
            }
            Spacer(Modifier.size(12.dp))
            Button(
                onClick = { onStartStop(false) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
            ) {
                Text(stringResource(R.string.recording_stop))
            }
        }
    }
}

/**
 * The review/confirm screen body (#67): a read-only distance hero + summary
 * (Temps · Moyenne), then the editable sport, name, and visibility fields.
 * Mirrors [DashboardBody]'s visual language; scrolls so the form stays reachable
 * above the keyboard on short screens.
 */
@Composable
private fun ReviewBody(
    modifier: Modifier,
    stats: RecordingUiState,
    selectedSport: Sport,
    onSelectSport: (Sport) -> Unit,
    name: String,
    onNameChange: (String) -> Unit,
    selectedVisibility: Visibility,
    onSelectVisibility: (Visibility) -> Unit,
) {
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.size(8.dp))
        Text(
            text = stringResource(R.string.recording_review_title),
            style = MaterialTheme.typography.headlineSmall,
        )
        Spacer(Modifier.size(20.dp))
        Hero(stats.distanceMeters)
        Spacer(Modifier.size(24.dp))
        SummaryCard(stats, selectedSport.usesPace)
        Spacer(Modifier.size(24.dp))

        ReviewField(stringResource(R.string.recording_sport)) {
            SportChip(selectedSport, onSelectSport, enabled = true)
        }
        Spacer(Modifier.size(16.dp))
        OutlinedTextField(
            value = name,
            onValueChange = onNameChange,
            label = { Text(stringResource(R.string.recording_name_hint)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.size(16.dp))
        ReviewField(stringResource(R.string.recording_visibility)) {
            VisibilityPicker(selectedVisibility, onSelectVisibility)
        }
    }
}

/** Filled summary card with the two read-only stats: temps · moyenne/allure. */
@Composable
private fun SummaryCard(ui: RecordingUiState, usesPace: Boolean) {
    val average = if (usesPace) formatPace(ui.averageSpeedMps) else formatSpeedKmh(ui.averageSpeedMps)
    val averageLabel = stringResource(if (usesPace) R.string.recording_pace else R.string.recording_average_speed)
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(20.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(modifier = Modifier.height(IntrinsicSize.Min)) {
            Stat(formatElapsed(ui.elapsedSeconds), stringResource(R.string.recording_elapsed), Modifier.weight(1f))
            VerticalDivider(modifier = Modifier.fillMaxHeight())
            Stat(average, averageLabel, Modifier.weight(1f))
        }
    }
}

/** A captioned form field: an upper-cased label above its control. */
@Composable
private fun ReviewField(label: String, content: @Composable () -> Unit) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
        Spacer(Modifier.size(6.dp))
        content()
    }
}

/** Visibility picker — an outlined button with a pull-down over [Visibility.entries]. */
@Composable
private fun VisibilityPicker(selected: Visibility, onSelect: (Visibility) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(
            onClick = { expanded = true },
            contentPadding = ButtonDefaults.TextButtonContentPadding,
        ) {
            Text(stringResource(selected.nameRes))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Visibility.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(stringResource(option.nameRes)) },
                    onClick = {
                        onSelect(option)
                        expanded = false
                    },
                )
            }
        }
    }
}

/** Bottom controls for the review screen: a full-width Enregistrer over Supprimer. */
@Composable
private fun ReviewControls(onSave: () -> Unit, onDiscard: () -> Unit) {
    Column(modifier = Modifier.padding(top = 12.dp, bottom = 16.dp)) {
        Button(
            onClick = onSave,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
        ) {
            Text(stringResource(R.string.recording_save))
        }
        Spacer(Modifier.size(12.dp))
        Button(
            onClick = onDiscard,
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
        ) {
            Text(stringResource(R.string.recording_discard))
        }
    }
}

/** Shown while the finished recording is serialized + uploaded after Enregistrer (#57). */
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

private fun formatSpeedKmh(metersPerSecond: Double): String =
    "%.1f km/h".format(metersPerSecond * 3.6)

/**
 * `m:ss/km`. Mirrors iOS: instantaneous pace is jumpy, so near-zero speed reads as
 * `—` rather than an absurd figure.
 */
private fun formatPace(metersPerSecond: Double): String {
    if (metersPerSecond <= 0.3) return "—"
    val secondsPerKm = 1000 / metersPerSecond
    val minutes = (secondsPerKm / 60).toInt()
    val seconds = (secondsPerKm % 60).toInt()
    return "%d:%02d/km".format(minutes, seconds)
}

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
            reviewName = "",
            onReviewNameChange = {},
            selectedVisibility = Visibility.PRIVATE,
            onSelectVisibility = {},
            onSave = {},
            onDiscard = {},
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
            reviewName = "",
            onReviewNameChange = {},
            selectedVisibility = Visibility.PRIVATE,
            onSelectVisibility = {},
            onSave = {},
            onDiscard = {},
        )
    }
}
