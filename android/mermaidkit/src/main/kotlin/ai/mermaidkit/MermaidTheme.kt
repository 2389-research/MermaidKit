package ai.mermaidkit

/**
 * A diagram color theme, as ARGB [Int]s (the form `android.graphics.Color` and
 * `Color.toArgb()` produce). Serializes to the `ThemeWire` JSON the native core
 * reads across the C ABI, so a scene is painted with *these* colors instead of a
 * built-in light/dark preset.
 *
 * Build one from a Material `ColorScheme` with `MermaidTheme.fromMaterial(...)`
 * (see `MermaidThemeMaterial.kt`), or construct the slots directly.
 *
 * - [ink]: primary text + strokes (node borders, arrows, labels)
 * - [accent]: highlight; node fills use it at low alpha
 * - [canvas]: background fill
 * - [hairline]: thin rules (sequence bands, fragment tabs)
 * - [secondaryText]: de-emphasized text (edge labels)
 * - [tertiaryText]: most de-emphasized (fragment guards, note captions)
 * - [palette]: categorical hues, cycled by index
 * - [prefersDark]: whether the canvas is dark (a few tints key off it)
 */
data class MermaidTheme(
    val ink: Int,
    val accent: Int,
    val canvas: Int,
    val hairline: Int,
    val secondaryText: Int,
    val tertiaryText: Int,
    val palette: List<Int>,
    val prefersDark: Boolean,
) {
    /** The `ThemeWire` JSON the native `mmk_scene_json_themed` decodes. */
    fun toWireJson(): String {
        val pal = palette.joinToString(",") { "\"${it.toRgbaHex()}\"" }
        return "{" +
            "\"ink\":\"${ink.toRgbaHex()}\"," +
            "\"accent\":\"${accent.toRgbaHex()}\"," +
            "\"canvas\":\"${canvas.toRgbaHex()}\"," +
            "\"hairline\":\"${hairline.toRgbaHex()}\"," +
            "\"secondaryText\":\"${secondaryText.toRgbaHex()}\"," +
            "\"tertiaryText\":\"${tertiaryText.toRgbaHex()}\"," +
            "\"palette\":[$pal]," +
            "\"prefersDark\":$prefersDark}"
    }

    companion object
}

/** An ARGB [Int] as a `#RRGGBBAA` string (locale-independent, lowercase hex). */
private fun Int.toRgbaHex(): String {
    val v = this
    fun component(shift: Int) = ((v ushr shift) and 0xFF).toString(16).padStart(2, '0')
    return "#${component(16)}${component(8)}${component(0)}${component(24)}"
}
