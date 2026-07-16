import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a laid-out timeline to the common scene IR.
    ///
    /// Geometry recap (`DiagramLayoutTimeline`): a vertical spine carries one
    /// dot per period; each period's events are rounded cards stacked to the
    /// right; a named section run is a full-width tint band spanning its
    /// periods (with a reserved header strip on top). We map:
    ///   - section bands       → container Nodes (they enclose dots + cards)
    ///   - period dots         → point Nodes (small synthesized frames)
    ///   - event cards         → Nodes
    ///   - period labels       → free-standing Labels (right-aligned gutter)
    ///   - section names       → free-standing Labels (header strip)
    /// There are no connectors between distinct nodes (the spine is decorative
    /// chrome, not an edge between two nodes), so `edges` is empty.
    static func from(_ layout: TimelineLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [DiagramScene.Node] = []
        var labels: [DiagramScene.Label] = []

        // Section tint bands legitimately contain the dots/cards of their
        // periods → containers, exempt from overlap/occlusion.
        for section in layout.sections {
            nodes.append(DiagramScene.Node(
                id: "section: \(section.name)",
                frame: section.frame,
                isContainer: true
            ))
            // The section name sits in the reserved header strip along the top
            // edge of the band, left-aligned at the band's left inset.
            let w = measuredLabelSize(measure, section.name).width
            labels.append(DiagramScene.Label(
                text: section.name,
                frame: CGRect(x: section.frame.minX + 6,
                              y: section.frame.minY + 4,
                              width: w, height: 14)
            ))
        }

        for period in layout.periods {
            // The dot on the spine is a point — synthesize an 8×8 frame.
            nodes.append(DiagramScene.Node(
                id: "• \(period.label)",
                frame: CGRect(x: period.dot.x - 4, y: period.dot.y - 4, width: 8, height: 8)
            ))

            // Each event is a card.
            for event in period.events {
                nodes.append(DiagramScene.Node(id: event.text, frame: event.frame))
            }

            // Period label: right-aligned, its right edge at labelPoint.x,
            // vertically centred on labelPoint.y.
            let w = measuredLabelSize(measure, period.label).width
            labels.append(DiagramScene.Label(
                text: period.label,
                frame: CGRect(x: period.labelPoint.x - w,
                              y: period.labelPoint.y - 7,
                              width: w, height: 14)
            ))
        }

        return DiagramScene(
            name: "timeline",
            size: layout.size,
            nodes: nodes,
            edges: [],
            labels: labels
        )
    }
}