import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers any parsed ``MermaidDiagram`` to a ``RenderScene``. Every one of
    /// the ~30 diagram families now lowers, so this never returns nil — the
    /// optional result is kept only for source-compatibility with callers that
    /// still branch on it. This is the single switch the SVG / Canvas bridges
    /// call: it runs the matching `DiagramLayoutEngine.layout` and hands the
    /// placed layout to the family's `from(_:theme:measure:)`.
    ///
    /// Phase 0a lowered flowchart; Phase 0b-1 added state, ER, class, and
    /// sequence; Phase 0b-2 adds c4, architecture, block, swimlane, sankey, and
    /// requirement; Phase 0b-3a adds the chart families — pie, gantt, timeline,
    /// journey, quadrant, xychart, radar, packet, and kanban; Phase 0b-3b
    /// completes coverage with mindmap, treemap, treeView, venn, cynefin,
    /// wardley, ishikawa, eventModeling, zenuml, and gitGraph. The switch is now
    /// exhaustive over all diagram types.
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
        case .mindmap(let mindmap):
            return from(DiagramLayoutEngine.layout(mindmap, measure: measure),
                        theme: theme, measure: measure)
        case .treemap(let treemap):
            return from(DiagramLayoutEngine.layout(treemap, measure: measure),
                        theme: theme, measure: measure)
        case .treeView(let treeView):
            return from(DiagramLayoutEngine.layout(treeView, measure: measure),
                        theme: theme, measure: measure)
        case .venn(let venn):
            return from(DiagramLayoutEngine.layout(venn, measure: measure),
                        theme: theme, measure: measure)
        case .cynefin(let cynefin):
            return from(DiagramLayoutEngine.layout(cynefin, measure: measure),
                        theme: theme, measure: measure)
        case .wardley(let wardley):
            return from(DiagramLayoutEngine.layout(wardley, measure: measure),
                        theme: theme, measure: measure)
        case .ishikawa(let ishikawa):
            return from(DiagramLayoutEngine.layout(ishikawa, measure: measure),
                        theme: theme, measure: measure)
        case .eventModeling(let eventModeling):
            return from(DiagramLayoutEngine.layout(eventModeling, measure: measure),
                        theme: theme, measure: measure)
        case .zenuml(let zenuml):
            return from(DiagramLayoutEngine.layout(zenuml, measure: measure),
                        theme: theme, measure: measure)
        case .gitGraph(let gitGraph):
            return from(DiagramLayoutEngine.layout(gitGraph, measure: measure),
                        theme: theme, measure: measure)
        }
    }
}
