import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a user-journey layout to the common scene IR: section tint
    /// bands are containers, each task's score badge is a small node, and
    /// section names, task labels, and actor lists are free-standing labels.
    /// A journey has no connectors, so `edges` is empty.
    static func from(_ layout: JourneyLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = []
        var labels: [Label] = []

        // Section tint bands legitimately contain the task rows drawn over them,
        // so they are containers (exempt from overlap/occlusion).
        for band in layout.sections {
            nodes.append(Node(id: band.name, frame: band.frame, isContainer: true))
            // The section name is drawn left-aligned in the reserved 22pt header
            // strip at the top of the band — a free-standing label.
            labels.append(Label(
                text: band.name,
                frame: CGRect(x: band.frame.minX + 8,
                              y: band.frame.minY + 4,
                              width: measuredLabelSize(measure, band.name).width,
                              height: 14)
            ))
        }

        // Each task's satisfaction badge is a small circular node centred on
        // scoreCenter; its score digit is the node's own (implicit) label.
        let r = layout.scoreDiameter / 2
        for task in layout.tasks {
            nodes.append(Node(
                id: task.label,
                frame: CGRect(x: task.scoreCenter.x - r,
                              y: task.scoreCenter.y - r,
                              width: layout.scoreDiameter,
                              height: layout.scoreDiameter)
            ))

            // The task label is left-aligned at labelPoint (row centre).
            labels.append(Label(
                text: task.label,
                frame: CGRect(x: task.labelPoint.x,
                              y: task.labelPoint.y - 7,
                              width: measuredLabelSize(measure, task.label).width,
                              height: 14)
            ))

            // The joined actor list is left-aligned at actorsPoint.
            if !task.actors.isEmpty {
                labels.append(Label(
                    text: task.actors,
                    frame: CGRect(x: task.actorsPoint.x,
                                  y: task.actorsPoint.y - 7,
                                  width: measuredLabelSize(measure, task.actors).width,
                                  height: 14)
                ))
            }
        }

        return DiagramScene(
            name: "journey",
            size: layout.size,
            nodes: nodes,
            edges: [],
            labels: labels
        )
    }
}
