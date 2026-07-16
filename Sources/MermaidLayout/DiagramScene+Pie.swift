import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a pie chart's geometry to the common scene IR. A pie has no
    /// connectors, so `edges` is empty and occlusion never applies. The disk
    /// itself is a single container node (its wedges are angular, not
    /// rectangular — modelling them as boxes would report spurious overlaps
    /// since every wedge shares the disk's bounding box). The free-standing
    /// labels that can actually collide are the title and the stacked legend
    /// rows (swatch + "Label (NN%)" chip), so those are the `labels`.
    static func from(_ layout: PieLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // The pie disk: a container (exempt from overlap/occlusion) sized to
        // the circle's bounding box around `center` with `radius`.
        let disk = Node(
            id: layout.title ?? "pie",
            frame: CGRect(
                x: layout.center.x - layout.radius,
                y: layout.center.y - layout.radius,
                width: layout.radius * 2,
                height: layout.radius * 2
            ),
            isContainer: true
        )

        var labels: [Label] = []

        // Title, centred above the disk (matches the renderer's placement).
        if let title = layout.title {
            let w = CGFloat(max(title.count, 1)) * 7
            labels.append(Label(
                text: title,
                frame: CGRect(
                    x: layout.center.x - w / 2,
                    y: layout.center.y - layout.radius - 16 - 8,
                    width: w,
                    height: 16
                )
            ))
        }

        // Legend rows, vertically stacked from `legendOrigin`, 20pt pitch.
        // Each row is a 10×10 swatch followed by a "Label (NN%)" chip.
        var y = layout.legendOrigin.y
        for slice in layout.slices {
            let percent = slice.fraction.isFinite ? Int((slice.fraction * 100).rounded()) : 0
            let text = "\(slice.label) (\(percent)%)"
            let textWidth = measuredLabelSize(measure, text).width
            labels.append(Label(
                text: text,
                frame: CGRect(
                    x: layout.legendOrigin.x,
                    y: y + 2,
                    width: 10 + 6 + textWidth,
                    height: 14
                )
            ))
            y += 20
        }

        return DiagramScene(
            name: "pie",
            size: layout.size,
            nodes: [disk],
            edges: [],
            labels: labels
        )
    }
}
