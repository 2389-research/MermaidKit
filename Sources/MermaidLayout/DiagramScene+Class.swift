import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lower a laid-out UML class diagram into the common scene IR.
    ///
    /// Each class box becomes a `Node` (its compartments — name / attributes /
    /// methods — are internal chrome, not separate nodes, so a class is one
    /// solid box the linter treats as opaque). Class boxes never *contain*
    /// other boxes, so none is a container. Relations become `Edge`s carrying
    /// their orthogonal route; a relation's multiplicity/role label is a
    /// free-standing `Label` pinned to the route's midpoint so the linter can
    /// catch it colliding with a box or another label.
    static func from(_ layout: ClassLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        let nodes = layout.boxes.map { box in
            Node(id: box.name, frame: box.frame, isContainer: false)
        }

        let edges = layout.edges.map { edge in
            Edge(polyline: edge.points, label: edge.label)
        }

        let labels: [Label] = layout.edges.enumerated().compactMap { index, edge in
            guard let text = edge.label, !text.isEmpty else { return nil }
            let center = edge.labelAnchor ?? polylineMidpoint(edge.points)
            let w = measuredLabelSize(measure, text).width
            return Label(
                text: text,
                frame: CGRect(x: center.x - w / 2, y: center.y - 7, width: w, height: 14),
                anchorEdge: index, backed: true
            )
        }

        return DiagramScene(
            name: "class",
            size: layout.size,
            nodes: nodes,
            edges: edges,
            labels: labels
        )
    }

}
