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
 * Measurement note: this first slice passes no measure callback, so native
 * layout uses a coarse glyph-box metric. Threading the device `Paint.measureText`
 * callback through JNI (so layout measures with the face that draws) is the next
 * slice — see docs/notes/android.md.
 */
object MermaidNative {
    init {
        System.loadLibrary("mermaidkit")
    }

    private external fun nativeSceneJson(source: String, prefersDark: Int): String?
    private external fun nativeNarrate(source: String): String?
    private external fun nativeVersion(): String

    /** The scene as wire JSON, or null when `source` is empty or fails to parse. */
    fun sceneJson(source: String, prefersDark: Boolean = false): String? =
        nativeSceneJson(source, if (prefersDark) 1 else 0)

    /** Parse `source` natively into a [SceneWire], or null when it fails to parse. */
    fun scene(source: String, prefersDark: Boolean = false): SceneWire? =
        sceneJson(source, prefersDark)?.let { SceneWire.parse(it) }

    /** An accessibility walkthrough of `source` for `contentDescription`, or null. */
    fun narrate(source: String): String? = nativeNarrate(source)

    /** The MermaidKitC ABI version string. */
    fun version(): String = nativeVersion()
}
