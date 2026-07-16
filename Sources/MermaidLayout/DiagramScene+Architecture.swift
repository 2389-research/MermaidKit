import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers an architecture layout to the common scene IR: group tint bands
    /// are containers, services and junction dots are plain nodes, and edges
    /// are unlabeled orthogonal wires.
    static func from(_ layout: ArchitectureLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [DiagramScene.Node] = []

        // Tinted group containers legitimately hold their member services, so
        // they are containers (exempt from overlap/occlusion).
        for (gi, group) in layout.groups.enumerated() {
            let id = group.label.isEmpty ? "group#\(gi)" : group.label
            nodes.append(DiagramScene.Node(id: id, frame: group.frame, isContainer: true))
        }

        // Service boxes and junction dots. Junctions carry no label, so give
        // them a stable synthesized id for reporting.
        for (si, svc) in layout.services.enumerated() {
            let id: String
            if svc.isJunction {
                id = "junction#\(si)"
            } else {
                id = svc.label.isEmpty ? "service#\(si)" : svc.label
            }
            nodes.append(DiagramScene.Node(id: id, frame: svc.frame, isContainer: false))
        }

        // Orthogonal wires; architecture edges carry no labels.
        let edges = layout.edges.map { DiagramScene.Edge(polyline: $0.points, label: nil) }

        // Group title strips are drawn text on container bands — free-
        // standing as far as the linter is concerned.
        let labels: [DiagramScene.Label] = layout.groups.compactMap { group in
            guard !group.label.isEmpty else { return nil }
            let iconOffset: CGFloat = group.icon.isEmpty ? 0 : 14
            let width = measuredLabelSize(measure, group.label).width
            return DiagramScene.Label(
                text: group.label,
                frame: CGRect(x: group.titleOrigin.x + iconOffset,
                              y: group.titleOrigin.y - 7,
                              width: width, height: 14))
        }

        return DiagramScene(
            name: "architecture",
            size: layout.size,
            nodes: nodes,
            edges: edges,
            labels: labels
        )
    }
}
