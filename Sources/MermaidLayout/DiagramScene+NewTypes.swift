import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Scene lowerings for the v0.5.0 diagram types. Same discipline as every
// other type: the scene mirrors exactly what the renderer draws, so the
// linter checks real geometry.

extension DiagramScene {
    /// Tree view: each row is a node (glyph through text), connectors are
    /// edges; descriptions are backed labels beside their row.
    static func from(_ layout: TreeViewLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = []
        var labels: [Label] = []
        for (index, row) in layout.rows.enumerated() {
            // Node = glyph through label text; the description sits beside
            // the row as its own label (checked for collisions separately).
            var frame = row.frame
            if let descriptionStart = row.descriptionOrigin?.x {
                frame.size.width = descriptionStart - 8 - frame.minX
            }
            nodes.append(Node(id: "\(index):\(row.label)", frame: frame))
            if let description = row.description, let at = row.descriptionOrigin {
                let w = measuredLabelSize(measure, description).width
                labels.append(Label(
                    text: description,
                    frame: CGRect(x: at.x, y: at.y - 7, width: w, height: 14)))
            }
        }
        let edges = layout.connectors.map { Edge(polyline: $0, label: nil) }
        return DiagramScene(name: "treeView", size: layout.size,
                            nodes: nodes, edges: edges, labels: labels)
    }

    /// Venn: circles are containers (overlap is the point of the diagram);
    /// set and region labels are free-standing, chip-backed by the renderer.
    static func from(_ layout: VennLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        let nodes: [Node] = layout.circles.map { circle in
            Node(id: circle.id,
                 frame: CGRect(x: circle.center.x - circle.radius,
                               y: circle.center.y - circle.radius,
                               width: circle.radius * 2, height: circle.radius * 2),
                 isContainer: true)
        }
        var labels: [Label] = []
        for circle in layout.circles {
            guard let text = circle.label, !text.isEmpty else { continue }
            let w = measuredLabelSize(measure, text).width
            labels.append(Label(
                text: text,
                frame: CGRect(x: circle.labelCenter.x - w / 2,
                              y: circle.labelCenter.y - 7, width: w, height: 14),
                backed: true))
        }
        for region in layout.regionLabels {
            let w = measuredLabelSize(measure, region.text).width
            labels.append(Label(
                text: region.text,
                frame: CGRect(x: region.center.x - w / 2,
                              y: region.center.y - 7, width: w, height: 14),
                backed: true))
        }
        return DiagramScene(name: "venn", size: layout.size, nodes: nodes, labels: labels)
    }

    /// Cynefin: quadrants and the confusion disk are containers; items and
    /// transition labels are labels; transitions are edges.
    static func from(_ layout: CynefinLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = layout.quadrants.map {
            Node(id: $0.domain, frame: $0.frame, isContainer: true)
        }
        if let center = layout.center {
            nodes.append(Node(id: center.domain, frame: center.frame, isContainer: true))
        }
        var labels: [Label] = []
        for quadrant in layout.quadrants {
            // Domain heading + heuristic subtitle, drawn inside the container.
            let nameWidth = measuredLabelSize(measure, quadrant.name).width
            labels.append(Label(
                text: quadrant.name,
                frame: CGRect(x: quadrant.frame.midX - nameWidth / 2,
                              y: quadrant.frame.minY + 11, width: nameWidth, height: 14)))
            let heuristicWidth = measuredLabelSize(measure, quadrant.heuristic).width
            labels.append(Label(
                text: quadrant.heuristic,
                frame: CGRect(x: quadrant.frame.midX - heuristicWidth / 2,
                              y: quadrant.frame.minY + 28, width: heuristicWidth, height: 12)))
        }
        for quadrant in layout.quadrants + (layout.center.map { [$0] } ?? []) {
            for item in quadrant.items {
                let w = measuredLabelSize(measure, item.text).width
                labels.append(Label(
                    text: item.text,
                    frame: CGRect(x: item.center.x - w / 2, y: item.center.y - 7,
                                  width: w, height: 14)))
            }
        }
        var edges: [Edge] = []
        for (index, transition) in layout.transitions.enumerated() {
            edges.append(Edge(polyline: [transition.from, transition.to], label: transition.label))
            if let text = transition.label, !text.isEmpty {
                let w = measuredLabelSize(measure, text).width
                labels.append(Label(
                    text: text,
                    frame: CGRect(x: transition.labelCenter.x - w / 2,
                                  y: transition.labelCenter.y - 7, width: w, height: 14),
                    anchorEdge: index, backed: true))
            }
        }
        return DiagramScene(name: "cynefin", size: layout.size,
                            nodes: nodes, edges: edges, labels: labels)
    }

    /// Wardley: the plot is a container, component dots are small nodes,
    /// links/evolves are edges, and every label is free-standing (the layout
    /// staggers them; the linter verifies it worked).
    static func from(_ layout: WardleyLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = [Node(id: "plot", frame: layout.plotFrame, isContainer: true)]
        var labels: [Label] = []
        for node in layout.nodes {
            nodes.append(Node(id: node.name,
                              frame: CGRect(x: node.center.x - 5, y: node.center.y - 5,
                                            width: 10, height: 10)))
            labels.append(Label(text: node.name, frame: node.labelFrame, backed: true))
        }
        var edges: [Edge] = layout.links.map { Edge(polyline: [$0.from, $0.to], label: nil) }
        edges.append(contentsOf: layout.evolves.map { Edge(polyline: [$0.from, $0.to], label: nil) })
        for note in layout.notes {
            let w = measuredLabelSize(measure, note.text).width
            labels.append(Label(
                text: note.text,
                frame: CGRect(x: note.center.x - w / 2, y: note.center.y - 7,
                              width: w, height: 14),
                backed: true))
        }
        return DiagramScene(name: "wardley", size: layout.size,
                            nodes: nodes, edges: edges, labels: labels)
    }
}
