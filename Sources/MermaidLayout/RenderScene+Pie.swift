import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `PieLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: PieLayout, …)`
    /// (MermaidRender/DiagramRenderer+Pie.swift). It emits, in the same
    /// painter's order: an optional title, filled wedges in each slice's
    /// categorical color, one canvas-colored separator per slice boundary, then
    /// a value-chip legend stacked below-right of the disk.
    ///
    /// The CG wedge is a `move → line-to-rim → addArc → close` fan; `ShapePath`
    /// carries no arc verb, so the rim sweep is approximated by `.quad`
    /// segments (≤22.5° each, `arcQuads`) — a faithful match for a filled pie
    /// slice at this radius. Fills are flat categorical colors (no gradient), so
    /// no color is approximated. The separators are butt-capped polylines where
    /// CG used a round cap; the difference is a sub-pixel nub at the hub. Any
    /// change to the drawn pie appearance must land in both.
    public static func from(_ layout: PieLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title,
                center: CGPoint(x: layout.center.x, y: layout.center.y - layout.radius - 16),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // Filled wedges, no per-wedge stroke (boundaries are drawn once, below).
        for slice in layout.slices {
            let rimStart = CGPoint(
                x: layout.center.x + layout.radius * cos(CGFloat(slice.startAngle)),
                y: layout.center.y + layout.radius * sin(CGFloat(slice.startAngle)))
            var verbs: [PathVerb] = [.move(layout.center), .line(rimStart)]
            verbs += arcQuads(center: layout.center, radius: layout.radius,
                              start: CGFloat(slice.startAngle), end: CGFloat(slice.endAngle))
            verbs.append(.close)
            elements.append(.shape(Shape(
                path: .path(verbs),
                fill: theme.categoricalColor(slice.colorIndex), stroke: nil)))
        }

        // One canvas-colored separator per boundary, from the hub to the rim.
        for slice in layout.slices {
            let rim = CGPoint(
                x: layout.center.x + layout.radius * cos(CGFloat(slice.startAngle)),
                y: layout.center.y + layout.radius * sin(CGFloat(slice.startAngle)))
            elements.append(.polyline(Polyline(
                points: [layout.center, rim],
                stroke: Stroke(color: theme.canvas, width: 2))))
        }

        // Legend: value chips vertically stacked.
        var y = layout.legendOrigin.y
        for slice in layout.slices {
            let swatch = CGRect(x: layout.legendOrigin.x, y: y + 4, width: 10, height: 10)
            elements.append(.shape(Shape(
                path: .roundedRect(swatch, radius: 2),
                fill: theme.categoricalColor(slice.colorIndex), stroke: nil)))

            let percent = Int((slice.fraction * 100).rounded())
            let label = "\(slice.label) (\(percent)%)"
            let size = measure(label, 10.5)
            elements.append(.text(Text(
                string: label,
                center: CGPoint(x: swatch.maxX + 6 + size.width / 2, y: swatch.midY),
                fontSize: 10.5, color: theme.secondaryText)))
            y += 20
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Approximates the circular arc from `start` to `end` (radians, about
    /// `center`) as a chain of `.quad` verbs — the caller has already emitted a
    /// `.move`/`.line` onto the `start` rim point. Each segment spans ≤22.5°; a
    /// segment of half-angle θ uses the tangent-intersection control point at
    /// radius `radius / cos(θ)`, the standard least-error quadratic for a small
    /// circular arc.
    static func arcQuads(center: CGPoint, radius: CGFloat,
                         start: CGFloat, end: CGFloat) -> [PathVerb] {
        let sweep = end - start
        let steps = max(1, Int((abs(sweep) / (.pi / 8)).rounded(.up)))
        let dt = sweep / CGFloat(steps)
        func rim(_ a: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
        var verbs: [PathVerb] = []
        for i in 0..<steps {
            let a0 = start + dt * CGFloat(i)
            let a1 = start + dt * CGFloat(i + 1)
            let am = (a0 + a1) / 2
            let ctrlR = radius / cos((a1 - a0) / 2)
            let ctrl = CGPoint(x: center.x + ctrlR * cos(am), y: center.y + ctrlR * sin(am))
            verbs.append(.quad(to: rim(a1), control: ctrl))
        }
        return verbs
    }
}
