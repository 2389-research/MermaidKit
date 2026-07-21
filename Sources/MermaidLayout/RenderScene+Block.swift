import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `BlockLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: BlockLayout, …)`
    /// (MermaidRender/DiagramRenderer+Block.swift). It emits categorically-
    /// tinted blocks (rect / rounded / inscribed-circle; `space` cells are
    /// skipped) with centered labels, then hairline orthogonal shafts (55%-ink)
    /// with 70%-ink arrowheads, and edge labels last on canvas chips. Any change
    /// to the drawn block appearance must land in both.
    public static func from(_ layout: BlockLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        _ = measure
        var elements: [Element] = []

        // 1. Blocks: subtle categorical tint per row, hairline border, ink label.
        for node in layout.nodes where node.shape != .space {
            let tint = theme.categoricalColor(node.colorIndex)
            let fill = tint.withAlpha(theme.prefersDark ? 0.22 : 0.13)
            let stroke = tint.withAlpha(0.6)

            switch node.shape {
            case .circle:
                // Inscribed circle: fill the full disc, then stroke it inset 0.5.
                let diameter = min(node.frame.width, node.frame.height)
                let r = CGRect(x: node.frame.midX - diameter / 2, y: node.frame.midY - diameter / 2,
                               width: diameter, height: diameter)
                elements.append(.shape(Shape(path: .ellipse(r), fill: fill, stroke: nil)))
                elements.append(.shape(Shape(
                    path: .ellipse(r.insetBy(dx: 0.5, dy: 0.5)), fill: nil,
                    stroke: Stroke(color: stroke, width: 1))))
            case .rounded:
                elements.append(.shape(Shape(
                    path: .roundedRect(node.frame, radius: min(node.frame.height / 2, 16)),
                    fill: fill, stroke: Stroke(color: stroke, width: 1))))
            case .rectangle, .space:
                elements.append(.shape(Shape(
                    path: .roundedRect(node.frame, radius: 6),
                    fill: fill, stroke: Stroke(color: stroke, width: 1))))
            }

            elements.append(.text(Text(
                string: node.label, center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                fontSize: 12, weight: .medium, color: theme.ink)))
        }

        // 2. Edges: hairline orthogonal shafts with filled arrowheads.
        let shaftColor = theme.ink.withAlpha(0.55)
        for edge in layout.edges where edge.points.count >= 2 {
            elements.append(.polyline(Polyline(
                points: edge.points, stroke: Stroke(color: shaftColor, width: 1.5))))
            elements += filledArrowheadElements(
                at: edge.points[edge.points.count - 1], from: edge.points[edge.points.count - 2],
                color: theme.ink)
        }

        // 3. Edge labels last so their canvas chip sits over the shafts.
        for edge in layout.edges {
            guard let label = edge.label, !label.isEmpty, edge.points.count >= 2 else { continue }
            elements.append(.text(Text(
                string: label, center: DiagramScene.polylineMidpoint(edge.points),
                fontSize: 10.5, color: theme.secondaryText, backing: theme.canvas)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
