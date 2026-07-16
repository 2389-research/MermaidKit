import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a radar chart's geometry to the common scene IR. Like a pie, a
    /// radar has no connectors, so `edges` is empty and occlusion never
    /// applies. The graticule disk is a single container node: its curve
    /// polygons are angular and every curve shares the disk's bounding box, so
    /// modelling curve vertices as boxes would report spurious overlaps (curves
    /// legitimately cross and coincide at axis vertices). The free-standing
    /// labels that can actually collide are the title, the outward spoke/axis
    /// labels, and the stacked legend rows, so those are the `labels`.
    static func from(_ layout: RadarLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // The plot disk: a container (exempt from overlap/occlusion) sized to
        // the full-radius circle. Derive the radius from the longest spoke
        // (spoke ends sit at fraction 1); fall back to the outer ring.
        let radius: CGFloat = {
            func dist(_ p: CGPoint) -> CGFloat {
                hypot(p.x - layout.center.x, p.y - layout.center.y)
            }
            let spokeMax = layout.spokes.map { dist($0.end) }.max()
            let ringMax = (layout.rings.last?.points ?? []).map(dist).max()
            return spokeMax ?? ringMax ?? 0
        }()
        let disk = Node(
            id: layout.title ?? "radar",
            frame: CGRect(
                x: layout.center.x - radius,
                y: layout.center.y - radius,
                width: radius * 2,
                height: radius * 2
            ),
            isContainer: true
        )

        var labels: [Label] = []

        // Title, centred above the disk near the top of the canvas.
        if let title = layout.title {
            let w = CGFloat(max(title.count, 1)) * 7
            labels.append(Label(
                text: title,
                frame: CGRect(
                    x: layout.center.x - w / 2,
                    y: 4,
                    width: w,
                    height: 16
                )
            ))
        }

        // Outward axis labels, one per spoke. `labelPoint` is the label centre.
        for spoke in layout.spokes {
            let w = measuredLabelSize(measure, spoke.label).width
            labels.append(Label(
                text: spoke.label,
                frame: CGRect(
                    x: spoke.labelPoint.x - w / 2,
                    y: spoke.labelPoint.y - 7,
                    width: w,
                    height: 14
                )
            ))
        }

        // Legend rows below the chart: a swatch followed by the curve label.
        // `labelPoint` is the text's left edge; `swatchCenter` sits to its left.
        for entry in layout.legend {
            let textWidth = measuredLabelSize(measure, entry.label).width
            let left = entry.swatchCenter.x - 5
            let right = entry.labelPoint.x + textWidth
            labels.append(Label(
                text: entry.label,
                frame: CGRect(
                    x: left,
                    y: entry.labelPoint.y - 7,
                    width: right - left,
                    height: 14
                )
            ))
        }

        return DiagramScene(
            name: "radar",
            size: layout.size,
            nodes: [disk],
            edges: [],
            labels: labels
        )
    }
}
