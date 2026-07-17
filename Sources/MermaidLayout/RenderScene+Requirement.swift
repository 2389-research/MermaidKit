import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `RequirementLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: RequirementLayout, …)`
    /// (MermaidRender/DiagramRenderer+Requirement.swift). It emits, in the same
    /// painter's order: typed relation connectors (42%-ink, same-colored
    /// arrowhead) beneath the boxes, categorically-tinted requirement/element
    /// boxes with a stereotype, a bold name, a hairline separator, and wrapped
    /// detail rows, then the relation labels last on canvas chips. Any change to
    /// the drawn appearance must land in both.
    public static func from(_ layout: RequirementLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // 1. Connectors first, so box fills sit cleanly over any overlap. The
        //    arrowhead matches the shaft color, so endArrow realizes it.
        let edgeColor = theme.ink.withAlpha(0.42)
        for edge in layout.edges where edge.points.count >= 2 {
            elements.append(.polyline(Polyline(
                points: edge.points, stroke: Stroke(color: edgeColor, width: 1),
                endArrow: true)))
        }

        let padding: CGFloat = 11
        let stereoH: CGFloat = 14
        let nameH: CGFloat = 20
        let sepGap: CGFloat = 8
        let lineH: CGFloat = 15

        // 2. Requirement / element boxes.
        for box in layout.boxes {
            let tint = theme.categoricalColor(box.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(box.frame, radius: 6),
                fill: tint.withAlpha(box.isElement ? 0.10 : 0.14),
                stroke: Stroke(color: tint.withAlpha(0.6), width: 1))))

            let top = box.frame.minY + padding
            elements.append(.text(Text(
                string: box.stereotype,
                center: CGPoint(x: box.frame.midX, y: top + stereoH / 2),
                fontSize: 9.5, color: theme.secondaryText)))
            elements.append(.text(Text(
                string: box.name,
                center: CGPoint(x: box.frame.midX, y: top + stereoH + nameH / 2),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))

            let sepY = top + stereoH + nameH + sepGap / 2
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: box.frame.minX + padding, y: sepY),
                         CGPoint(x: box.frame.maxX - padding, y: sepY)],
                stroke: Stroke(color: theme.hairline, width: 1))))

            var lineY = top + stereoH + nameH + sepGap + lineH / 2
            let textX = box.frame.minX + padding
            for line in box.detailLines {
                // Left-anchored: shift a centered scene Text by half its width.
                let w = measure(line, 10.5).width
                elements.append(.text(Text(
                    string: line, center: CGPoint(x: textX + w / 2, y: lineY),
                    fontSize: 10.5, color: theme.secondaryText)))
                lineY += lineH
            }
        }

        // 3. Relation labels last, on top of every connector and box.
        for edge in layout.edges {
            guard !edge.label.isEmpty, edge.points.count >= 2 else { continue }
            elements.append(.text(Text(
                string: edge.label, center: DiagramScene.polylineMidpoint(edge.points),
                fontSize: 10.5, color: theme.secondaryText, backing: theme.canvas)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
