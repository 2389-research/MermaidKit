package ai.mermaidkit

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import ai.mermaidkit.scene.Element
import ai.mermaidkit.scene.SceneRenderer
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The JNI seam end-to-end on a real device: a Mermaid **source string** goes
 * through `MermaidNative` (JNI → the Swift `mmk_*` C ABI in `libmermaidkit.so`)
 * and comes back as a scene that draws to a `Canvas`. This is the whole point of
 * the native bridge — an app hands over source, not a pre-lowered scene.
 *
 * Requires the cross-compiled `jniLibs` (android/native/build-jni.sh) to be
 * present, so it only runs where the `.so`s were built + packaged.
 */
@RunWith(AndroidJUnit4::class)
class NativeBridgeTest {

    private val source = """
        flowchart LR
            A[Start] --> B{Choice}
            B -->|yes| C((Done))
            B -->|no| D[Stop]
    """.trimIndent()

    @Test
    fun versionLoadsThroughJni() {
        // Proves libmermaidkit.so + the Swift runtime .so's all loaded and a
        // trivial call returns.
        val v = MermaidNative.version()
        assertTrue("version was: $v", v.contains("MermaidKitC"))
    }

    @Test
    fun sceneJsonFromSourceParsesAndRenders() {
        // Native parse + lower + encode.
        val json = MermaidNative.sceneJson(source)
        assertNotNull("mmk_scene_json returned null for a valid source", json)
        assertTrue(json!!.contains("\"type\":\"polyline\""))
        assertTrue(json.contains("\"type\":\"shape\""))

        // Straight into the Kotlin model + renderer.
        val scene = MermaidNative.scene(source)
        assertNotNull(scene)
        assertTrue(scene!!.elements.any { it is Element.Shape })
        assertTrue(scene.elements.any { it is Element.Polyline })

        val bmp = Bitmap.createBitmap(
            scene.size.w.toInt().coerceAtLeast(1),
            scene.size.h.toInt().coerceAtLeast(1),
            Bitmap.Config.ARGB_8888)
        SceneRenderer().draw(scene, Canvas(bmp))
        var inked = 0
        for (y in 0 until bmp.height) for (x in 0 until bmp.width) {
            if (bmp.getPixel(x, y) != Color.WHITE) inked++
        }
        assertTrue("native-parsed scene should render ink, got $inked", inked > 300)
    }

    @Test
    fun narrateThreadsThroughJni() {
        val narration = MermaidNative.narrate(source)
        assertNotNull(narration)
        assertTrue("narration: $narration", narration!!.contains("Start"))
    }

    @Test
    fun invalidSourceReturnsNull() {
        // The ABI returns nil (never traps) on unparseable input.
        assertTrue(MermaidNative.sceneJson("not a diagram at all") == null)
    }
}
