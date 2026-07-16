import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a block diagram to the common scene IR: every cell is a plain
    /// node, edges keep their routes, and each edge caption becomes a
    /// free-standing Label at the route's arc-length midpoint.
    static func from(_ layout: BlockLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        DiagramScene(
            name: "block",
            size: layout.size,
            nodes: layout.nodes.map { node in
                Node(id: node.label, frame: node.frame, isContainer: false)
            },
            edges: layout.edges.map { edge in
                Edge(polyline: edge.points, label: edge.label)
            },
            labels: layout.edges.enumerated().compactMap { index, edge -> Label? in
                guard let text = edge.label, !text.isEmpty,
                      edge.points.count >= 2
                else { return nil }
                // Place the label at the polyline's arc-length midpoint, which
                // sits in a gap channel rather than over a cell. The renderer
                // draws it on a canvas chip via drawEdgeLabel, on its own
                // route — lowering it bare with no anchorEdge guaranteed a
                // false-positive edge-cuts-label on every labeled edge.
                let center = polylineMidpoint(edge.points)
                let width = measuredLabelSize(measure, text).width
                return Label(
                    text: text,
                    frame: CGRect(x: center.x - width / 2, y: center.y - 7,
                                  width: width, height: 14),
                    anchorEdge: index, backed: true
                )
            }
        )
    }
}

