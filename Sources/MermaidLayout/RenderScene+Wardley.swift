import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `WardleyLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: WardleyLayout, …)`
    /// (MermaidRender/DiagramRenderer+NewTypes.swift). It emits, in the same
    /// painter's order: an optional title, the plot frame + dashed evolution-band
    /// dividers + band names, the rotated "Value Chain" y-axis label, dependency
    /// links under the dots, dashed evolve arrows with a hollow target dot, then
    /// component dots (a filled accent dot, or a hollow ring for an anchor), an
    /// optional inertia bar, a chipped label per node, and any notes.
    ///
    /// Links and axis chrome are straight segments; nothing is curved or
    /// gradient-filled, so no geometry or color is approximated. Node/note labels
    /// draw an explicit canvas-at-88% chip rect under a plain run — matching the
    /// CG `fill(labelFrame.insetBy(…))` exactly rather than the heuristic-sized
    /// `backing` chip. Any change to the drawn wardley appearance must land in
    /// both.
    public static func from(_ layout: WardleyLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 16),
                fontSize: 13, weight: .semibold, color: theme.ink)))
        }

        // Plot frame + evolution band boundaries.
        elements.append(.shape(Shape(
            path: .roundedRect(layout.plotFrame, radius: 0), fill: nil,
            stroke: Stroke(color: theme.hairline, width: 1))))
        for band in layout.bands.dropFirst() {
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: band.x, y: layout.plotFrame.minY),
                         CGPoint(x: band.x, y: layout.plotFrame.maxY)],
                stroke: Stroke(color: theme.hairline, width: 1, dashed: true))))
        }
        for band in layout.bands {
            elements.append(.text(leftText(
                band.name, at: CGPoint(x: band.x + 4, y: layout.plotFrame.maxY + 10),
                fontSize: 9, color: theme.tertiaryText, measure: measure)))
        }
        // Y axis: value chain, rotated bottom-to-top.
        elements.append(.text(Text(
            string: "Value Chain",
            center: CGPoint(x: layout.plotFrame.minX - 12, y: layout.plotFrame.midY),
            fontSize: 9, color: theme.tertiaryText, rotation: -.pi / 2)))

        // Links under dots.
        for link in layout.links {
            elements.append(.polyline(Polyline(
                points: [link.from, link.to],
                stroke: Stroke(color: link.isFlow ? theme.accent
                                                   : theme.secondaryText.withAlpha(0.55),
                               width: link.isFlow ? 2 : 1))))
        }
        // Evolve arrows: dashed accent + hollow target dot.
        for evolve in layout.evolves {
            elements.append(.polyline(Polyline(
                points: [evolve.from, evolve.to],
                stroke: Stroke(color: theme.accent, width: 1.4, dashed: true), endArrow: true)))
            elements.append(.shape(Shape(
                path: .ellipse(CGRect(x: evolve.to.x - 4, y: evolve.to.y - 4, width: 8, height: 8)),
                fill: theme.canvas, stroke: Stroke(color: theme.accent, width: 1))))
        }
        // Component dots + labels.
        for node in layout.nodes {
            let dot = CGRect(x: node.center.x - 5, y: node.center.y - 5, width: 10, height: 10)
            if node.isAnchor {
                elements.append(.shape(Shape(
                    path: .ellipse(dot), fill: theme.canvas,
                    stroke: Stroke(color: theme.ink, width: 1.4))))
            } else {
                elements.append(.shape(Shape(path: .ellipse(dot), fill: theme.accent, stroke: nil)))
            }
            if node.inertia {
                elements.append(.polyline(Polyline(
                    points: [CGPoint(x: node.center.x + 9, y: node.center.y - 7),
                             CGPoint(x: node.center.x + 9, y: node.center.y + 7)],
                    stroke: Stroke(color: theme.ink, width: 3))))
            }
            let text = node.decorator.map { "\(node.name) (\($0))" } ?? node.name
            let nameWidth = measure(node.name, 10.5).width
            elements.append(.shape(Shape(
                path: .roundedRect(node.labelFrame.insetBy(dx: -2, dy: -1), radius: 0),
                fill: theme.canvas.withAlpha(0.88), stroke: nil)))
            elements.append(.text(Text(
                string: text,
                center: CGPoint(x: node.labelFrame.minX + nameWidth / 2, y: node.labelFrame.midY),
                fontSize: 10.5, weight: node.isAnchor ? .semibold : .regular, color: theme.ink)))
        }
        for note in layout.notes {
            elements.append(.text(Text(
                string: note.text, center: note.center, fontSize: 9,
                color: theme.tertiaryText, backing: theme.canvas.withAlpha(0.88))))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
