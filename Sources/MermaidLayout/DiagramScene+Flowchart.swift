import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a flowchart layout to the common scene IR: subgraph boxes are
    /// containers (exempt from overlap/occlusion — they legitimately hold their
    /// members), every placed box is a plain node, connectors keep their
    /// orthogonal routes, and each |label| becomes a free-standing Label at the
    /// layout's labelPoint (endpoint midpoint fallback).
    static func from(_ layout: FlowchartLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // Container boxes first so they read as backdrops; then the content
        // nodes. A subgraph's header label lowers as a free-standing label so
        // the linter checks nothing runs through it.
        var nodes: [Node] = layout.containers.map { container in
            Node(id: container.label.isEmpty ? container.id : container.label,
                 frame: container.frame, isContainer: true)
        }
        nodes.append(contentsOf: layout.nodes.map { node in
            Node(id: node.id, frame: node.frame, isContainer: false)
        })
        var labels: [Label] = layout.edges.enumerated().compactMap { index, edge -> Label? in
            guard let text = edge.label, !text.isEmpty else { return nil }
            let center = edge.labelPoint ?? CGPoint(
                x: (edge.start.x + edge.end.x) / 2,
                y: (edge.start.y + edge.end.y) / 2
            )
            let width = measuredLabelSize(measure, text).width
            return Label(
                text: text,
                frame: CGRect(x: center.x - width / 2, y: center.y - 7,
                              width: width, height: 14),
                anchorEdge: index, backed: true
            )
        }
        // Group header labels: centered in the box's header strip (matching the
        // renderer). Backed, so a member edge routed near the header downgrades
        // to a warning rather than reading as a cut.
        for container in layout.containers where !container.label.isEmpty {
            let width = measuredLabelSize(measure, container.label).width
            labels.append(Label(
                text: container.label,
                frame: CGRect(x: container.frame.midX - width / 2,
                              y: container.frame.minY + 4, width: width, height: 13),
                backed: true))
        }
        return DiagramScene(
            name: "flowchart",
            size: layout.size,
            nodes: nodes,
            edges: layout.edges.map { edge in
                Edge(polyline: edge.points, label: edge.label)
            },
            labels: labels
        )
    }
}
