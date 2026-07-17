import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `StateLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: StateLayout, …)`
    /// (MermaidRender/DiagramRenderer+State.swift). It emits the same composite
    /// container boxes (with a title strip + separator), transition shafts with
    /// filled arrowheads, and node glyphs (start dot, ringed end, choice diamond,
    /// fork/join bar, plain state). Any change to the drawn state appearance must
    /// land in both.
    public static func from(_ layout: StateLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        _ = measure
        var elements: [Element] = []

        let stroke = theme.ink.withAlpha(0.35)
        let nodeStroke = Stroke(color: stroke, width: 1)
        let nodeFill = theme.accent.withAlpha(0.06)
        let solid = theme.ink.withAlpha(0.75)

        // 1. Composite containers, outermost → innermost; the title strip carries
        //    the composite's name, and a hairline rules off the children below it.
        for container in layout.containers.sorted(by: { $0.depth < $1.depth }) {
            elements.append(.shape(Shape(
                path: .roundedRect(container.frame, radius: 8),
                fill: theme.ink.withAlpha(0.03), stroke: nodeStroke)))
            if !container.label.isEmpty {
                elements.append(.text(Text(
                    string: container.label,
                    center: CGPoint(x: container.frame.midX,
                                    y: container.frame.minY + container.titleHeight / 2),
                    fontSize: 11.5, weight: .semibold, color: theme.ink)))
            }
            let sepY = container.frame.minY + container.titleHeight
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: container.frame.minX, y: sepY),
                         CGPoint(x: container.frame.maxX, y: sepY)],
                stroke: Stroke(color: theme.ink.withAlpha(0.15), width: 1))))
        }

        // 2. Transition shafts with a filled arrowhead at the target end (the
        //    renderer strokes the full shaft to `end` then paints the head on
        //    top; the scene's endArrow realizes the same head geometry).
        for edge in layout.edges {
            elements.append(.polyline(Polyline(
                points: edge.points, stroke: nodeStroke, endArrow: true)))
        }

        // 3. Transition labels on canvas chips (reserved anchor, else midpoint).
        for edge in layout.edges {
            guard let label = edge.label, !label.isEmpty else { continue }
            let at = edge.labelAnchor ?? DiagramScene.polylineMidpoint(edge.points)
            elements.append(.text(Text(
                string: label, center: at, fontSize: 10.5,
                color: theme.secondaryText, backing: theme.canvas)))
        }

        // 4. Node glyphs on top so their borders sit above the edge ends.
        for node in layout.nodes {
            let f = node.frame
            switch node.kind {
            case .start:
                elements.append(.shape(Shape(path: .ellipse(f), fill: solid, stroke: nil)))
            case .end:
                elements.append(.shape(Shape(
                    path: .ellipse(f.insetBy(dx: 1, dy: 1)),
                    fill: nil, stroke: Stroke(color: solid, width: 1))))
                elements.append(.shape(Shape(
                    path: .ellipse(f.insetBy(dx: 4.5, dy: 4.5)), fill: solid, stroke: nil)))
            case .choice:
                elements.append(.shape(Shape(path: .polygon([
                    CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.midY),
                    CGPoint(x: f.midX, y: f.maxY), CGPoint(x: f.minX, y: f.midY),
                ]), fill: nodeFill, stroke: nodeStroke)))
            case .fork, .join:
                elements.append(.shape(Shape(
                    path: .roundedRect(f, radius: 2),
                    fill: theme.ink.withAlpha(0.7), stroke: nil)))
            case .simple:
                elements.append(.shape(Shape(
                    path: .roundedRect(f, radius: 8), fill: nodeFill, stroke: nodeStroke)))
                if !node.label.isEmpty {
                    elements.append(.text(Text(
                        string: node.label,
                        center: CGPoint(x: f.midX, y: f.midY),
                        fontSize: 12, weight: .medium, color: theme.ink)))
                }
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
