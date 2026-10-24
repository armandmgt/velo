package fr.armandmgt.velo.features.record

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.data.RecordingDao
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/** A recording that was stopped but never reached the server, as the list shows it. */
data class UnsentRecording(
    val id: String,
    val startedAt: Long,
    val sport: Sport,
    val stats: RecordingHandoff.Stats,
)

/**
 * The unsent recordings, newest first, kept current as recordings are stopped,
 * sent or deleted. Points are only read for sessions stopped without stored totals.
 */
fun RecordingDao.unsentRecordings(fallbackSport: Sport): Flow<List<UnsentRecording>> =
    stoppedSessions().map { sessions ->
        sessions.map { session ->
            val points = if (session.stoppedAt == null) pointsFor(session.id) else emptyList()
            UnsentRecording(
                id = session.id,
                startedAt = session.startedAt,
                sport = RecordingHandoff.sportOf(session, fallbackSport),
                stats = RecordingHandoff.finalStats(session, points),
            )
        }
    }

/**
 * Recordings that were stopped but never reached the server — the review page
 * failed to load, or the app died before the upload committed. Mirrors the iOS
 * `UnsentRecordingsViewController`: Envoyer reopens the web review on the stored
 * recording exactly as Arrêter does, and Supprimer deletes it after a confirmation.
 */
@Composable
fun UnsentRecordingsScreen(
    recordings: List<UnsentRecording>,
    onSend: (String) -> Unit,
    onDelete: (String) -> Unit,
    onBack: () -> Unit,
) {
    var confirmingDelete by remember { mutableStateOf<String?>(null) }

    Scaffold(containerColor = PAGE) { innerPadding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = innerPadding.calculateTopPadding() + 8.dp,
                bottom = innerPadding.calculateBottomPadding() + 24.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    text = "‹ " + stringResource(R.string.recording_unsent_back),
                    color = Rec.ink,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clickable(onClick = onBack)
                        .padding(vertical = 8.dp),
                )
                Text(
                    text = stringResource(R.string.recording_unsent_title),
                    color = Rec.ink,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.recording_unsent_intro), color = Rec.muted, fontSize = 14.sp)
                Spacer(Modifier.size(4.dp))
            }
            items(recordings, key = { it.id }) { recording ->
                UnsentRecordingCard(
                    recording = recording,
                    onSend = { onSend(recording.id) },
                    onDelete = { confirmingDelete = recording.id },
                )
            }
        }
    }

    confirmingDelete?.let { id ->
        AlertDialog(
            onDismissRequest = { confirmingDelete = null },
            title = { Text(stringResource(R.string.recording_discard_confirm_title)) },
            text = { Text(stringResource(R.string.recording_discard_confirm_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingDelete = null
                    onDelete(id)
                }) { Text(stringResource(R.string.recording_discard), color = Rec.red) }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = null }) {
                    Text(stringResource(R.string.recording_discard_cancel))
                }
            },
        )
    }
}

@Composable
private fun UnsentRecordingCard(recording: UnsentRecording, onSend: () -> Unit, onDelete: () -> Unit) {
    val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.FRANCE)
        .format(Date(recording.startedAt))

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .flatCard(Rec.borderDock, 0.dp)
            .semantics { contentDescription = "unsentRecording" }
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(painterResource(recording.sport.iconRes), contentDescription = null, tint = Rec.ink, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(stringResource(recording.sport.nameRes), color = Rec.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text(date, color = Rec.muted, fontSize = 13.sp)
        }
        Spacer(Modifier.size(14.dp))
        Row(modifier = Modifier.height(IntrinsicSize.Min)) {
            Figure(
                caption = stringResource(R.string.recording_distance),
                value = "${RecordingFormatters.distanceKilometers(recording.stats.distance)} km",
                color = Rec.orange,
            )
            Spacer(Modifier.width(16.dp))
            Spacer(Modifier.width(1.dp).fillMaxHeight().background(Rec.divider))
            Spacer(Modifier.width(16.dp))
            Figure(
                caption = stringResource(R.string.recording_unsent_elapsed),
                value = RecordingFormatters.elapsed(recording.stats.elapsed),
                color = Rec.ink,
            )
        }
        Spacer(Modifier.size(14.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FlatButton(
                text = stringResource(R.string.recording_discard),
                onClick = onDelete,
                background = Rec.surface,
                textColor = Rec.red,
                border = Rec.redBorder,
                modifier = Modifier.weight(1f),
            )
            FlatButton(
                text = stringResource(R.string.recording_unsent_send),
                onClick = onSend,
                background = Rec.green,
                textColor = Rec.greenText,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun Figure(caption: String, value: String, color: Color) {
    Column {
        Text(caption.uppercase(), color = Rec.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.5.sp)
        Spacer(Modifier.size(2.dp))
        Text(value, color = color, style = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = "tnum"))
    }
}

/** The screen behind the cards, matching the iOS `Palette.page`. */
private val PAGE = Color(0xFFF4F4F4)
