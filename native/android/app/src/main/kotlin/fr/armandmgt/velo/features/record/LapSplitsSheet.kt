package fr.armandmgt.velo.features.record

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fr.armandmgt.velo.R

/**
 * The lap sheet — opened from the recording dock's Tours counter while riding.
 *
 * A sheet rather than a permanent dock section: riders glance at the dock
 * mid-effort and read the table when they have a moment, so the splits cost the
 * dock no standing height. Laps are device-local (ADR 0001): this table and the
 * web review are the only places they are ever shown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LapSplitsSheet(
    ui: RecordingUiState,
    usesPace: Boolean,
    onDismiss: () -> Unit,
) {
    val splits = LapSplits.splits(
        boundaries = ui.lapBoundaries,
        totalDistance = ui.distanceMeters,
        totalElapsed = ui.elapsedSeconds.toDouble(),
    )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Rec.surface,
        // Sharp-cornered like every other recording surface, not Material's rounded sheet.
        shape = RectangleShape,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(
                    text = stringResource(R.string.recording_laps),
                    color = Rec.ink,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = stringResource(
                        R.string.recording_laps_summary,
                        RecordingFormatters.distanceKilometers(ui.distanceMeters),
                        RecordingFormatters.elapsed(ui.elapsedSeconds.toDouble()),
                    ),
                    color = Rec.muted,
                    style = TextStyle(fontSize = 13.sp, fontFeatureSettings = "tnum"),
                )
            }

            SplitHeaderRow(usesPace)
            Hairline()
            splits.forEachIndexed { index, split ->
                SplitRow(split, usesPace)
                if (index < splits.lastIndex) Hairline()
            }

            splits.firstOrNull { it.isInProgress }?.let { running ->
                Text(
                    text = stringResource(R.string.recording_laps_in_progress, running.ordinal),
                    color = Rec.muted,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp),
                )
            }

            Spacer(Modifier.size(20.dp))
            FlatButton(
                text = stringResource(R.string.recording_laps_close),
                onClick = onDismiss,
                background = Rec.surface,
                textColor = Rec.ink,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                border = Rec.border,
            )
        }
    }
}

@Composable
private fun SplitHeaderRow(usesPace: Boolean) {
    SplitGridRow(
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 7.dp),
        lap = { Caption(stringResource(R.string.recording_laps_column_lap)) },
        distance = { Caption(stringResource(R.string.recording_laps_column_distance)) },
        time = { Caption(stringResource(R.string.recording_laps_column_time)) },
        speed = {
            Caption(
                stringResource(
                    if (usesPace) R.string.recording_laps_column_pace else R.string.recording_laps_column_speed,
                ),
            )
        },
    )
}

/**
 * The lap in progress is called out with an accent rule down its leading edge and
 * a tinted row, rather than a punctuation mark that is easy to miss mid-ride.
 */
@Composable
private fun SplitRow(split: LapSplit, usesPace: Boolean) {
    val weight = if (split.isInProgress) FontWeight.Bold else FontWeight.Normal
    val background = if (split.isInProgress) Rec.orange.copy(alpha = 0.08f) else Color.Transparent

    Row(Modifier.fillMaxWidth().background(background)) {
        Box(Modifier.width(if (split.isInProgress) 3.dp else 0.dp).height(46.dp).background(Rec.orange))
        SplitGridRow(
            modifier = Modifier.padding(
                start = if (split.isInProgress) 17.dp else 20.dp,
                end = 20.dp,
                top = 13.dp,
                bottom = 13.dp,
            ),
            lap = { Number(split.ordinal.toString(), size = 16.sp, weight = FontWeight.Bold) },
            distance = {
                Number(
                    "${RecordingFormatters.distanceKilometers(split.distance)} km",
                    weight = if (split.isInProgress) FontWeight.Bold else FontWeight.SemiBold,
                )
            },
            time = { Number(RecordingFormatters.elapsed(split.elapsed), weight = weight) },
            speed = {
                Number(
                    RecordingFormatters.speedOrPace(split.averageSpeed, usesPace),
                    weight = weight,
                    color = Rec.muted,
                )
            },
        )
    }
}

/** Lap number in a fixed column, then three equal right-aligned columns. */
@Composable
private fun SplitGridRow(
    modifier: Modifier,
    lap: @Composable () -> Unit,
    distance: @Composable () -> Unit,
    time: @Composable () -> Unit,
    speed: @Composable () -> Unit,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(26.dp)) { lap() }
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { distance() }
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { time() }
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { speed() }
    }
}

@Composable
private fun Caption(text: String) {
    Text(
        text = text.uppercase(),
        color = Rec.muted,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.5.sp,
        textAlign = TextAlign.End,
    )
}

@Composable
private fun Number(
    text: String,
    size: TextUnit = 16.sp,
    weight: FontWeight = FontWeight.Normal,
    color: Color = Rec.ink,
) {
    Text(text, color = color, style = TextStyle(fontSize = size, fontWeight = weight, fontFeatureSettings = "tnum"))
}

@Composable
private fun Hairline() {
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(Rec.divider))
}
