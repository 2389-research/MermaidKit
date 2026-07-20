package ai.mermaidkit

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import ai.mermaidkit.scene.SceneRenderer
import ai.mermaidkit.scene.SceneWire
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The end-to-end proof on a real Android runtime: a wire scene drawn through the
 * device's actual Skia `Canvas` must land real ink — a fill, a stroked edge, an
 * arrowhead, and text. Runs on the emulator (needs KVM); the JVM unit tests
 * cover parsing without a device.
 */
@RunWith(AndroidJUnit4::class)
class RenderInstrumentedTest {

    // A hand-written scene exercising every element kind (shape+fill+stroke,
    // polyline+arrow, text) — the exact SceneWire JSON shape the C ABI emits.
    private val json = """
        {"version":1,"size":{"w":200,"h":100},"background":"#FFFFFFFF","elements":[
          {"type":"shape","path":{"type":"roundedRect","rect":{"x":20,"y":30,"w":80,"h":40},"radius":6},
           "fill":"#5B8FF9FF","stroke":{"color":"#1D1D1FFF","width":2,"dashed":false}},
          {"type":"polyline","points":[{"x":100,"y":50},{"x":185,"y":50}],"endArrow":true,"startArrow":false,
           "stroke":{"color":"#1D1D1FFF","width":2,"dashed":false}},
          {"type":"text","string":"Hi","center":{"x":60,"y":50},"fontSize":16,"weight":"medium","color":"#1D1D1FFF","rotation":0}
        ]}
    """.trimIndent()

    @Test
    fun rendersNonBlankBitmap() {
        val scene = SceneWire.parse(json)
        val bmp = Bitmap.createBitmap(
            scene.size.w.toInt(), scene.size.h.toInt(), Bitmap.Config.ARGB_8888)
        SceneRenderer().draw(scene, Canvas(bmp))

        // Real ink must mark the canvas (fill + stroke + arrow + glyphs).
        var inked = 0
        for (y in 0 until bmp.height) for (x in 0 until bmp.width) {
            if (bmp.getPixel(x, y) != Color.WHITE) inked++
        }
        assertTrue("expected ink on the canvas, got $inked non-white px", inked > 300)

        // The blue node fill must actually be blue where the rect is.
        val inside = bmp.getPixel(40, 40)
        assertTrue("node fill should read blue (b>r), got #${Integer.toHexString(inside)}",
            Color.blue(inside) > Color.red(inside))

        // The arrowhead region (right of the node) must have dark ink.
        var darkNearArrow = false
        for (x in 150 until 190) if (Color.red(bmp.getPixel(x, 50)) < 80) darkNearArrow = true
        assertTrue("arrow/edge ink expected near the tip", darkNearArrow)
    }

    /**
     * Renders a real fixture (a flowchart lowered by the Swift pipeline, captured
     * as golden JSON) at 3× onto the device Canvas and writes a PNG to the test's
     * external files dir. Not a strict assertion — the visual artifact of the
     * on-device render, pullable via `adb pull` for inspection.
     */
    @Test
    fun capturesFlowchartRenderToPng() {
        val ctx = InstrumentationRegistry.getInstrumentation().context
        val text = ctx.assets.open("flowchart.json").bufferedReader().use { it.readText() }
        val scene = SceneWire.parse(text)

        val scale = 3f
        val bmp = Bitmap.createBitmap(
            (scene.size.w * scale).toInt(), (scene.size.h * scale).toInt(),
            Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.scale(scale, scale)
        SceneRenderer().draw(scene, canvas)

        val out = File(ctx.getExternalFilesDir(null), "flowchart_render.png")
        out.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue("PNG should have been written (${out.length()} bytes)", out.length() > 0)
    }
}
