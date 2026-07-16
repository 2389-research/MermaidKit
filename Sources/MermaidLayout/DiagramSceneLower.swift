import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {

    /// Lowers any parsed diagram to its scene by laying it out and delegating
    /// to the per-type `from(_:)` overload (one per `DiagramScene+<Type>.swift`).
    public static func lower(_ diagram: MermaidDiagram, measure: DiagramTextMeasurer) -> DiagramScene {
        var scene = lowerBody(diagram, measure: measure)
        // Titles are drawn by the shared drawDiagramTitle at (width/2, y 14);
        // most per-type lowerings never included them, leaving the linter
        // blind to title-vs-content collisions and clipped long titles. Add
        // the title label centrally — for every current and future type —
        // unless the type's own lowering already emitted it (pie, radar).
        if let title = diagram.titleText, !title.isEmpty,
           !scene.labels.contains(where: { $0.text == title && $0.frame.minY < 26 }) {
            let width = measure(title, 12.5).width
            scene = DiagramScene(
                name: scene.name, size: scene.size,
                nodes: scene.nodes, edges: scene.edges,
                labels: scene.labels + [Label(
                    text: title,
                    frame: CGRect(x: scene.size.width / 2 - width / 2, y: 7,
                                  width: width, height: 14))])
        }
        return scene
    }

    /// Lowers a parsed diagram and stamps the source's metadata (front-matter
    /// title, accTitle, accDescr) onto the scene, so hosts consuming the IR
    /// can caption the diagram and set accessibility labels. Geometry is
    /// identical to ``lower(_:measure:)`` — metadata is data, not layout.
    public static func lower(_ diagram: MermaidDiagram, metadata: DiagramMetadata,
                             measure: DiagramTextMeasurer) -> DiagramScene {
        let scene = lower(diagram, measure: measure)
        guard !metadata.isEmpty else { return scene }
        return DiagramScene(
            name: scene.name, size: scene.size,
            nodes: scene.nodes, edges: scene.edges, labels: scene.labels,
            title: metadata.title,
            accessibilityTitle: metadata.accessibilityTitle,
            accessibilityDescription: metadata.accessibilityDescription)
    }

    private static func lowerBody(_ diagram: MermaidDiagram, measure: DiagramTextMeasurer) -> DiagramScene {
        switch diagram {
        case .flowchart(let d):   return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .sequence(let d):    return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .pie(let d):         return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .classDiagram(let d):return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .er(let d):          return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .state(let d):       return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .gantt(let d):       return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .timeline(let d):    return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .mindmap(let d):     return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .journey(let d):     return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .quadrant(let d):    return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .packet(let d):      return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .xychart(let d):     return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .kanban(let d):      return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .radar(let d):       return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .treemap(let d):     return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .gitGraph(let d):    return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .requirement(let d): return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .sankey(let d):      return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .c4(let d):          return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .architecture(let d):return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .block(let d):       return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .zenuml(let d):      return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .treeView(let d):    return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .venn(let d):        return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .cynefin(let d):     return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .wardley(let d):     return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .ishikawa(let d):    return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .eventModeling(let d): return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        case .swimlane(let d):    return .from(DiagramLayoutEngine.layout(d, measure: measure), measure: measure)
        }
    }

    /// Lint report for a Mermaid source string, or nil if it doesn't parse.
    public static func lintReport(source: String, measure: DiagramTextMeasurer) -> String? {
        guard let diagram = MermaidParser.parse(source) else { return nil }
        return DiagramLayoutLinter.report(lower(diagram, measure: measure))
    }
}
