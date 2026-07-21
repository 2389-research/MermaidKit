import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// A filled arrowhead at `tip`, oriented along the final segment from
    /// `origin` — the platform-free twin of `DiagramRenderer.drawFilledArrowhead`
    /// (MermaidRender/DiagramRenderer+GraphShared.swift). ONE opaque triangle in
    /// `color`: an opaque head needs no seam-eraser, and the earlier canvas-colored
    /// eraser triangle read as a wedge wherever the head crossed a group tint
    /// (canvas ≠ tint). See issue #23. Used by the box families (C4, architecture,
    /// block); callers pass an opaque `color`.
    static func filledArrowheadElements(
        at tip: CGPoint, from origin: CGPoint, color: DiagramColor
    ) -> [Element] {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let length: CGFloat = 8.5, spread: CGFloat = 0.40
        let tri: [CGPoint] = [
            tip,
            CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)),
            CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)),
        ]
        return [.shape(Shape(path: .polygon(tri), fill: color.withAlpha(1), stroke: nil))]
    }

    /// Lowers a `C4Layout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: C4Layout, …)`
    /// (MermaidRender/DiagramRenderer+C4.swift). It emits, in the same painter's
    /// order: the centered diagram title, relationship shafts with filled
    /// arrowheads, categorically-tinted element boxes (dashed border + 6%-fill
    /// for externals, a straddling "head" disc for people) carrying stacked
    /// stereotype / bold-title / detail text, and edge labels on canvas chips.
    /// Any change to the drawn C4 appearance must land in both.
    public static func from(_ layout: C4Layout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        _ = measure
        var elements: [Element] = []

        // 1. Centered diagram title (drawDiagramTitle: 12.5pt semibold ink).
        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // 2. Relationship shafts (50%-ink), each with a 60%-ink arrowhead. The
        //    head is separate geometry so the shaft carries no arrow flag.
        for edge in layout.edges {
            let pts = edge.points
            guard pts.count >= 2 else { continue }
            elements.append(.polyline(Polyline(
                points: pts, stroke: Stroke(color: theme.ink.withAlpha(0.5), width: 1))))
            elements += filledArrowheadElements(
                at: pts[pts.count - 1], from: pts[pts.count - 2], color: theme.ink)
        }

        // 3. Element boxes: tinted rounded rects (external = dashed border +
        //    lighter fill), a person's head disc, then stacked text.
        for box in layout.boxes {
            let tint = theme.categoricalColor(box.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(box.frame, radius: 6),
                fill: tint.withAlpha(box.external ? 0.06 : 0.14),
                stroke: Stroke(color: tint.withAlpha(box.external ? 0.45 : 0.65),
                               width: 1, dashed: box.external))))

            if box.isPerson {
                let headR: CGFloat = 7
                elements.append(.shape(Shape(
                    path: .ellipse(CGRect(x: box.frame.midX - headR, y: box.frame.minY - headR - 1,
                                          width: headR * 2, height: headR * 2)),
                    fill: tint.withAlpha(0.85), stroke: nil)))
            }

            let midX = box.frame.midX
            var y = box.frame.minY + 10                       // top padding
            elements.append(.text(Text(
                string: box.stereotype, center: CGPoint(x: midX, y: y + 6.5),
                fontSize: 9.5, color: theme.secondaryText)))
            y += 13 + 3                                        // stereoH + titleGap
            for line in box.titleLines {
                elements.append(.text(Text(
                    string: line, center: CGPoint(x: midX, y: y + 8),
                    fontSize: 12, weight: .semibold, color: theme.ink)))
                y += 16
            }
            if !box.detailLines.isEmpty {
                y += 4
                for line in box.detailLines {
                    elements.append(.text(Text(
                        string: line, center: CGPoint(x: midX, y: y + 6.5),
                        fontSize: 10, color: theme.secondaryText)))
                    y += 13
                }
            }
        }

        // 4. Edge labels on top, each on a canvas chip in a clear channel band.
        for edge in layout.edges {
            guard let label = edge.label, !label.isEmpty else { continue }
            elements.append(.text(Text(
                string: label, center: edge.labelPoint,
                fontSize: 10.5, color: theme.secondaryText, backing: theme.canvas)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
