import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers an xychart layout to the common scene IR: the plot rect and the
    /// bars are containers (a line series legitimately overlays a bar), line
    /// series are edges, and tick/category captions plus axis titles are
    /// free-standing labels (the y-axis title as a rotated vertical strip).
    static func from(_ layout: XYChartLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // A synthesized frame for a label stored only as a center point.
        func labelFrame(_ text: String, _ center: CGPoint) -> CGRect {
            let w = measuredLabelSize(measure, text).width
            return CGRect(x: center.x - w / 2, y: center.y - 7, width: w, height: 14)
        }
        // The y-axis title is drawn rotated 90° about its center, so its
        // bounding box is a *vertical* strip: text length runs along y and the
        // line height is the width. Lowering it as a horizontal box would fake
        // a wide frame spilling off the left edge that is never actually drawn.
        func rotatedLabelFrame(_ text: String, _ center: CGPoint) -> CGRect {
            let len = measuredLabelSize(measure, text).width
            return CGRect(x: center.x - 7, y: center.y - len / 2, width: 14, height: len)
        }

        // The plot rect is a container: bars sit inside it and lines route
        // across it, so it must be exempt from overlap/occlusion checks.
        var nodes: [Node] = [
            Node(id: "plot", frame: layout.plotRect, isContainer: true)
        ]
        // Every bar is a visible box. Ids are stable per series+slot.
        for (i, bar) in layout.bars.enumerated() {
            // A bar is a data mark, not an obstacle: a line series legitimately
            // overlays it, so exempt it from occlusion/overlap checks.
            nodes.append(Node(id: "bar-s\(bar.colorIndex)-\(i)", frame: bar.frame, isContainer: true))
        }

        // Line series are genuine polylines over the plot.
        let edges: [Edge] = layout.lines.map { Edge(polyline: $0.points) }

        // Free-standing labels: x categories, y ticks, and axis titles.
        var labels: [Label] = []
        for l in layout.xLabels {
            labels.append(Label(text: l.text, frame: labelFrame(l.text, l.center)))
        }
        for l in layout.yLabels {
            labels.append(Label(text: l.text, frame: labelFrame(l.text, l.center)))
        }
        if let t = layout.yAxisTitle {
            labels.append(Label(text: t.text, frame: rotatedLabelFrame(t.text, t.center)))
        }
        if let t = layout.xAxisTitle {
            labels.append(Label(text: t.text, frame: labelFrame(t.text, t.center)))
        }

        return DiagramScene(
            name: "xychart",
            size: layout.size,
            nodes: nodes,
            edges: edges,
            labels: labels
        )
    }
}
