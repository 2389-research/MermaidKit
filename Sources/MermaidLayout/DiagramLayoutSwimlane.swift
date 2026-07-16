import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Laid-out swimlane diagram: horizontal lane bands, nodes placed on the
/// shared topological column grid inside their lane, and orthogonal edges
/// (straight within a row, elbowed across lanes/columns).
public struct SwimlaneLayout: Sendable {
    public struct Lane: Sendable {
        public let label: String
        public let band: CGRect
    }
    public struct Node: Sendable {
        public let id: String
        public let label: String
        public let shape: Flowchart.NodeShape
        public let frame: CGRect
    }
    public struct Edge: Sendable {
        public let points: [CGPoint]
        public let label: String?
        public let dashed: Bool
        public let labelCenter: CGPoint?
    }
    public let size: CGSize
    public let lanes: [Lane]
    public let nodes: [Node]
    public let edges: [Edge]
}

extension DiagramLayoutEngine {
    /// Lays out a swimlane diagram: network-simplex layer assignment gives
    /// every node a global column (time flows in the lane direction), the
    /// node's lane gives its band, and nodes sharing a lane+column stack
    /// within the band. The lane constraint is what distinguishes this from
    /// a flowchart: cross-axis position is AUTHORED (the lane), not
    /// optimized, so only the main axis is solved.
    public static func layout(_ diagram: SwimlaneDiagram, measure: DiagramTextMeasurer) -> SwimlaneLayout {
        let margin: CGFloat = 14
        let gutter: CGFloat = 30    // lane label gutter (rotated text)
        let columnGap: CGFloat = 46
        let rowGap: CGFloat = 14
        let lanePad: CGFloat = 16
        let boxHeight: CGFloat = 32

        // 1. Global columns from the layered layering (back-edges stripped
        //    the same way the flowchart pipeline does: cycles must not wedge
        //    the solver).
        let ids = diagram.nodes.map(\.id)
        // Drop self-loops, find the back-edges of the remaining digraph, and
        // strip them so the layering solver only sees a DAG.
        let forwardCandidates = diagram.edges
            .filter { $0.from != $0.to }
            .map { ($0.from, $0.to) }
        let backEdges = backEdgeIndices(ids: ids, edges: forwardCandidates)
        let acyclic = forwardCandidates.enumerated()
            .filter { !backEdges.contains($0.offset) }
            .map { $0.element }
        let layerOf = assignLayers(ids: ids, edges: acyclic)

        // 2. Column widths: widest node in each column.
        func nodeSize(_ node: SwimlaneDiagram.Node) -> CGSize {
            let text = measure(node.label, nodeFontSize)
            let extra: CGFloat = node.shape == .diamond ? 34 : 22
            return CGSize(width: text.width + extra, height: boxHeight)
        }
        let columns = (layerOf.values.max() ?? 0) + 1
        var columnWidth = [CGFloat](repeating: 64, count: columns)
        for node in diagram.nodes {
            let column = layerOf[node.id] ?? 0
            columnWidth[column] = max(columnWidth[column], nodeSize(node).width)
        }
        var columnX = [CGFloat](repeating: 0, count: columns)
        var x = margin + gutter
        for c in 0..<columns {
            columnX[c] = x
            x += columnWidth[c] + columnGap
        }
        let contentRight = x - columnGap

        // 3. Lane bands: height = tallest stack of same-lane same-column
        //    nodes, at least one row.
        var stacks: [String: [Int: [SwimlaneDiagram.Node]]] = [:]
        for node in diagram.nodes {
            stacks[node.laneID, default: [:]][layerOf[node.id] ?? 0, default: []].append(node)
        }
        var lanes: [SwimlaneLayout.Lane] = []
        var laneY: [String: CGFloat] = [:]
        var y = margin
        for lane in diagram.lanes {
            let deepest = stacks[lane.id]?.values.map(\.count).max() ?? 1
            let height = lanePad * 2 + CGFloat(deepest) * boxHeight + CGFloat(deepest - 1) * rowGap
            lanes.append(.init(label: lane.label,
                               band: CGRect(x: margin, y: y,
                                            width: contentRight - margin, height: height)))
            laneY[lane.id] = y
            y += height + 4
        }

        // 4. Place nodes: centred in their column, stacked in their lane.
        var placed: [String: CGRect] = [:]
        var nodes: [SwimlaneLayout.Node] = []
        for lane in diagram.lanes {
            guard let byColumn = stacks[lane.id], let bandY = laneY[lane.id] else { continue }
            for (column, group) in byColumn.sorted(by: { $0.key < $1.key }) {
                for (row, node) in group.enumerated() {
                    let size = nodeSize(node)
                    let frame = CGRect(
                        x: columnX[column] + (columnWidth[column] - size.width) / 2,
                        y: bandY + lanePad + CGFloat(row) * (boxHeight + rowGap),
                        width: size.width, height: size.height)
                    placed[node.id] = frame
                    nodes.append(.init(id: node.id, label: node.label,
                                       shape: node.shape, frame: frame))
                }
            }
        }

        // 5. Edges: right edge to left edge; same-row edges run straight,
        //    everything else takes a mid-gap elbow. Backward edges loop via
        //    the gap below the deeper node.
        var edges: [SwimlaneLayout.Edge] = []
        for edge in diagram.edges {
            guard let a = placed[edge.from], let b = placed[edge.to] else { continue }
            var points: [CGPoint]
            if a.maxX <= b.minX {
                let start = CGPoint(x: a.maxX, y: a.midY)
                let end = CGPoint(x: b.minX, y: b.midY)
                if abs(start.y - end.y) < 0.5 {
                    points = [start, end]
                } else {
                    let midX = (start.x + end.x) / 2
                    points = [start, CGPoint(x: midX, y: start.y),
                              CGPoint(x: midX, y: end.y), end]
                }
            } else {
                // Backward or same-column: route below both boxes.
                let below = max(a.maxY, b.maxY) + rowGap
                points = [CGPoint(x: a.midX, y: a.maxY),
                          CGPoint(x: a.midX, y: below),
                          CGPoint(x: b.midX, y: below),
                          CGPoint(x: b.midX, y: b.maxY)]
            }
            var labelCenter: CGPoint?
            if edge.label != nil {
                let mid = points.count == 2
                    ? CGPoint(x: (points[0].x + points[1].x) / 2, y: points[0].y - 9)
                    : CGPoint(x: points[1].x, y: (points[1].y + points[2].y) / 2)
                labelCenter = mid
            }
            edges.append(.init(points: points, label: edge.label,
                               dashed: edge.dashed, labelCenter: labelCenter))
        }

        return SwimlaneLayout(
            size: CGSize(width: contentRight + margin, height: y - 4 + margin),
            lanes: lanes, nodes: nodes, edges: edges)
    }
}
