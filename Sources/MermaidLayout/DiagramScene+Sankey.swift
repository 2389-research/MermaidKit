import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a sankey layout to the common scene IR: each flow bar is a
    /// plain node, each link is an edge along its routed centerline, and bar
    /// captions (drawn outboard of their bars) are free-standing labels.
    static func from(_ layout: SankeyLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        DiagramScene(
            name: "sankey",
            size: layout.size,
            // Each node is a flow bar; bars never contain other bars.
            nodes: layout.nodes.map { node in
                Node(id: node.label, frame: node.rect, isContainer: false)
            },
            // Each link is a flow band; represent it as its routed centerline
            // (source bar's right edge → target bar's left edge). The layout
            // detours column-skipping links around intermediate bars, so the
            // polyline reflects the real flow route for occlusion checks.
            edges: layout.links.map { link in
                Edge(polyline: link.route, label: nil)
            },
            // Node labels sit outboard of their bars (not centered on them), so
            // they are free-standing and can collide with neighbouring columns.
            labels: layout.nodes.map { node in
                let w = measuredLabelSize(measure, node.label).width
                return Label(
                    text: node.label,
                    frame: CGRect(
                        x: node.labelCenter.x - w / 2,
                        y: node.labelCenter.y - 7,
                        width: w,
                        height: 14),
                    backed: true)
            }
        )
    }
}
