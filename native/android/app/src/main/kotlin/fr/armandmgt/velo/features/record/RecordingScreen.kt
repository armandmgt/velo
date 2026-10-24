package fr.armandmgt.velo.features.record

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.data.RecordingState
import fr.armandmgt.velo.ui.theme.VeloTheme

/** What the recording screen shows — driven by the permission flow + GPS feed. */
sealed interface RecordingScreenState {
    /** Waiting on the location-permission dialog result. */
    data object RequestingPermission : RecordingScreenState

    /** Location was denied — show why, with a shortcut to app settings. */
    data object PermissionDenied : RecordingScreenState

    /** Recording (or armed, per [RecordingUiState.armed]): mirror the live stats from the service. */
    data class Streaming(val state: RecordingUiState) : RecordingScreenState

}

/**
 * The native recording screen, redesigned map-centric + flat per
 * `Recording.dc.html`: a full-bleed live map with floating white chips / pill and a
 * collapsible stats dock over flat sharp-cornered controls.
 */
@Composable
fun RecordingScreen(
    state: RecordingScreenState,
    selectedSport: Sport,
    onSelectSport: (Sport) -> Unit,
    autoPauseEnabled: Boolean,
    onToggleAutoPause: (Boolean) -> Unit,
    unsentCount: Int,
    onOpenUnsent: () -> Unit,
    onStartStop: (Boolean) -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Scaffold { innerPadding ->
        // Streaming is the map-centric surface; the other states keep the simple
        // stacked column layout.
        if (state is RecordingScreenState.Streaming) {
            RecordingMapScreen(
                innerPadding = innerPadding,
                ui = state.state,
                selectedSport = selectedSport,
                onSelectSport = onSelectSport,
                autoPauseEnabled = autoPauseEnabled,
                onToggleAutoPause = onToggleAutoPause,
                unsentCount = unsentCount,
                onOpenUnsent = onOpenUnsent,
                onStartStop = onStartStop,
                onPause = onPause,
                onResume = onResume,
                onLap = onLap,
            )
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val bodyModifier = Modifier
                .fillMaxWidth()
                .weight(1f)

            when (state) {
                RecordingScreenState.RequestingPermission ->
                    CenteredMessage(bodyModifier, stringResource(R.string.recording_waiting_gps))

                RecordingScreenState.PermissionDenied ->
                    DeniedBody(bodyModifier, onOpenSettings)

                is RecordingScreenState.Streaming -> Unit // handled above
            }
        }
    }
}

/**
 * The map-centric recording surface: a full-bleed [RecordingMap] with the header
 * chips + state pill floating on top and a collapsible stats dock over the controls
 * at the bottom. The camera is kept above the dock by measuring the bottom overlay's
 * height and feeding it as the map's bottom padding.
 */
@Composable
private fun RecordingMapScreen(
    innerPadding: PaddingValues,
    ui: RecordingUiState,
    selectedSport: Sport,
    onSelectSport: (Sport) -> Unit,
    autoPauseEnabled: Boolean,
    onToggleAutoPause: (Boolean) -> Unit,
    unsentCount: Int,
    onOpenUnsent: () -> Unit,
    onStartStop: (Boolean) -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
) {
    val position = remember(ui.latitude, ui.longitude) {
        val lat = ui.latitude
        val lng = ui.longitude
        if (lat != null && lng != null) RoutePoint(lat, lng) else null
    }
    var bottomOverlayHeight by remember { mutableStateOf(0) }
    var showLapSplits by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        RecordingMap(
            routePoints = ui.routePoints,
            position = position,
            bottomPaddingPx = bottomOverlayHeight,
            modifier = Modifier.fillMaxSize(),
        )

        // Top overlay: sport ⟷ GPS chips, then the state pill.
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .padding(innerPadding)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Header(selectedSport, onSelectSport, ui.accuracy, armed = ui.armed)
            if (!ui.armed) {
                Spacer(Modifier.size(12.dp))
                PillCapsule { StatePill(ui.recordingState) }
            }
        }

        // Bottom overlay: collapsible stats dock over the controls.
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(innerPadding)
                .padding(horizontal = 12.dp, vertical = 12.dp)
                .onSizeChanged { bottomOverlayHeight = it.height },
        ) {
            RecordingDock(
                ui = ui,
                usesPace = selectedSport.usesPace,
                autoPauseEnabled = autoPauseEnabled,
                onToggleAutoPause = onToggleAutoPause,
                unsentCount = unsentCount,
                onOpenUnsent = onOpenUnsent,
                onOpenLapSplits = { showLapSplits = true },
            )
            Spacer(Modifier.size(10.dp))
            Controls(ui, onStartStop, onPause, onResume, onLap)
        }
    }

    if (showLapSplits) {
        LapSplitsSheet(ui, selectedSport.usesPace) { showLapSplits = false }
    }
}

/** A flat white sharp-cornered capsule backing the state pill so it reads over the map. */
@Composable
private fun PillCapsule(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .flatCard(Rec.border, 2.dp)
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) { content() }
}

/**
 * The collapsible stats dock floating at the bottom of the map. Armed → the "Prêt à
 * enregistrer" card; recording/paused → a compact one-row summary or the expanded
 * Distance | Temps + Vitesse · Moyenne · Tours layout, toggled by the grabber.
 */
@Composable
private fun RecordingDock(
    ui: RecordingUiState,
    usesPace: Boolean,
    autoPauseEnabled: Boolean,
    onToggleAutoPause: (Boolean) -> Unit,
    unsentCount: Int,
    onOpenUnsent: () -> Unit,
    onOpenLapSplits: () -> Unit,
) {
    var collapsed by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize()
            .flatCard(Rec.borderDock, 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (!ui.armed) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { collapsed = !collapsed }
                    .semantics { contentDescription = "Réduire ou agrandir les statistiques" }
                    .padding(vertical = 9.dp),
                contentAlignment = Alignment.Center,
            ) {
                GrabHandle()
            }
        }

        when {
            ui.armed -> IdleDockContent(autoPauseEnabled, onToggleAutoPause, unsentCount, onOpenUnsent)
            collapsed -> CollapsedStats(ui, usesPace)
            else -> ExpandedStats(ui, usesPace, onOpenLapSplits)
        }
    }
}

@Composable
private fun GrabHandle() {
    Box(
        Modifier
            .size(width = 36.dp, height = 5.dp)
            .clip(RoundedCornerShape(3.dp))
            .background(Rec.grabber),
    )
}

/**
 * Dock content before Démarrer: a quiet "ready to record" card, carrying the one
 * pause-automatique toggle. It lives here because this card only exists while
 * armed — a ride records under the setting it began with. The way back to unsent
 * recordings lives here too, out of the way once a ride is under way.
 */
@Composable
private fun IdleDockContent(
    autoPauseEnabled: Boolean,
    onToggleAutoPause: (Boolean) -> Unit,
    unsentCount: Int,
    onOpenUnsent: () -> Unit,
) {
    Column(
        modifier = Modifier.padding(top = 16.dp, start = 20.dp, end = 20.dp, bottom = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        GrabHandle()
        Spacer(Modifier.size(16.dp))
        Text(
            text = stringResource(R.string.recording_ready_title).uppercase(),
            color = Rec.muted,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.6.sp,
        )
        Spacer(Modifier.size(6.dp))
        Text(
            text = stringResource(R.string.recording_ready_subtitle),
            color = Rec.muted,
            fontSize = 14.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.size(10.dp))
        Row(
            modifier = Modifier.toggleable(
                value = autoPauseEnabled,
                onValueChange = onToggleAutoPause,
                role = Role.Switch,
            ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.recording_auto_pause),
                color = Rec.ink,
                fontSize = 14.sp,
            )
            Spacer(Modifier.width(12.dp))
            Switch(checked = autoPauseEnabled, onCheckedChange = null)
        }
        if (unsentCount > 0) {
            Spacer(Modifier.size(10.dp))
            Row(
                modifier = Modifier
                    .clickable(onClick = onOpenUnsent)
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(painterResource(R.drawable.ic_cloud_off), contentDescription = null, tint = Rec.red, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(
                    text = pluralStringResource(R.plurals.recording_unsent_count, unsentCount, unsentCount),
                    color = Rec.red,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

/** The collapsed dock: distance · | · temps · [spacer] · vitesse, one row. */
@Composable
private fun CollapsedStats(ui: RecordingUiState, usesPace: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 20.dp, end = 20.dp, top = 2.dp, bottom = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "%.1f".format(ui.distanceMeters / 1000),
                color = Rec.orange,
                style = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = "tnum"),
            )
            Spacer(Modifier.width(4.dp))
            Text("km", color = Rec.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 3.dp))
        }
        Spacer(Modifier.width(16.dp))
        Box(Modifier.width(1.dp).height(26.dp).background(Rec.divider))
        Spacer(Modifier.width(16.dp))
        Text(
            text = dockElapsed(ui.elapsedSeconds).full,
            color = Rec.ink,
            style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
        )
        Spacer(Modifier.weight(1f))
        // The number in accent, the unit smaller and muted (design's collapsed speed).
        Text(collapsedSpeed(ui.currentSpeedMps, usesPace))
    }
}

/** Collapsed-dock speed: accent number + a smaller muted unit (` km/h` or ` /km`). */
private fun collapsedSpeed(metersPerSecond: Double, usesPace: Boolean): AnnotatedString {
    val number = if (usesPace) speedNumber(metersPerSecond, true) else "%.1f".format(metersPerSecond * 3.6)
    val unit = if (usesPace) " /km" else " km/h"
    return buildAnnotatedString {
        withStyle(SpanStyle(color = Rec.orange, fontSize = 20.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")) {
            append(number)
        }
        withStyle(SpanStyle(color = Rec.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)) {
            append(unit)
        }
    }
}

/** The expanded dock: Distance | Temps (two big columns) over Vitesse · Moyenne · Tours. */
@Composable
private fun ExpandedStats(ui: RecordingUiState, usesPace: Boolean, onOpenLapSplits: () -> Unit) {
    val time = dockElapsed(ui.elapsedSeconds)
    val vitLabel = if (usesPace) "Vit. /km" else "Vit. km/h"
    val moyLabel = if (usesPace) "Moy. /km" else "Moy. km/h"

    Column {
        Row(modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Column(
                modifier = Modifier.weight(1f).padding(start = 20.dp, end = 16.dp, top = 2.dp, bottom = 14.dp),
            ) {
                CaptionRow(R.drawable.ic_stat_distance, stringResource(R.string.recording_distance))
                Spacer(Modifier.size(2.dp))
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = "%.1f".format(ui.distanceMeters / 1000),
                        color = Rec.orange,
                        style = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = "tnum"),
                    )
                    Spacer(Modifier.width(5.dp))
                    Text("km", color = Rec.muted, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 5.dp))
                }
            }
            Box(Modifier.width(0.5.dp).fillMaxHeight().background(Rec.divider))
            Column(
                modifier = Modifier.weight(1f).padding(start = 16.dp, end = 20.dp, top = 2.dp, bottom = 14.dp),
            ) {
                CaptionRow(R.drawable.ic_stat_time, stringResource(R.string.recording_elapsed))
                Spacer(Modifier.size(2.dp))
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = time.big,
                        color = Rec.ink,
                        style = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = "tnum"),
                    )
                    Text(
                        text = time.small,
                        color = Rec.muted,
                        style = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
                        modifier = Modifier.padding(bottom = 3.dp),
                    )
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(Rec.divider))
        Row(modifier = Modifier.height(IntrinsicSize.Min)) {
            StatCell(speedNumber(ui.currentSpeedMps, usesPace), Rec.orange, vitLabel)
            Box(Modifier.width(0.5.dp).fillMaxHeight().background(Rec.divider))
            StatCell(speedNumber(ui.averageSpeedMps, usesPace), Rec.ink, moyLabel)
            Box(Modifier.width(0.5.dp).fillMaxHeight().background(Rec.divider))
            // The counter is the way into the splits: the dock stays the glanceable
            // summary, and the full table lives one tap away in a sheet.
            StatCell(
                value = ui.lap.toString(),
                valueColor = Rec.ink,
                caption = stringResource(R.string.recording_laps),
                modifier = Modifier
                    .clickable(onClick = onOpenLapSplits)
                    .semantics { contentDescription = "Tours" },
            )
        }
    }
}

/** A small caption row: a tinted icon + an uppercase muted label. */
@Composable
private fun CaptionRow(iconRes: Int, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(painterResource(iconRes), contentDescription = null, tint = Rec.muted, modifier = Modifier.size(13.dp))
        Spacer(Modifier.width(5.dp))
        Text(text.uppercase(), color = Rec.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.5.sp)
    }
}

/** One bottom-row stat cell: a value over an uppercase caption, centred. */
@Composable
private fun RowScope.StatCell(value: String, valueColor: Color, caption: String, modifier: Modifier = Modifier) {
    Column(
        modifier = Modifier.weight(1f).then(modifier).padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, color = valueColor, style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
        Spacer(Modifier.size(2.dp))
        Text(caption.uppercase(), color = Rec.muted, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.4.sp)
    }
}

/** Sport chip (left) ⟷ GPS chip (right), both flat white bordered chips. */
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
        FlatSportChip(selectedSport, onSelectSport, enabled = armed)
        GpsChip(accuracy)
    }
}

/**
 * Flat sport chip: a white bordered chip (icon + name) with a pull-down picker.
 * Opens only while [enabled] (pre-Démarrer); once recording the sport is locked.
 */
@Composable
private fun FlatSportChip(selected: Sport, onSelect: (Sport) -> Unit, enabled: Boolean) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .flatCard(Rec.border, 2.dp)
                .clickable(enabled = enabled) { expanded = true }
                .padding(horizontal = 13.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(painterResource(selected.iconRes), contentDescription = null, tint = Rec.ink, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(7.dp))
            Text(stringResource(selected.nameRes), color = Rec.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Sport.entries.forEach { sport ->
                DropdownMenuItem(
                    text = { Text(stringResource(sport.nameRes)) },
                    leadingIcon = {
                        Icon(painterResource(sport.iconRes), contentDescription = null, modifier = Modifier.size(20.dp))
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

/** Flat white GPS chip: a signal-coloured dot + the current status. */
@Composable
private fun GpsChip(accuracy: Float?) {
    val dotColor = when {
        accuracy == null -> Rec.muted
        accuracy <= 15f -> Rec.green
        accuracy <= 40f -> Rec.paused
        else -> Rec.red
    }
    val value = accuracy?.let { "%.0f m".format(it) } ?: stringResource(R.string.recording_gps_searching)

    Row(
        modifier = Modifier
            .flatCard(Rec.border, 2.dp)
            .padding(horizontal = 13.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(dotColor))
        Spacer(Modifier.width(7.dp))
        Text(
            text = stringResource(R.string.recording_gps_signal, value),
            color = Rec.ink,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** State pill contents: a pulsing coloured dot + uppercase coloured word. */
@Composable
private fun StatePill(recordingState: RecordingState) {
    val recording = !recordingState.isPaused
    val color = if (recording) Rec.red else Rec.paused

    val transition = rememberInfiniteTransition(label = "pill")
    val pulse by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.28f,
        animationSpec = infiniteRepeatable(tween(800), RepeatMode.Reverse),
        label = "pulse",
    )
    val dotAlpha = if (recording) pulse else 1f

    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(color).alpha(dotAlpha))
        Spacer(Modifier.width(8.dp))
        Text(
            // Pause auto is named apart from a manual pause so the rider can tell who
            // stopped the clock — and knows Reprendre will override it.
            text = stringResource(
                when (recordingState) {
                    RecordingState.AUTO_PAUSED -> R.string.recording_state_auto_paused
                    RecordingState.PAUSED -> R.string.recording_state_paused
                    else -> R.string.recording_state_recording
                },
            ).uppercase(),
            color = color,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.4.sp,
        )
    }
}

/**
 * Flat, sharp-cornered bottom controls (no Material buttons): a full-width green
 * Démarrer while armed, else Tour · Pause · Arrêter (recording) or Reprendre · Arrêter
 * (paused). [onStartStop] is handed the current [armed] flag so the caller decides
 * start vs stop.
 */
@Composable
private fun Controls(
    ui: RecordingUiState,
    onStartStop: (Boolean) -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
) {
    Column(modifier = Modifier.padding(top = 10.dp, bottom = 14.dp)) {
        if (ui.armed) {
            FlatButton(
                text = stringResource(R.string.recording_start),
                onClick = { onStartStop(true) },
                background = Rec.green,
                textColor = Rec.greenText,
                modifier = Modifier.fillMaxWidth(),
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
            )
        } else {
            // Tour is hidden in both paused states, so a stop at a red light can't
            // mint a zero-distance split.
            val paused = ui.recordingState.isPaused
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (!paused) {
                    // Visible text doubles as the label Maestro taps via "^Tour$".
                    FlatButton(
                        text = stringResource(R.string.recording_mark_lap),
                        onClick = onLap,
                        background = Rec.surface,
                        textColor = Rec.ink,
                        modifier = Modifier.weight(1f),
                        border = Rec.border,
                    )
                }
                FlatButton(
                    text = if (paused) stringResource(R.string.recording_resume) else stringResource(R.string.recording_pause),
                    onClick = { if (paused) onResume() else onPause() },
                    background = if (paused) Rec.green else Rec.surface,
                    textColor = if (paused) Rec.greenText else Rec.ink,
                    modifier = Modifier.weight(if (paused) 2f else 1f),
                    border = if (paused) null else Rec.border,
                    fontWeight = if (paused) FontWeight.Bold else FontWeight.SemiBold,
                )
                FlatButton(
                    text = stringResource(R.string.recording_stop),
                    onClick = { onStartStop(false) },
                    background = Rec.surface,
                    textColor = Rec.red,
                    modifier = Modifier.weight(1f),
                    border = Rec.redBorder,
                )
            }
        }
    }
}

/** A flat, sharp-cornered button (Box + optional border) — replaces Material buttons. */
@Composable
internal fun FlatButton(
    text: String,
    onClick: () -> Unit,
    background: Color,
    textColor: Color,
    modifier: Modifier = Modifier,
    border: Color? = null,
    fontWeight: FontWeight = FontWeight.SemiBold,
    fontSize: TextUnit = 15.sp,
) {
    Box(
        modifier = modifier
            .background(background)
            .then(if (border != null) Modifier.border(1.dp, border) else Modifier)
            .clickable(onClick = onClick)
            .padding(vertical = 15.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = textColor, fontWeight = fontWeight, fontSize = fontSize)
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

/** Elapsed split for the dock: `full` (collapsed) plus a big head + small `:ss` tail
 *  (expanded), matching the design's two-weight time (e.g. 4:38 / :20). */
private data class DockTime(val full: String, val big: String, val small: String)

private fun dockElapsed(totalSeconds: Long): DockTime {
    val h = totalSeconds / 3600
    val m = (totalSeconds % 3600) / 60
    val s = totalSeconds % 60
    val small = ":%02d".format(s)
    return if (h > 0) {
        DockTime("%d:%02d:%02d".format(h, m, s), "%d:%02d".format(h, m), small)
    } else {
        DockTime("%d:%02d".format(m, s), "$m", small)
    }
}

/** The value only (no unit) for the bottom stat cells. */
private fun speedNumber(metersPerSecond: Double, usesPace: Boolean): String =
    if (usesPace) {
        RecordingFormatters.pace(metersPerSecond).removeSuffix("/km")
    } else {
        "%.1f".format(metersPerSecond * 3.6)
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
            autoPauseEnabled = true,
            onToggleAutoPause = {},
            unsentCount = 0,
            onOpenUnsent = {},
            onStartStop = {},
            onPause = {},
            onResume = {},
            onLap = {},
            onOpenSettings = {},
        )
    }
}
