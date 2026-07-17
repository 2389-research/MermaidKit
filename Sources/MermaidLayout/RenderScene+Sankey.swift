import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `SankeyLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: SankeyLayout, …)`
    /// (MermaidRender/DiagramRenderer+Sankey.swift). It emits, in the same
    /// painter's order: flow bands (a filled quad-curve ribbon in the source
    /// node's categorical color), solid tinted node bars, then name labels on
    /// opaque canvas chips.
    ///
    /// The CG ribbon's two long edges are cubic Béziers; `ShapePath` carries no
    /// cubic verb, so each is split at its midpoint into two quadratic segments
    /// (`cubicToQuads`) — a faithful match for these gentle horizontal S-curves.
    /// The fill is a flat color (no gradient), so no color is approximated. Any
    /// change to the drawn sankey appearance must land in both.
    public static func from(_ layout: SankeyLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        _ = measure
        var elements: [Element] = []

        // 1. Flow bands first, so the solid bars and labels sit on top. Bands
        //    take their source node's color; alpha lifts on dark so it reads.
        for link in layout.links {
            let color = theme.categoricalColor(link.colorIndex)
            let cx = (link.sourceTop.x + link.targetTop.x) / 2
            var verbs: [PathVerb] = [.move(link.sourceTop)]
            // Top edge: sourceTop → targetTop (controls straddle the midline x).
            verbs += cubicToQuads(
                link.sourceTop,
                CGPoint(x: cx, y: link.sourceTop.y), CGPoint(x: cx, y: link.targetTop.y),
                link.targetTop)
            verbs.append(.line(link.targetBottom))
            // Bottom edge back: targetBottom → sourceBottom.
            verbs += cubicToQuads(
                link.targetBottom,
                CGPoint(x: cx, y: link.targetBottom.y), CGPoint(x: cx, y: link.sourceBottom.y),
                link.sourceBottom)
            verbs.append(.close)
            elements.append(.shape(Shape(
                path: .path(verbs),
                fill: color.withAlpha(theme.prefersDark ? 0.34 : 0.28), stroke: nil)))
        }

        // 2. Node bars: solid tinted rectangles with a firmer border.
        for node in layout.nodes {
            let color = theme.categoricalColor(node.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(node.rect, radius: 2),
                fill: color.withAlpha(0.9), stroke: Stroke(color: color, width: 1))))
        }

        // 3. Labels on opaque canvas chips so a crossing band never muddies them.
        for node in layout.nodes where !node.label.isEmpty {
            elements.append(.text(Text(
                string: node.label, center: node.labelCenter,
                fontSize: 11, color: theme.ink, backing: theme.canvas)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Splits a cubic Bézier (`p0`→`p3`, controls `c1`,`c2`) at its midpoint
    /// into two quadratic segments, returned as `.quad` verbs (the caller has
    /// already emitted the `.move`/`.line` onto `p0`). De Casteljau at t=0.5
    /// yields the on-curve midpoint; each half's quad control is the least-error
    /// quadratic control of that half-cubic.
    private static func cubicToQuads(
        _ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint
    ) -> [PathVerb] {
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        let p01 = mid(p0, c1), p12 = mid(c1, c2), p23 = mid(c2, p3)
        let p012 = mid(p01, p12), p123 = mid(p12, p23)
        let m = mid(p012, p123)                       // on-curve point at t=0.5
        // Least-error quad control of a cubic = (3(C1+C2) − (P0+P3)) / 4, applied
        // to each half's control polygon.
        func quadControl(_ a: CGPoint, _ b: CGPoint, _ q0: CGPoint, _ q3: CGPoint) -> CGPoint {
            CGPoint(x: (3 * (a.x + b.x) - (q0.x + q3.x)) / 4,
                    y: (3 * (a.y + b.y) - (q0.y + q3.y)) / 4)
        }
        let ctrlL = quadControl(p01, p012, p0, m)
        let ctrlR = quadControl(p123, p23, m, p3)
        return [.quad(to: m, control: ctrlL), .quad(to: p3, control: ctrlR)]
    }
}
