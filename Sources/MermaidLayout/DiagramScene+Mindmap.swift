import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a laid-out mindmap into the common scene IR. Every node is a real
    /// box (labels can repeat across branches, so the scene id disambiguates
    /// with the node's index). Parent→child links become two-point polylines
    /// from the parent's right-center to the child's left-center. A mindmap has
    /// no free-standing edge labels and no group containers, so `labels` is
    /// empty and nothing is marked `isContainer`.
    static func from(_ layout: MindmapLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        DiagramScene(
            name: "mindmap",
            size: layout.size,
            nodes: layout.nodes.enumerated().map { index, node in
                Node(id: "\(node.label)#\(index)", frame: node.frame)
            },
            edges: layout.edges.map { edge in
                Edge(polyline: [edge.from, edge.to])
            },
            labels: []
        )
    }
}
