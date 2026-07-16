import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a state layout to the common scene IR: simple and pseudo states
    /// are plain nodes, composite-state boxes are containers, transitions are
    /// edges (routed polyline, straight start→end fallback), and transition
    /// labels are free-standing at the route's arc-length midpoint.
    static func from(_ layout: StateLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // Every simple/start/end/choice/fork/join node keeps its exact frame.
        // Layout already sizes point-like nodes (start/end dots, choice/fork/
        // join bars) into real rects, so no synthesis is needed here.
        var nodes: [DiagramScene.Node] = layout.nodes.map { node in
            DiagramScene.Node(id: node.id, frame: node.frame, isContainer: false)
        }
        // A composite state's box legitimately contains its children → container.
        nodes.append(contentsOf: layout.containers.map { container in
            DiagramScene.Node(id: container.label, frame: container.frame, isContainer: true)
        })

        // Transitions: prefer the routed polyline; fall back to the straight
        // start→end segment when the layout stored no waypoints.
        let edges: [DiagramScene.Edge] = layout.edges.map { edge in
            let poly = edge.points.count >= 2 ? edge.points : [edge.start, edge.end]
            return DiagramScene.Edge(polyline: poly, label: edge.label)
        }

        // Free-standing transition labels, centred on the polyline midpoint.
        let labels: [DiagramScene.Label] = layout.edges.enumerated().compactMap { index, edge in
            guard let text = edge.label, !text.isEmpty else { return nil }
            let poly = edge.points.count >= 2 ? edge.points : [edge.start, edge.end]
            let mid = edge.labelAnchor ?? polylineMidpoint(poly)
            let w = measuredLabelSize(measure, text).width
            return DiagramScene.Label(
                text: text,
                frame: CGRect(x: mid.x - w / 2, y: mid.y - 7, width: w, height: 14),
                anchorEdge: index,  // scene edges mirror layout.edges 1:1 above
                backed: true
            )
        }

        // Composite title strips: drawn centred in the container's title
        // band; lower them so content can't overdraw a composite's name.
        let compositeTitles: [DiagramScene.Label] = layout.containers.compactMap { container in
            guard !container.label.isEmpty else { return nil }
            let width = measuredLabelSize(measure, container.label).width
            return DiagramScene.Label(
                text: container.label,
                frame: CGRect(x: container.frame.midX - width / 2,
                              y: container.frame.minY + container.titleHeight / 2 - 7,
                              width: width, height: 14))
        }

        return DiagramScene(
            name: "state",
            size: layout.size,
            nodes: nodes,
            edges: edges,
            labels: labels + compositeTitles
        )
    }

}