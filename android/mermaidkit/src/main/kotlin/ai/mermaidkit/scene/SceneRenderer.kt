package ai.mermaidkit.scene

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * Draws a [SceneWire] onto an Android [Canvas] with [Paint] — the Kotlin twin of
 * Swift's `DiagramRenderer`, but driven entirely by the platform-free scene, so
 * it never needs to know what a "sequence diagram" or "treemap" is. It paints
 * primitives in painter's order, exactly like the SVG backend.
 *
 * The scene's coordinates are points in a top-left-origin space; the caller sets
 * up any scale/translation on the [Canvas] before calling [draw] (e.g. to map
 * `scene.size` into the view bounds at the right density).
 *
 * Fidelity notes:
 * - Colors are `#RRGGBBAA` strings; [parseColor] reorders them to Android ARGB.
 * - Text is measured with the *same* [Paint] that draws it — the measure seam the
 *   C ABI's callback is pinned to (Vinculum's #62 lesson), so on-device layout and
 *   draw agree.
 */
class SceneRenderer {

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)

    /** Paint [scene] onto [canvas]. */
    fun draw(scene: SceneWire, canvas: Canvas) {
        canvas.drawColor(parseColor(scene.background))
        for (element in scene.elements) {
            when (element) {
                is Element.Shape -> drawShape(element, canvas)
                is Element.Polyline -> drawPolyline(element, canvas)
                is Element.Text -> drawText(element, canvas)
            }
        }
    }

    // MARK: - Shapes

    private fun drawShape(shape: Element.Shape, canvas: Canvas) {
        val path = buildPath(shape.path)
        shape.fill?.let {
            fill.color = parseColor(it)
            canvas.drawPath(path, fill)
        }
        shape.stroke?.let { applyStroke(it); canvas.drawPath(path, stroke) }
    }

    private fun buildPath(shape: ShapePath): Path {
        val path = Path()
        when (shape) {
            is ShapePath.RoundedRect ->
                path.addRoundRect(rectF(shape.rect), shape.radius.toFloat(),
                    shape.radius.toFloat(), Path.Direction.CW)
            is ShapePath.Ellipse ->
                path.addOval(rectF(shape.rect), Path.Direction.CW)
            is ShapePath.Polygon -> addPolygon(path, shape.points)
            is ShapePath.Path -> addVerbs(path, shape.verbs)
        }
        return path
    }

    private fun addPolygon(path: Path, points: List<Point>) {
        if (points.isEmpty()) return
        path.moveTo(points[0].x.toFloat(), points[0].y.toFloat())
        for (i in 1 until points.size) path.lineTo(points[i].x.toFloat(), points[i].y.toFloat())
        path.close()
    }

    private fun addVerbs(path: Path, verbs: List<PathVerb>) {
        for (verb in verbs) when (verb) {
            is PathVerb.Move -> path.moveTo(verb.point.x.toFloat(), verb.point.y.toFloat())
            is PathVerb.Line -> path.lineTo(verb.point.x.toFloat(), verb.point.y.toFloat())
            is PathVerb.Quad -> path.quadTo(
                verb.control.x.toFloat(), verb.control.y.toFloat(),
                verb.to.x.toFloat(), verb.to.y.toFloat())
            is PathVerb.Close -> path.close()
        }
    }

    // MARK: - Polylines (edge routes + arrowheads)

    private fun drawPolyline(line: Element.Polyline, canvas: Canvas) {
        val points = line.points
        if (points.size < 2) return
        applyStroke(line.stroke)
        val path = Path().apply {
            moveTo(points[0].x.toFloat(), points[0].y.toFloat())
            for (i in 1 until points.size) lineTo(points[i].x.toFloat(), points[i].y.toFloat())
        }
        canvas.drawPath(path, stroke)

        // Arrowheads are realized from the segment direction at each armed end —
        // the scene keeps the geometry a single point list (see SceneWire.Polyline).
        val ink = parseColor(line.stroke.color)
        if (line.endArrow) drawArrowhead(canvas, points[points.size - 2], points[points.size - 1], ink)
        if (line.startArrow) drawArrowhead(canvas, points[1], points[0], ink)
    }

    /** A filled triangular head at [tip], pointing along [from]→[tip]. */
    private fun drawArrowhead(canvas: Canvas, from: Point, tip: Point, color: Int) {
        val angle = atan2(tip.y - from.y, tip.x - from.x)
        val len = 8.0
        val spread = Math.toRadians(22.0)
        val head = Path().apply {
            moveTo(tip.x.toFloat(), tip.y.toFloat())
            lineTo((tip.x - len * cos(angle - spread)).toFloat(),
                (tip.y - len * sin(angle - spread)).toFloat())
            lineTo((tip.x - len * cos(angle + spread)).toFloat(),
                (tip.y - len * sin(angle + spread)).toFloat())
            close()
        }
        fill.color = color
        canvas.drawPath(head, fill)
    }

    // MARK: - Text

    private fun drawText(text: Element.Text, canvas: Canvas) {
        textPaint.textSize = text.fontSize.toFloat()
        textPaint.typeface = typefaceFor(text.weight)
        textPaint.textAlign = Paint.Align.CENTER
        val cx = text.center.x.toFloat()
        val cy = text.center.y.toFloat()

        // Vertical centering: baseline offset from the font metrics midpoint.
        val fm = textPaint.fontMetrics
        val baseline = cy - (fm.ascent + fm.descent) / 2f

        canvas.save()
        if (text.rotation != 0.0) {
            canvas.rotate(Math.toDegrees(text.rotation).toFloat(), cx, cy)
        }
        // A backing chip keeps a routed line from showing through an edge label.
        text.backing?.let {
            val half = textPaint.measureText(text.string) / 2f + 2f
            val h = (fm.descent - fm.ascent) / 2f + 1f
            fill.color = parseColor(it)
            canvas.drawRect(cx - half, cy - h, cx + half, cy + h, fill)
        }
        textPaint.color = parseColor(text.color)
        canvas.drawText(text.string, cx, baseline, textPaint)
        canvas.restore()
    }

    private fun typefaceFor(weight: String): Typeface = when (weight) {
        "medium" -> mediumTypeface
        "semibold" -> semiboldTypeface
        else -> Typeface.DEFAULT
    }

    // MARK: - Helpers

    private fun applyStroke(s: Stroke) {
        stroke.color = parseColor(s.color)
        stroke.strokeWidth = s.width.toFloat()
        stroke.pathEffect = if (s.dashed) dashEffect else null
    }

    private fun rectF(r: Rect) =
        RectF(r.x.toFloat(), r.y.toFloat(), (r.x + r.w).toFloat(), (r.y + r.h).toFloat())

    companion object {
        private val dashEffect = android.graphics.DashPathEffect(floatArrayOf(4f, 3f), 0f)
        // Weight 500/600 need API 28+ (Typeface.create(base, weight, italic)); a
        // BOLD fallback keeps older devices legible without crashing.
        private val mediumTypeface: Typeface =
            if (android.os.Build.VERSION.SDK_INT >= 28)
                Typeface.create(Typeface.DEFAULT, 500, false)
            else Typeface.DEFAULT_BOLD
        private val semiboldTypeface: Typeface =
            if (android.os.Build.VERSION.SDK_INT >= 28)
                Typeface.create(Typeface.DEFAULT, 600, false)
            else Typeface.DEFAULT_BOLD

        /**
         * Parse a `#RRGGBBAA` (or `#RRGGBB`) wire color into an Android ARGB int.
         * Android's [Color.parseColor] expects `#AARRGGBB`, so we reorder rather
         * than call it.
         */
        fun parseColor(hex: String): Int {
            val s = if (hex.startsWith("#")) hex.substring(1) else hex
            val r = s.substring(0, 2).toInt(16)
            val g = s.substring(2, 4).toInt(16)
            val b = s.substring(4, 6).toInt(16)
            val a = if (s.length >= 8) s.substring(6, 8).toInt(16) else 255
            return Color.argb(a, r, g, b)
        }
    }
}
