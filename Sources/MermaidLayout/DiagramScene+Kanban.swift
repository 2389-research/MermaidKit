import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a kanban layout to the common scene IR: column header bands are
    /// containers and cards are plain nodes. All text is node-internal, so
    /// there are no edges and no free-standing labels.
    static func from(_ layout: KanbanLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [DiagramScene.Node] = []

        // Column headers are tinted bands that head each lane; treat them as
        // containers so they never trip overlap/occlusion against their cards.
        for column in layout.columns {
            nodes.append(DiagramScene.Node(
                id: column.title,
                frame: column.headerFrame,
                isContainer: true
            ))
        }

        // Each card is a real box. Its label (wrapped lines + optional ticket)
        // is centred inside the box, so it stays implicit in the Node.
        for card in layout.cards {
            let id = card.ticket ?? card.lines.joined(separator: " ")
            nodes.append(DiagramScene.Node(
                id: id,
                frame: card.frame,
                isContainer: false
            ))
        }

        // A kanban board has no connectors and no free-standing labels: the
        // column title lives in its header Node and each card's text lives in
        // its card Node.
        return DiagramScene(
            name: "kanban",
            size: layout.size,
            nodes: nodes,
            edges: [],
            labels: []
        )
    }
}
