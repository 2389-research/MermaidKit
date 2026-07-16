import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a quadrant chart to the common scene IR: the plot square and
    /// four tint quarters are containers, each data dot is a small node, and
    /// point, quadrant, and axis captions are free-standing labels (y-axis
    /// labels as rotated tall-narrow boxes). No connectors, so `edges` is empty.
    static func from(_ layout: QuadrantLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        var nodes: [Node] = []

        // The plot square and the four tint quarters legitimately contain the
        // data dots, so they are containers (exempt from overlap/occlusion).
        nodes.append(Node(id: "plot", frame: layout.plotRect, isContainer: true))
        for (index, rect) in layout.quadrantRects.enumerated() {
            nodes.append(Node(id: "quadrant-\(index + 1)", frame: rect, isContainer: true))
        }

        // Each data point is a real box: a small frame around its dot.
        let r = layout.dotRadius
        for point in layout.points {
            let frame = CGRect(x: point.position.x - r, y: point.position.y - r,
                               width: r * 2, height: r * 2)
            nodes.append(Node(id: point.label, frame: frame))
        }

        // Quadrant charts have no connectors.

        // Free-standing labels that can collide: each dot's right-anchored
        // label, the quadrant names, and the axis-end labels.
        var labels: [Label] = []
        func leftAnchored(_ text: String, at anchor: CGPoint) -> Label {
            let w = measuredLabelSize(measure, text).width
            return Label(text: text, frame: CGRect(x: anchor.x, y: anchor.y - 7, width: w, height: 14))
        }
        func centered(_ text: String, at c: CGPoint) -> Label {
            let w = measuredLabelSize(measure, text).width
            return Label(text: text, frame: CGRect(x: c.x - w / 2, y: c.y - 7, width: w, height: 14))
        }
        // y-axis labels are painted rotated 90° in the narrow left gutter, so
        // their bounding box is tall-and-narrow (width = font height, height =
        // text length) — lowering them as horizontal boxes made them spill off
        // the left edge of the canvas.
        func rotatedCentered(_ text: String, at c: CGPoint) -> Label {
            let h = measuredLabelSize(measure, text).width
            return Label(text: text, frame: CGRect(x: c.x - 7, y: c.y - h / 2, width: 14, height: h))
        }

        for point in layout.points {
            labels.append(leftAnchored(point.label, at: point.labelPoint))
        }
        for q in layout.quadrantLabels {
            labels.append(centered(q.text, at: q.center))
        }
        for x in layout.xAxisLabels {
            labels.append(centered(x.text, at: x.center))
        }
        for y in layout.yAxisLabels {
            labels.append(rotatedCentered(y.text, at: y.center))
        }

        return DiagramScene(
            name: "quadrant",
            size: layout.size,
            nodes: nodes,
            edges: [],
            labels: labels
        )
    }
}