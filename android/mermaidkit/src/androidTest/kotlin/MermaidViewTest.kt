package ai.mermaidkit

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The classic-View snap-in surface end-to-end: set a source string on a
 * [MermaidView], run the real Android measure/layout/draw pipeline, and confirm
 * it sizes to width, draws ink, and exposes the narration as contentDescription.
 * Needs the cross-compiled jniLibs (MermaidView parses natively).
 */
@RunWith(AndroidJUnit4::class)
class MermaidViewTest {

    private val ctx = InstrumentationRegistry.getInstrumentation().targetContext
    private val source = "flowchart LR\n A[Start] --> B{Choice}\n B --> C((Done))"

    @Test
    fun rendersSourceSizesAndDescribes() {
        val view = MermaidView(ctx)
        view.source = source

        val width = 800
        view.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        assertEquals("view fills the width it's given", width, view.measuredWidth)
        assertTrue("wrap_content height follows the scene aspect", view.measuredHeight > 0)
        view.layout(0, 0, view.measuredWidth, view.measuredHeight)

        val bmp = Bitmap.createBitmap(view.measuredWidth, view.measuredHeight, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bmp))
        var inked = 0
        for (y in 0 until bmp.height) for (x in 0 until bmp.width) {
            if (bmp.getPixel(x, y) != Color.WHITE) inked++
        }
        assertTrue("MermaidView should draw the diagram, got $inked ink px", inked > 500)

        // Accessibility from the first surface.
        val desc = view.contentDescription
        assertNotNull("contentDescription should be set from the narration", desc)
        assertTrue("narration should mention a node, was: $desc",
            desc.toString().contains("Start"))
    }

    @Test
    fun blankSourceClears() {
        val view = MermaidView(ctx)
        view.source = source
        assertNotNull(view.contentDescription)
        view.source = ""
        assertTrue(view.contentDescription == null)
    }
}
