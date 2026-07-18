import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `ZenUMLLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: ZenUMLLayout, …)`
    /// (MermaidRender/DiagramRenderer+ZenUML.swift), a close cousin of the
    /// sequence lowering. It emits, in the same painter's order: an optional
    /// centered title, dashed lifelines dropping from each participant, message
    /// arrows (straight, or a rectangular self-call loop) with a filled head and
    /// caption, then the participant boxes on top so the lifelines/arrows tuck
    /// under them — each box a categorical tint with a stereotype line above the
    /// name when present.
    ///
    /// The CG self-loop routes its final leg to `fromX + 5` and paints a separate
    /// arrowhead tip at `fromX`; here the shaft polyline runs the full width and
    /// its `endArrow` realizes the head, sparing the 5pt stub — the tip lands at
    /// the same point with the same leftward direction. The dashed lifeline's
    /// 3,3 dots read through the fixed "4 3" pattern (as in the sequence twin).
    /// Any change to the drawn ZenUML appearance must land in both.
    public static func from(_ layout: ZenUMLLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // 1. Optional centered title.
        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // 2. Dashed lifelines dropping from each participant box.
        for p in layout.participants {
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: p.centerX, y: p.lifelineTop),
                         CGPoint(x: p.centerX, y: p.lifelineBottom)],
                stroke: Stroke(color: theme.hairline, width: 1, dashed: true))))
        }

        // 3. Message arrows, stacked top to bottom.
        let shaft = theme.ink.withAlpha(0.55)
        for arrow in layout.arrows {
            if arrow.isSelf {
                let yTop = arrow.y, yBot = arrow.y + arrow.selfHeight
                elements.append(.polyline(Polyline(points: [
                    CGPoint(x: arrow.fromX, y: yTop), CGPoint(x: arrow.toX, y: yTop),
                    CGPoint(x: arrow.toX, y: yBot), CGPoint(x: arrow.fromX, y: yBot),
                ], stroke: Stroke(color: shaft, width: 1.3), endArrow: true)))
                if !arrow.label.isEmpty {
                    elements.append(.text(leftText(
                        arrow.label,
                        at: CGPoint(x: arrow.toX + 6, y: (yTop + yBot) / 2),
                        fontSize: 10, color: theme.secondaryText, measure: measure)))
                }
            } else {
                elements.append(.polyline(Polyline(points: [
                    CGPoint(x: arrow.fromX, y: arrow.y), CGPoint(x: arrow.toX, y: arrow.y),
                ], stroke: Stroke(color: shaft, width: 1.3), endArrow: true)))
                if !arrow.label.isEmpty {
                    elements.append(.text(Text(
                        string: arrow.label,
                        center: CGPoint(x: (arrow.fromX + arrow.toX) / 2, y: arrow.y - 9),
                        fontSize: 10.5, color: theme.secondaryText, backing: theme.canvas)))
                }
            }
        }

        // 4. Participant boxes on top.
        for p in layout.participants {
            let color = theme.categoricalColor(p.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(p.frame, radius: 6),
                fill: color.withAlpha(0.14), stroke: Stroke(color: color.withAlpha(0.6), width: 1))))
            if let s = p.stereotype {
                elements.append(.text(Text(
                    string: s, center: CGPoint(x: p.frame.midX, y: p.frame.minY + 12),
                    fontSize: 8.5, color: theme.tertiaryText)))
                elements.append(.text(Text(
                    string: p.name, center: CGPoint(x: p.frame.midX, y: p.frame.minY + 25),
                    fontSize: 12, weight: .medium, color: theme.ink)))
            } else {
                elements.append(.text(Text(
                    string: p.name, center: CGPoint(x: p.frame.midX, y: p.frame.midY),
                    fontSize: 12, weight: .medium, color: theme.ink)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
