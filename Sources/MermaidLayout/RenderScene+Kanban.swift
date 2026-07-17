import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `KanbanLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: KanbanLayout, …)`
    /// (MermaidRender/DiagramRenderer+Kanban.swift). It emits, in the same
    /// painter's order: tinted column-header pills with centered titles, then
    /// per card a subtle body, a colored left accent rail, the pre-wrapped text
    /// lines, and an optional ticket chip. Kanban draws no diagram title. All
    /// colors are flat; nothing is approximated.
    public static func from(_ layout: KanbanLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // Column headers: tinted pill with the column title.
        for column in layout.columns {
            let tint = theme.categoricalColor(column.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(column.headerFrame, radius: 6),
                fill: tint.withAlpha(0.22), stroke: nil)))
            if !column.title.isEmpty {
                elements.append(.text(Text(
                    string: column.title,
                    center: CGPoint(x: column.headerFrame.midX, y: column.headerFrame.midY + 1),
                    fontSize: 11.5, weight: .semibold, color: theme.ink)))
            }
        }

        // Cards: subtle body, colored left rail, wrapped text, optional ticket.
        for card in layout.cards {
            let tint = theme.categoricalColor(card.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(card.frame, radius: 6),
                fill: theme.ink.withAlpha(0.05), stroke: nil)))
            // Left accent rail.
            elements.append(.shape(Shape(
                path: .roundedRect(CGRect(x: card.frame.minX, y: card.frame.minY + 4,
                                          width: 3, height: card.frame.height - 8), radius: 0),
                fill: tint.withAlpha(0.85), stroke: nil)))

            var textY = card.frame.minY + 9 + 7
            for line in card.lines {
                if !line.isEmpty {
                    elements.append(.text(leftText(
                        line, at: CGPoint(x: card.frame.minX + 12, y: textY),
                        fontSize: 11, color: theme.ink, measure: measure)))
                }
                textY += 15
            }
            if let ticket = card.ticket, !ticket.isEmpty {
                elements.append(.text(leftText(
                    ticket, at: CGPoint(x: card.frame.minX + 12, y: card.frame.maxY - 9),
                    fontSize: 8.5, weight: .medium, color: theme.tertiaryText, measure: measure)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
