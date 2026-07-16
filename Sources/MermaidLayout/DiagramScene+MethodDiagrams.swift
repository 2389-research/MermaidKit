import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Scene lowerings for ishikawa, eventmodeling, and swimlane — same
// discipline as every type: the scene mirrors what the renderer draws.

extension DiagramScene {
    /// Fishbone: the head is a node; spine/ribs/twigs are edges; every cause
    /// and sub-cause text is a free-standing label.
    static func from(_ layout: IshikawaLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = [Node(id: layout.problem, frame: layout.headFrame)]
        var edges: [Edge] = [Edge(polyline: [layout.spineStart, layout.spineEnd], label: nil)]
        var labels: [Label] = []
        for rib in layout.ribs {
            edges.append(Edge(polyline: [rib.from, rib.to], label: rib.label))
            let w = measuredLabelSize(measure, rib.label).width
            labels.append(Label(
                text: rib.label,
                frame: CGRect(x: rib.labelCenter.x - w / 2, y: rib.labelCenter.y - 7,
                              width: w, height: 14),
                backed: true))
            for twig in rib.twigs {
                edges.append(Edge(polyline: [twig.from, twig.to], label: twig.label))
                let tw = measuredLabelSize(measure, twig.label).width
                labels.append(Label(
                    text: twig.label,
                    frame: CGRect(x: twig.labelCenter.x - tw / 2, y: twig.labelCenter.y - 7,
                                  width: tw, height: 14),
                    backed: true))
            }
        }
        _ = nodes  // (single head node; kept explicit for clarity)
        return DiagramScene(name: "ishikawa", size: layout.size,
                            nodes: nodes, edges: edges, labels: labels)
    }

    /// Event modeling: lanes are containers, frames are nodes, connectors
    /// are edges; lane names are gutter labels.
    static func from(_ layout: EventModelingLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = layout.lanes.map {
            Node(id: $0.name, frame: $0.band, isContainer: true)
        }
        nodes.append(contentsOf: layout.frames.map {
            Node(id: $0.entity, frame: $0.frame)
        })
        let edges = layout.connectors.map { Edge(polyline: $0, label: nil) }
        let labels: [Label] = layout.lanes.map { lane in
            let w = measuredLabelSize(measure, lane.name).width
            return Label(
                text: lane.name,
                frame: CGRect(x: lane.band.minX + 4, y: lane.band.minY + 3,
                              width: w, height: 14))
        }
        return DiagramScene(name: "eventmodeling", size: layout.size,
                            nodes: nodes, edges: edges, labels: labels)
    }

    /// Swimlane: lane bands are containers, nodes are nodes, edges carry
    /// their labels (anchored, chip-backed).
    static func from(_ layout: SwimlaneLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = layout.lanes.map {
            Node(id: $0.label, frame: $0.band, isContainer: true)
        }
        nodes.append(contentsOf: layout.nodes.map {
            Node(id: $0.id, frame: $0.frame)
        })
        let edges = layout.edges.map { Edge(polyline: $0.points, label: $0.label) }
        var labels: [Label] = []
        for (index, edge) in layout.edges.enumerated() {
            guard let text = edge.label, !text.isEmpty, let at = edge.labelCenter else { continue }
            let w = measuredLabelSize(measure, text).width
            labels.append(Label(
                text: text,
                frame: CGRect(x: at.x - w / 2, y: at.y - 7, width: w, height: 14),
                anchorEdge: index, backed: true))
        }
        for lane in layout.lanes {
            let w = measuredLabelSize(measure, lane.label).width
            labels.append(Label(
                text: lane.label,
                frame: CGRect(x: lane.band.minX + 4, y: lane.band.midY - 7,
                              width: min(w, 22), height: 14)))
        }
        return DiagramScene(name: "swimlane", size: layout.size,
                            nodes: nodes, edges: edges, labels: labels)
    }
}
