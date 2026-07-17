import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Builds a left-anchored text run — the platform-free twin of
    /// `DiagramRenderer.drawTextLeft`, which centers the run at
    /// `origin.x + measuredWidth / 2` so its left edge sits at `origin.x`. The
    /// chart families (timeline cards, journey/quadrant point labels, radar and
    /// kanban rows, xy value ticks) all anchor text this way.
    static func leftText(_ string: String, at origin: CGPoint, fontSize: CGFloat,
                         weight: FontWeight = .regular, color: DiagramColor,
                         measure: DiagramTextMeasurer) -> Text {
        let width = measure(string, Double(fontSize)).width
        return Text(string: string,
                    center: CGPoint(x: origin.x + width / 2, y: origin.y),
                    fontSize: fontSize, weight: weight, color: color)
    }
}
