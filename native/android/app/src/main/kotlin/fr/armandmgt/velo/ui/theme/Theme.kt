package fr.armandmgt.velo.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.colorResource
import fr.armandmgt.velo.R

/**
 * Compose theme for the app's native (Compose) surfaces, mapping the web app's
 * daisyUI "bike" / "bike-dark" palette onto Material 3 color roles. The brand_*
 * color resources carry both light and dark values (values + values-night), so
 * `colorResource` resolves the right one; `isSystemInDarkTheme()` only selects
 * which Material defaults fill the roles we don't override.
 */
@Composable
fun VeloTheme(content: @Composable () -> Unit) {
    val primary = colorResource(R.color.brand_primary)
    val onPrimary = colorResource(R.color.brand_on_primary)
    val secondary = colorResource(R.color.brand_secondary)
    val onSecondary = colorResource(R.color.brand_on_secondary)
    val error = colorResource(R.color.brand_error)
    val onError = colorResource(R.color.brand_on_error)
    val base100 = colorResource(R.color.brand_base_100)
    val base200 = colorResource(R.color.brand_base_200)
    val base300 = colorResource(R.color.brand_base_300)
    val baseContent = colorResource(R.color.brand_base_content)

    val colorScheme = veloColorScheme(
        dark = isSystemInDarkTheme(),
        primary = primary,
        onPrimary = onPrimary,
        secondary = secondary,
        onSecondary = onSecondary,
        error = error,
        onError = onError,
        base100 = base100,
        base200 = base200,
        base300 = base300,
        baseContent = baseContent,
    )

    MaterialTheme(colorScheme = colorScheme, content = content)
}

private fun veloColorScheme(
    dark: Boolean,
    primary: Color,
    onPrimary: Color,
    secondary: Color,
    onSecondary: Color,
    error: Color,
    onError: Color,
    base100: Color,
    base200: Color,
    base300: Color,
    baseContent: Color,
) = (if (dark) darkColorScheme() else lightColorScheme()).copy(
    primary = primary,
    onPrimary = onPrimary,
    primaryContainer = primary,
    onPrimaryContainer = onPrimary,
    secondary = secondary,
    onSecondary = onSecondary,
    secondaryContainer = secondary,
    onSecondaryContainer = onSecondary,
    tertiary = secondary,
    onTertiary = onSecondary,
    error = error,
    onError = onError,
    background = base200,
    onBackground = baseContent,
    surface = base100,
    onSurface = baseContent,
    surfaceVariant = base300,
    onSurfaceVariant = baseContent,
)
