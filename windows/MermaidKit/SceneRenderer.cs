using SkiaSharp;

namespace MermaidKit;

/// Draws a <see cref="SceneWire"/> onto a SkiaSharp <see cref="SKCanvas"/> — the
/// .NET twin of the Android Kotlin renderer, and (because both are Skia) a
/// fidelity match for it. Driven entirely by the platform-free scene, so it
/// never needs to know what a "sequence diagram" is; it paints primitives in
/// painter's order, exactly like the SVG backend.
///
/// Coordinates are points in a top-left-origin space; the caller sets any
/// scale/translation on the canvas before calling <see cref="Draw"/>. Colors are
/// <c>#RRGGBBAA</c> strings. Text is measured with the same paint that draws it,
/// so on-device layout (via the native measure seam) and draw agree.
public sealed class SceneRenderer
{
    /// Paint <paramref name="scene"/> onto <paramref name="canvas"/>.
    public void Draw(SceneWire scene, SKCanvas canvas)
    {
        canvas.Clear(ParseColor(scene.background));
        foreach (var element in scene.elements)
        {
            switch (element)
            {
                case ShapeElement s: DrawShape(s, canvas); break;
                case PolylineElement p: DrawPolyline(p, canvas); break;
                case TextElement t: DrawText(t, canvas); break;
            }
        }
    }

    // MARK: - Shapes

    private static void DrawShape(ShapeElement shape, SKCanvas canvas)
    {
        using var path = BuildPath(shape.path);
        if (shape.fill is { } fill)
        {
            using var p = new SKPaint { Style = SKPaintStyle.Fill, IsAntialias = true, Color = ParseColor(fill) };
            canvas.DrawPath(path, p);
        }
        if (shape.stroke is { } stroke)
        {
            using var p = StrokePaint(stroke);
            canvas.DrawPath(path, p);
        }
    }

    private static SKPath BuildPath(ShapePath shape)
    {
        var path = new SKPath();
        switch (shape)
        {
            case RoundedRect r:
                path.AddRoundRect(ToRect(r.rect), (float)r.radius, (float)r.radius);
                break;
            case Ellipse e:
                path.AddOval(ToRect(e.rect));
                break;
            case Polygon poly:
                AddPolygon(path, poly.points);
                break;
            case PathShape ps:
                AddVerbs(path, ps.verbs);
                break;
        }
        return path;
    }

    private static void AddPolygon(SKPath path, IReadOnlyList<Point> pts)
    {
        if (pts.Count == 0) return;
        path.MoveTo((float)pts[0].x, (float)pts[0].y);
        for (int i = 1; i < pts.Count; i++) path.LineTo((float)pts[i].x, (float)pts[i].y);
        path.Close();
    }

    private static void AddVerbs(SKPath path, IReadOnlyList<PathVerb> verbs)
    {
        foreach (var v in verbs)
        {
            switch (v)
            {
                case MoveVerb m: path.MoveTo((float)m.point.x, (float)m.point.y); break;
                case LineVerb l: path.LineTo((float)l.point.x, (float)l.point.y); break;
                case QuadVerb q:
                    path.QuadTo((float)q.control.x, (float)q.control.y, (float)q.to.x, (float)q.to.y);
                    break;
                case CloseVerb: path.Close(); break;
            }
        }
    }

    // MARK: - Polylines (edge routes + arrowheads)

    private static void DrawPolyline(PolylineElement line, SKCanvas canvas)
    {
        var pts = line.points;
        if (pts.Count < 2) return;
        using var stroke = StrokePaint(line.stroke);
        using var path = new SKPath();
        path.MoveTo((float)pts[0].x, (float)pts[0].y);
        for (int i = 1; i < pts.Count; i++) path.LineTo((float)pts[i].x, (float)pts[i].y);
        canvas.DrawPath(path, stroke);

        var ink = ParseColor(line.stroke.color);
        if (line.endArrow) DrawArrowhead(canvas, pts[^2], pts[^1], ink);
        if (line.startArrow) DrawArrowhead(canvas, pts[1], pts[0], ink);
    }

    private static void DrawArrowhead(SKCanvas canvas, Point from, Point tip, SKColor color)
    {
        double angle = Math.Atan2(tip.y - from.y, tip.x - from.x);
        const double len = 8, spread = 22 * Math.PI / 180;
        using var path = new SKPath();
        path.MoveTo((float)tip.x, (float)tip.y);
        path.LineTo((float)(tip.x - len * Math.Cos(angle - spread)), (float)(tip.y - len * Math.Sin(angle - spread)));
        path.LineTo((float)(tip.x - len * Math.Cos(angle + spread)), (float)(tip.y - len * Math.Sin(angle + spread)));
        path.Close();
        using var p = new SKPaint { Style = SKPaintStyle.Fill, IsAntialias = true, Color = color };
        canvas.DrawPath(path, p);
    }

    // MARK: - Text

    private static void DrawText(TextElement text, SKCanvas canvas)
    {
        using var paint = new SKPaint
        {
            IsAntialias = true,
            SubpixelText = true,
            Color = ParseColor(text.color),
            TextSize = (float)text.fontSize,
            TextAlign = SKTextAlign.Center,
            Typeface = TypefaceFor(text.weight),
        };
        float cx = (float)text.center.x, cy = (float)text.center.y;
        var fm = paint.FontMetrics;
        float baseline = cy - (fm.Ascent + fm.Descent) / 2f;

        int save = canvas.Save();
        if (text.rotation != 0)
            canvas.RotateDegrees((float)(text.rotation * 180 / Math.PI), cx, cy);

        if (text.backing is { } backing)
        {
            float half = paint.MeasureText(text.@string) / 2f + 2f;
            float h = (fm.Descent - fm.Ascent) / 2f + 1f;
            using var chip = new SKPaint { Style = SKPaintStyle.Fill, IsAntialias = true, Color = ParseColor(backing) };
            canvas.DrawRect(cx - half, cy - h, half * 2, h * 2, chip);
        }
        canvas.DrawText(text.@string, cx, baseline, paint);
        canvas.RestoreToCount(save);
    }

    private static SKTypeface TypefaceFor(string weight) => weight switch
    {
        "medium" => SKTypeface.FromFamilyName(null, SKFontStyleWeight.Medium, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright),
        "semibold" => SKTypeface.FromFamilyName(null, SKFontStyleWeight.SemiBold, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright),
        _ => SKTypeface.Default,
    };

    // MARK: - Helpers

    private static SKPaint StrokePaint(Stroke s)
    {
        var p = new SKPaint
        {
            Style = SKPaintStyle.Stroke,
            IsAntialias = true,
            Color = ParseColor(s.color),
            StrokeWidth = (float)s.width,
        };
        if (s.dashed) p.PathEffect = SKPathEffect.CreateDash(new[] { 4f, 3f }, 0);
        return p;
    }

    private static SKRect ToRect(Rect r) =>
        new((float)r.x, (float)r.y, (float)(r.x + r.w), (float)(r.y + r.h));

    /// Parse a <c>#RRGGBBAA</c> (or <c>#RRGGBB</c>) wire color into an SKColor.
    public static SKColor ParseColor(string hex)
    {
        var s = hex.StartsWith('#') ? hex[1..] : hex;
        byte r = Convert.ToByte(s.Substring(0, 2), 16);
        byte g = Convert.ToByte(s.Substring(2, 2), 16);
        byte b = Convert.ToByte(s.Substring(4, 2), 16);
        byte a = s.Length >= 8 ? Convert.ToByte(s.Substring(6, 2), 16) : (byte)255;
        return new SKColor(r, g, b, a);
    }
}
