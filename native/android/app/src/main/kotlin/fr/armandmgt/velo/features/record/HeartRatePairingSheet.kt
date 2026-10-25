package fr.armandmgt.velo.features.record

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fr.armandmgt.velo.R

/**
 * The strap picker, opened from the armed card: the heart-rate straps nearby,
 * listed by name as they are found. Tapping one remembers it and connects.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HeartRatePairingSheet(
    state: HeartRateUiState,
    onSelect: (HeartRateStrap) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Rec.surface,
        shape = RectangleShape,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.heart_rate_pairing_title),
                color = Rec.ink,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = stringResource(R.string.heart_rate_pairing_intro),
                color = Rec.muted,
                fontSize = 14.sp,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!state.bluetoothUnavailable) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = Rec.muted)
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    text = stringResource(
                        when {
                            state.bluetoothUnavailable -> R.string.heart_rate_pairing_unavailable
                            state.discoveredStraps.isEmpty() -> R.string.heart_rate_pairing_searching
                            else -> R.string.heart_rate_pairing_pick
                        },
                    ),
                    color = Rec.muted,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            state.discoveredStraps.forEach { strap ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(1.dp, Rec.border)
                        .clickable { onSelect(strap) }
                        .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(painterResource(R.drawable.ic_favorite), contentDescription = null, tint = Rec.red, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(strap.name, color = Rec.ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.size(8.dp))
            FlatButton(
                text = stringResource(R.string.heart_rate_pairing_cancel),
                onClick = onDismiss,
                background = Rec.surface,
                textColor = Rec.ink,
                modifier = Modifier.fillMaxWidth(),
                border = Rec.border,
            )
        }
    }
}
