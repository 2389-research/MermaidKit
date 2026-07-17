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
    /// Phase 0a lowered flowchart; Phase 0b-1 added state, ER, class, and
    /// sequence; Phase 0b-2 adds c4, architecture, block, swimlane, sankey, and
    /// requirement; Phase 0b-3a adds the chart families — pie, gantt, timeline,
    /// journey, quadrant, xychart, radar, packet, and kanban. Every remaining
    /// case returns nil (marked `// Phase 0b:`) until a later slice lowers it —
    /// the bridge then declines those sources.
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
        case .c4(let c4):
            return from(DiagramLayoutEngine.layout(c4, measure: measure),
                        theme: theme, measure: measure)
        case .architecture(let arch):
            return from(DiagramLayoutEngine.layout(arch, measure: measure, spacing: spacing),
                        theme: theme, measure: measure)
        case .block(let block):
            return from(DiagramLayoutEngine.layout(block, measure: measure),
                        theme: theme, measure: measure)
        case .swimlane(let swimlane):
            return from(DiagramLayoutEngine.layout(swimlane, measure: measure),
                        theme: theme, measure: measure)
        case .sankey(let sankey):
            return from(DiagramLayoutEngine.layout(sankey, measure: measure),
                        theme: theme, measure: measure)
        case .requirement(let requirement):
            return from(DiagramLayoutEngine.layout(requirement, measure: measure),
                        theme: theme, measure: measure)
        case .pie(let pie):
            return from(DiagramLayoutEngine.layout(pie, measure: measure),
                        theme: theme, measure: measure)
        case .gantt(let gantt):
            return from(DiagramLayoutEngine.layout(gantt, measure: measure),
                        theme: theme, measure: measure)
        case .timeline(let timeline):
            return from(DiagramLayoutEngine.layout(timeline, measure: measure),
                        theme: theme, measure: measure)
        case .journey(let journey):
            return from(DiagramLayoutEngine.layout(journey, measure: measure),
                        theme: theme, measure: measure)
        case .quadrant(let quadrant):
            return from(DiagramLayoutEngine.layout(quadrant, measure: measure),
                        theme: theme, measure: measure)
        case .xychart(let xychart):
            return from(DiagramLayoutEngine.layout(xychart, measure: measure),
                        theme: theme, measure: measure)
        case .radar(let radar):
            return from(DiagramLayoutEngine.layout(radar, measure: measure),
                        theme: theme, measure: measure)
        case .packet(let packet):
            return from(DiagramLayoutEngine.layout(packet, measure: measure),
                        theme: theme, measure: measure)
        case .kanban(let kanban):
            return from(DiagramLayoutEngine.layout(kanban, measure: measure),
                        theme: theme, measure: measure)
        // Phase 0b: the remaining families lower in a later slice.
        case .mindmap, .treemap, .treeView, .venn, .cynefin,
             .wardley, .ishikawa, .eventModeling, .gitGraph, .zenuml:
            return nil
        }
    }
}
