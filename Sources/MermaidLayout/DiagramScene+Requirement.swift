import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a requirement layout to the common scene IR: requirement and
    /// element blocks are plain nodes, relationships are orthogonal edges,
    /// and each verb becomes a free-standing Label at the route's arc-length
    /// midpoint, clamped on-canvas.
    static func from(_ layout: RequirementLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // Each requirement / element block is a visible box (stereotype + name +
        // detail rows). A box does not *contain* other diagram nodes, so it is a
        // plain node subject to overlap and occlusion checks.
        let nodes = layout.boxes.map { box in
            Node(id: box.name, frame: box.frame, isContainer: false)
        }

        // Each relationship is an orthogonal connector routed through the empty
        // channels between boxes. The verb (satisfies / traces / …) rides the
        // edge as its label.
        let edges = layout.edges.map { edge -> Edge in
            Edge(
                polyline: edge.points,
                label: edge.label.isEmpty ? nil : edge.label
            )
        }

        // Free-standing relationship labels, placed at the route midpoint (by
        // arc length) so the linter can check them for collisions. Clamped to
        // the canvas so a route near an edge doesn't push the label off-canvas.
        let labels: [Label] = layout.edges.enumerated().compactMap { index, edge in
            guard !edge.label.isEmpty else { return nil }
            let mid = polylineMidpoint(edge.points)
            let w = measuredLabelSize(measure, edge.label).width
            var x = mid.x - w / 2
            var yTop = mid.y - 7
            x = max(0, min(x, layout.size.width - w))
            yTop = max(0, min(yTop, layout.size.height - 14))
            return Label(text: edge.label, frame: CGRect(x: x, y: yTop, width: w, height: 14),
                         anchorEdge: index, backed: true)
        }

        return DiagramScene(
            name: "requirement",
            size: layout.size,
            nodes: nodes,
            edges: edges,
            labels: labels
        )
    }

}
