import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `CynefinLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: CynefinLayout, …)`
    /// (MermaidRender/DiagramRenderer+NewTypes.swift). It emits, in the same
    /// painter's order: an optional title, four tinted quadrant fills with a
    /// hairline border, a domain name + heuristic + item dots' text per quadrant,
    /// the optional central "confusion" disk, then accent transition arrows with
    /// chipped labels.
    ///
    /// Fills are flat categorical tints (no gradient) and arrows lower to
    /// `endArrow` polylines whose head geometry matches `drawArrowhead`, so
    /// nothing is approximated. Any change to the drawn cynefin appearance must
    /// land in both.
    public static func from(_ layout: CynefinLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 16),
                fontSize: 13, weight: .semibold, color: theme.ink)))
        }

        for quadrant in layout.quadrants {
            let tint = theme.categoricalColor(quadrant.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(quadrant.frame, radius: 0),
                fill: tint.withAlpha(0.14), stroke: Stroke(color: theme.hairline, width: 1))))
            elements.append(.text(Text(
                string: quadrant.name,
                center: CGPoint(x: quadrant.frame.midX, y: quadrant.frame.minY + 18),
                fontSize: 12, weight: .semibold, color: theme.ink)))
            elements.append(.text(Text(
                string: quadrant.heuristic,
                center: CGPoint(x: quadrant.frame.midX, y: quadrant.frame.minY + 34),
                fontSize: 9, color: theme.tertiaryText)))
            for item in quadrant.items {
                elements.append(.text(Text(
                    string: item.text, center: item.center,
                    fontSize: 10.5, color: theme.secondaryText)))
            }
        }

        if let center = layout.center {
            elements.append(.shape(Shape(
                path: .ellipse(center.frame), fill: theme.canvas,
                stroke: Stroke(color: theme.ink.withAlpha(0.5), width: 1.2))))
            elements.append(.text(Text(
                string: center.name,
                center: CGPoint(x: center.frame.midX, y: center.frame.midY - 10),
                fontSize: 11, weight: .semibold, color: theme.ink)))
            elements.append(.text(Text(
                string: center.heuristic,
                center: CGPoint(x: center.frame.midX, y: center.frame.midY + 5),
                fontSize: 8.5, color: theme.tertiaryText)))
            for item in center.items {
                elements.append(.text(Text(
                    string: item.text, center: item.center,
                    fontSize: 8.5, color: theme.secondaryText)))
            }
        }

        for transition in layout.transitions {
            elements.append(.polyline(Polyline(
                points: [transition.from, transition.to],
                stroke: Stroke(color: theme.accent, width: 1.4), endArrow: true)))
            if let label = transition.label {
                elements.append(labelChip(label, center: transition.labelCenter,
                                          weight: .regular, color: theme.secondaryText, theme: theme))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
