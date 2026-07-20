package ai.mermaidkit

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import ai.mermaidkit.scene.SceneRenderer
import ai.mermaidkit.scene.SceneWire

/**
 * A classic Android [View] that renders a Mermaid diagram from a **source
 * string** — the whole pipeline (native parse → `SceneWire` → `Canvas` draw)
 * behind one property. Set [source] and it draws; the diagram's accessibility
 * narration is set as the view's `contentDescription` automatically.
 *
 * Sizing: the view reports the scene's intrinsic size, scaled to fit the width
 * it's given (aspect preserved). In a `wrap_content` height it takes the scaled
 * height; a fixed height letterboxes via the same uniform scale.
 *
 * This class has **no Compose dependency** — Compose apps use [MermaidDiagram].
 * Text is measured with the same [Paint] that draws (via [PaintMeasurer]) so
 * on-device layout and draw agree.
 */
class MermaidView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    private val renderer = SceneRenderer()
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
    private val measurer = PaintMeasurer(textPaint)
    private var scene: SceneWire? = null

    /** The Mermaid source to render. Null/blank clears the view. */
    var source: String? = null
        set(value) {
            if (field == value) return
            field = value
            reparse()
        }

    /** Select the dark preset. Re-parses the scene. */
    var prefersDark: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            reparse()
        }

    private fun reparse() {
        val s = source
        scene = if (s.isNullOrBlank()) null else MermaidNative.scene(s, prefersDark, measurer)
        // Accessibility from the first surface (per the plan): the narration
        // walkthrough becomes the view's contentDescription.
        contentDescription = s?.takeIf { it.isNotBlank() }?.let { MermaidNative.narrate(it) }
        requestLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val sc = scene
        if (sc == null || sc.size.w <= 0 || sc.size.h <= 0) {
            setMeasuredDimension(
                resolveSize(suggestedMinimumWidth, widthMeasureSpec),
                resolveSize(suggestedMinimumHeight, heightMeasureSpec))
            return
        }
        val availW = MeasureSpec.getSize(widthMeasureSpec)
        val wMode = MeasureSpec.getMode(widthMeasureSpec)
        // Width: fill what we're offered (AT_MOST/EXACTLY), else intrinsic.
        val width = if (wMode == MeasureSpec.UNSPECIFIED) sc.size.w.toInt() else availW
        val scale = width / sc.size.w
        val height = resolveSize((sc.size.h * scale).toInt(), heightMeasureSpec)
        setMeasuredDimension(width, height)
    }

    override fun onDraw(canvas: Canvas) {
        val sc = scene ?: return
        if (sc.size.w <= 0 || sc.size.h <= 0) return
        // Uniform scale to fit width; content stays top-aligned.
        val scale = (width / sc.size.w).toFloat()
        val save = canvas.save()
        canvas.scale(scale, scale)
        renderer.draw(sc, canvas)
        canvas.restoreToCount(save)
    }
}
