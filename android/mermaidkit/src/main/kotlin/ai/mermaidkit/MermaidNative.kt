package ai.mermaidkit

import ai.mermaidkit.scene.SceneWire

/**
 * The native bridge to the Swift core (the `mmk_*` C ABI via a JNI shim). Loads
 * `libmermaidkit.so`, which pulls in `libMermaidKitCDynamic.so` and the Swift
 * runtime `.so`s packaged alongside it in the AAR's `jniLibs`.
 *
 * This is the seam that lets an app go from a Mermaid **source string** to a
 * drawable scene without any Swift or NDK of its own: [scene] parses the source
 * natively and returns a [SceneWire] ready for [ai.mermaidkit.scene.SceneRenderer].
 *
 * Measurement: pass a [Measurer] so native layout measures text with the *same*
 * face that draws it (the pinned measure seam — see docs/notes/android.md and the
 * issue-#62 lesson). Use [PaintMeasurer] to back it with the drawing `Paint`.
 * With no measurer, layout falls back to a coarse glyph-box metric.
 */
object MermaidNative {
    init {
        System.loadLibrary("mermaidkit")
    }

    /**
     * A text-measurement seam the native layout calls back into. [measure] returns
     * `[width, height]` in points for `text` at `fontSize` — measured with the face
     * that will ultimately draw, so on-device layout and draw agree.
     *
     * Called synchronously from native code on the calling thread; keep it fast
     * and allocation-light (it runs once per text run). A throwing measurer is
     * caught natively and treated as "no measurement" for that run.
     */
    fun interface Measurer {
        fun measure(text: String, fontSize: Double): DoubleArray
    }

    private external fun nativeSceneJson(source: String, prefersDark: Int): String?
    private external fun nativeSceneJsonMeasured(
        source: String, prefersDark: Int, measurer: Measurer): String?
    private external fun nativeSceneJsonThemed(
        source: String, themeJson: String?, measurer: Measurer?): String?
    private external fun nativeNarrate(source: String): String?
    private external fun nativeVersion(): String

    /** The scene as wire JSON, or null when `source` is empty or fails to parse. */
    fun sceneJson(source: String, prefersDark: Boolean = false, measurer: Measurer? = null): String? {
        val dark = if (prefersDark) 1 else 0
        return if (measurer != null) nativeSceneJsonMeasured(source, dark, measurer)
        else nativeSceneJson(source, dark)
    }

    /** The scene as wire JSON themed with [theme]'s colors, or null on failure. */
    fun sceneJson(source: String, theme: MermaidTheme, measurer: Measurer? = null): String? =
        nativeSceneJsonThemed(source, theme.toWireJson(), measurer)

    /**
     * Parse `source` natively into a [SceneWire], or null when it fails to parse.
     * Pass a [measurer] (e.g. [PaintMeasurer]) for device-faithful text metrics.
     */
    fun scene(source: String, prefersDark: Boolean = false, measurer: Measurer? = null): SceneWire? =
        sceneJson(source, prefersDark, measurer)?.let { SceneWire.parse(it) }

    /**
     * Parse `source` natively into a [SceneWire] painted with [theme]'s colors
     * (e.g. `MermaidTheme.fromMaterial(...)`), or null when it fails to parse.
     */
    fun scene(source: String, theme: MermaidTheme, measurer: Measurer? = null): SceneWire? =
        sceneJson(source, theme, measurer)?.let { SceneWire.parse(it) }

    /** An accessibility walkthrough of `source` for `contentDescription`, or null. */
    fun narrate(source: String): String? = nativeNarrate(source)

    /** The MermaidKitC ABI version string. */
    fun version(): String = nativeVersion()
}
