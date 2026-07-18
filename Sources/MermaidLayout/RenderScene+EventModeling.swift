import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers an `EventModelingLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: EventModelingLayout,
    /// …)` (MermaidRender/DiagramRenderer+MethodDiagrams.swift). It emits, in the
    /// same painter's order: swimlane bands (odd lanes get a faint fill) with a
    /// hairline border and a left-anchored lane name, elbow connectors between
    /// consecutive timeframes (each ending in an arrowhead), then per-kind tinted
    /// event/command/view cards with their entity label centered.
    ///
    /// Cards are flat categorical tints (no gradient) and connectors are straight
    /// polylines whose head geometry matches `drawArrowhead`, so nothing is
    /// approximated. Any change to the drawn event-modeling appearance must land
    /// in both.
    public static func from(_ layout: EventModelingLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // 1. Swimlane bands.
        for (index, lane) in layout.lanes.enumerated() {
            elements.append(.shape(Shape(
                path: .roundedRect(lane.band, radius: 0),
                fill: index % 2 == 1 ? theme.hairline.withAlpha(0.05) : nil,
                stroke: Stroke(color: theme.hairline, width: 1))))
            elements.append(.text(leftText(
                lane.name, at: CGPoint(x: lane.band.minX + 6, y: lane.band.minY + 10),
                fontSize: 9, weight: .semibold, color: theme.tertiaryText, measure: measure)))
        }

        // 2. Elbow connectors between consecutive timeframes.
        let connectorColor = theme.secondaryText.withAlpha(0.6)
        for connector in layout.connectors where connector.count >= 2 {
            elements.append(.polyline(Polyline(
                points: connector, stroke: Stroke(color: connectorColor, width: 1.2),
                endArrow: true)))
        }

        // 3. Per-kind tinted cards.
        for frame in layout.frames {
            let tint = theme.categoricalColor(frame.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(frame.frame, radius: 4),
                fill: tint.withAlpha(0.22), stroke: Stroke(color: tint, width: 1.2))))
            elements.append(.text(Text(
                string: frame.entity,
                center: CGPoint(x: frame.frame.midX, y: frame.frame.midY),
                fontSize: 10.5, color: theme.ink)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
