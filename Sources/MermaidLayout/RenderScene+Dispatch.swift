import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers any parsed ``MermaidDiagram`` to a ``RenderScene``, or nil for a
    /// family this phase doesn't cover yet. This is the single switch the SVG /
    /// Canvas bridges call: it runs the matching `DiagramLayoutEngine.layout`
    /// and hands the placed layout to the family's `from(_:theme:measure:)`.
    ///
    /// Phase 0a lowered flowchart; Phase 0b adds state, ER, class, and sequence.
    /// Every remaining case returns nil (marked `// Phase 0b:`) until a later
    /// slice lowers it — the bridge then simply declines those sources.
    public static func from(_ diagram: MermaidDiagram, theme: RenderTheme,
                            measure: DiagramTextMeasurer,
                            spacing: DiagramSpacing = .regular) -> RenderScene? {
        switch diagram {
        case .flowchart(let chart):
            return from(DiagramLayoutEngine.layout(chart, measure: measure, spacing: spacing),
                        theme: theme, measure: measure)
        case .state(let state):
            return from(DiagramLayoutEngine.layout(state, measure: measure, spacing: spacing),
                        theme: theme, measure: measure)
        case .er(let er):
            return from(DiagramLayoutEngine.layout(er, measure: measure, spacing: spacing),
                        theme: theme, measure: measure)
        case .classDiagram(let cls):
            return from(DiagramLayoutEngine.layout(cls, measure: measure, spacing: spacing),
                        theme: theme, measure: measure)
        case .sequence(let sequence):
            return from(DiagramLayoutEngine.layout(sequence, measure: measure),
                        theme: theme, measure: measure)
        // Phase 0b: the remaining families lower in a later slice.
        case .pie, .gantt, .timeline, .mindmap, .journey, .quadrant, .packet,
             .xychart, .kanban, .radar, .treemap, .treeView, .venn, .cynefin,
             .wardley, .ishikawa, .eventModeling, .swimlane, .gitGraph, .sankey,
             .requirement, .zenuml, .c4, .architecture, .block:
            return nil
        }
    }
}
