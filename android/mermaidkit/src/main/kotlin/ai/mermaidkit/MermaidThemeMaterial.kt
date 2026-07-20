package ai.mermaidkit

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb

/**
 * Build a [MermaidTheme] from a Material 3 [ColorScheme] — so a diagram picks up
 * the app's own theme (and light/dark) instead of a built-in preset. This is the
 * default source of the theme in [MermaidDiagram].
 *
 * The mapping is a deliberate, documented default (Material's roles → the
 * diagram's color slots):
 * - ink ← `onSurface`, accent ← `primary`, canvas ← `surface`
 * - hairline ← `outlineVariant`
 * - secondaryText ← `onSurfaceVariant`; tertiaryText ← `onSurfaceVariant` @ 70%
 * - palette ← `[primary, tertiary, secondary, error]` (categorical hues)
 * - prefersDark ← derived from the surface's luminance
 *
 * Override any of it by copying the returned [MermaidTheme].
 */
fun MermaidTheme.Companion.fromMaterial(
    colors: ColorScheme,
    prefersDark: Boolean = colors.surface.luminance() < 0.5f,
): MermaidTheme = MermaidTheme(
    ink = colors.onSurface.toArgb(),
    accent = colors.primary.toArgb(),
    canvas = colors.surface.toArgb(),
    hairline = colors.outlineVariant.toArgb(),
    secondaryText = colors.onSurfaceVariant.toArgb(),
    tertiaryText = colors.onSurfaceVariant.copy(alpha = 0.7f).toArgb(),
    palette = listOf(colors.primary, colors.tertiary, colors.secondary, colors.error)
        .map { it.toArgb() },
    prefersDark = prefersDark,
)
