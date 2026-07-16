import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a laid-out Gantt chart to the common scene IR.
    ///
    /// - Task bars (and milestone diamonds) become `Node`s; their task label is
    ///   the node's own (gutter) label and is therefore implicit — not repeated
    ///   in `labels`.
    /// - Section tint bands legitimately *contain* the run of task rows they
    ///   span, so they are container nodes (exempt from overlap/occlusion).
    /// - A Gantt has no connectors between tasks, so `edges` is empty; the day
    ///   ticks are axis gridlines, not routed edges, so their vertical rules are
    ///   deliberately NOT lowered as edges (that would spuriously "occlude"
    ///   every bar). Each tick's day-index caption is a free-standing axis label.
    static func from(_ layout: GanttLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = []

        // Section bands first so they read as the backing containers.
        for section in layout.sections {
            nodes.append(Node(id: "section:\(section.name)", frame: section.frame, isContainer: true))
        }

        // One node per task bar / milestone diamond.
        for bar in layout.bars {
            nodes.append(Node(id: bar.label, frame: bar.frame))
        }

        // Day-axis tick captions: free-standing labels sitting under the chart.
        let labels: [Label] = layout.ticks.map { tick in
            let w = measuredLabelSize(measure, tick.label).width
            return Label(
                text: tick.label,
                frame: CGRect(x: tick.x - w / 2, y: tick.bottom + 2, width: w, height: 14)
            )
        }

        return DiagramScene(
            name: "gantt",
            size: layout.size,
            nodes: nodes,
            edges: [],
            labels: labels
        )
    }
}