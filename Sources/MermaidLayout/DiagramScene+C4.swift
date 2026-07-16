import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a C4 model layout to the common scene IR. Every element is a
    /// leaf box (boundaries and deployment nodes are flattened away by the
    /// parser, so nothing here is a container). Relationships are orthogonal
    /// routed polylines that thread the empty channels between rows; each label
    /// is free-standing at a point on its route that sits in a clear channel
    /// band, clamped to stay on-canvas.
    static func from(_ layout: C4Layout, measure: DiagramTextMeasurer) -> DiagramScene {
        DiagramScene(
            name: "c4",
            size: layout.size,
            nodes: layout.boxes.enumerated().map { i, box in
                let title = box.titleLines.joined(separator: " ")
                let id = title.isEmpty ? "\(box.stereotype) #\(i)" : title
                return Node(id: id, frame: box.frame, isContainer: false)
            },
            edges: layout.edges.map { edge in
                Edge(polyline: edge.points, label: edge.label)
            },
            labels: layout.edges.enumerated().compactMap { index, edge -> Label? in
                guard let text = edge.label, !text.isEmpty else { return nil }
                let w = measuredLabelSize(measure, text).width
                let half = w / 2
                // The label point lives in an empty channel band, so clamping x
                // to the canvas can never push it onto a box.
                let cx = min(max(edge.labelPoint.x, half + 1), layout.size.width - half - 1)
                return Label(text: text,
                             frame: CGRect(x: cx - half, y: edge.labelPoint.y - 7,
                                           width: w, height: 14),
                             anchorEdge: index, backed: true)
            }
        )
    }
}