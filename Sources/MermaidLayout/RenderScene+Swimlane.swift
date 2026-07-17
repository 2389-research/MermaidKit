import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `SwimlaneLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: SwimlaneLayout, …)`
    /// (MermaidRender/DiagramRenderer+MethodDiagrams.swift). It emits, in the
    /// same painter's order: tinted lane bands (7%-fill, hairline border) with a
    /// bottom-to-top rotated lane title, connectors (75%-secondary, dash-capable)
    /// with matching arrowheads and canvas-chip labels, and flowchart-family
    /// step nodes on top. Any change to the drawn appearance must land in both.
    public static func from(_ layout: SwimlaneLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        _ = measure
        var elements: [Element] = []

        // 1. Lane bands with a rotated (reads bottom-to-top) semibold title.
        for (index, lane) in layout.lanes.enumerated() {
            let tint = theme.categoricalColor(index)
            elements.append(.shape(Shape(
                path: .roundedRect(lane.band, radius: 0),
                fill: tint.withAlpha(0.07), stroke: Stroke(color: theme.hairline, width: 1))))
            if !lane.label.isEmpty {
                elements.append(.text(Text(
                    string: lane.label,
                    center: CGPoint(x: lane.band.minX + 12, y: lane.band.midY),
                    fontSize: 10, weight: .semibold, color: theme.secondaryText,
                    rotation: -.pi / 2)))
            }
        }

        // 2. Connectors: 75%-secondary shafts (dashed when marked) whose
        //    same-colored arrowhead the endArrow flag realizes, then a label
        //    on a canvas chip where the layout parked it.
        let edgeColor = theme.secondaryText.withAlpha(0.75)
        for edge in layout.edges where edge.points.count >= 2 {
            elements.append(.polyline(Polyline(
                points: edge.points, stroke: Stroke(color: edgeColor, width: 1.2, dashed: edge.dashed),
                endArrow: true)))
            if let label = edge.label, !label.isEmpty, let at = edge.labelCenter {
                elements.append(.text(Text(
                    string: label, center: at,
                    fontSize: 10.5, color: theme.secondaryText, backing: theme.canvas)))
            }
        }

        // 3. Step nodes: the flowchart-family shape subset, then a centered label.
        for node in layout.nodes {
            let fill = theme.accent.withAlpha(0.10)
            let stroke = Stroke(color: theme.ink.withAlpha(0.75), width: 1.2)
            let f = node.frame
            let path: ShapePath
            switch node.shape {
            case .diamond:
                path = .polygon([
                    CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.midY),
                    CGPoint(x: f.midX, y: f.maxY), CGPoint(x: f.minX, y: f.midY),
                ])
            case .circle:
                path = .ellipse(f)
            case .stadium:
                path = .roundedRect(f, radius: f.height / 2)
            case .rounded:
                path = .roundedRect(f, radius: 8)
            default:
                path = .roundedRect(f, radius: 3)
            }
            elements.append(.shape(Shape(path: path, fill: fill, stroke: stroke)))
            elements.append(.text(Text(
                string: node.label, center: CGPoint(x: f.midX, y: f.midY),
                fontSize: 12, color: theme.ink)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
