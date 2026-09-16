package fr.armandmgt.velo.features.record

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The design's flat, light palette (Recording.dc.html): sharp-cornered white
 * surfaces with thin borders — deliberately *not* Material tokens, so the native
 * recording surfaces match the web pixel-for-pixel.
 */
internal object Rec {
    val ink = Color(0xFF161616)        // primary text        — oklch(20% 0 0)
    val muted = Color(0xFF555555)      // captions / secondary — oklch(45% 0 0)
    val border = Color(0xFFCECECE)     // chip / button border — oklch(85% 0 0)
    val borderDock = Color(0xFFD7D7D7) // dock border          — oklch(88% 0 0)
    val divider = Color(0xFFE4E4E4)    // internal dividers    — oklch(92% 0 0)
    val grabber = Color(0xFFC4C4C4)    // grab handle          — oklch(82% 0 0)
    val orange = Color(0xFFF69900)     // distance / speed     — web `--color-primary` resolved
    val green = Color(0xFF20C45F)      // Démarrer fill        — oklch(72% 0.19 150)
    val greenText = Color(0xFF08351A)  // Démarrer text        — oklch(24% 0.06 153)
    val redBorder = Color(0xFFFF627E)  // Arrêter border       — oklch(71% 0.194 13.4)
    val red = Color(0xFFDD1B53)        // Arrêter / rec pill   — oklch(58% 0.22 13.4)
    val paused = Color(0xFFD36000)     // paused pill          — oklch(62% 0.18 56)
    val surface = Color(0xFFFFFFFF)
}

/** A flat white sharp-cornered card: soft shadow + 1px border, no rounded corners. */
internal fun Modifier.flatCard(borderColor: Color, elevation: Dp): Modifier =
    this
        .shadow(elevation, RectangleShape, clip = false)
        .background(Rec.surface)
        .border(1.dp, borderColor)
