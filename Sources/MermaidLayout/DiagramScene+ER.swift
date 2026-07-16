import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers an ER layout to the common scene IR: entity boxes are plain
    /// nodes, relationships are orthogonal edges, and each relationship verb
    /// becomes a free-standing Label at the route's arc-length midpoint.
    static func from(_ layout: ERLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // Each entity is a visible box (name compartment + attribute rows). It
        // does not *contain* other diagram nodes, so it is a plain node subject
        // to overlap/occlusion checks.
        let nodes = layout.boxes.map { box in
            Node(id: box.name, frame: box.frame, isContainer: false)
        }

        // Each relationship is an orthogonal route between two entity boxes; the
        // crow's-foot markers live on the first/last segments. The relationship
        // verb rides the edge as its label.
        let edges = layout.edges.map { edge -> Edge in
            Edge(polyline: edge.points, label: edge.label.isEmpty ? nil : edge.label)
        }

        // Free-standing relationship labels, placed at the route midpoint so the
        // linter can check them for collisions with boxes and each other.
        let labels: [Label] = layout.edges.enumerated().compactMap { index, edge in
            guard !edge.label.isEmpty else { return nil }
            let mid = edge.labelAnchor ?? polylineMidpoint(edge.points)
            let w = measuredLabelSize(measure, edge.label).width
            return Label(
                text: edge.label,
                frame: CGRect(x: mid.x - w / 2, y: mid.y - 7, width: w, height: 14),
                anchorEdge: index, backed: true
            )
        }

        return DiagramScene(
            name: "er",
            size: layout.size,
            nodes: nodes,
            edges: edges,
            labels: labels
        )
    }

}