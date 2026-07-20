package ai.mermaidkit

import android.graphics.Paint

/**
 * A [MermaidNative.Measurer] backed by an Android [Paint] — the pinned measure
 * seam. Native layout calls this to size text with the *same* face that
 * [ai.mermaidkit.scene.SceneRenderer] draws with, so on-device layout and draw
 * agree (node boxes fit their labels, edge labels don't clip).
 *
 * Width is `Paint.measureText`; height is the font's line height
 * (`descent - ascent`) — matching the metric `SceneRenderer` uses to vertically
 * center a run. The [Paint]'s typeface should match the renderer's (default
 * sans); the ABI's measure callback carries only text + size, not weight, so a
 * single base face is used for measurement (a small width difference vs. the
 * medium/semibold draw face — see docs/notes/android.md).
 */
class PaintMeasurer(paint: Paint? = null) : MermaidNative.Measurer {

    // A private copy so mutating textSize per call never disturbs a Paint the
    // caller also draws with.
    private val paint: Paint = (paint?.let { Paint(it) } ?: Paint(Paint.ANTI_ALIAS_FLAG))

    override fun measure(text: String, fontSize: Double): DoubleArray {
        paint.textSize = fontSize.toFloat()
        val width = paint.measureText(text).toDouble()
        val fm = paint.fontMetrics
        val height = (fm.descent - fm.ascent).toDouble()
        return doubleArrayOf(width, height)
    }
}
