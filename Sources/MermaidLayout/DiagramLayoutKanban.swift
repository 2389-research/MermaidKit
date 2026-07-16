import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a kanban board: columns side by side, each a tinted header
    /// over a vertical stack of cards. Card text word-wraps to the column
    /// width (capped) so long items stay readable. Pure geometry.
    public static func layout(_ board: KanbanBoard, measure: DiagramTextMeasurer) -> KanbanLayout {
        let margin: CGFloat = 14
        let columnWidth: CGFloat = 172
        let columnGap: CGFloat = 12
        let headerHeight: CGFloat = 30
        let cardGap: CGFloat = 8
        let cardPadding: CGFloat = 9
        let lineHeight: CGFloat = 15
        let ticketHeight: CGFloat = 14
        let maxLines = 4
        let textWidth = columnWidth - cardPadding * 2

        // Greedy word-wrap, capped; the last kept line absorbs the remainder.
        func wrap(_ text: String) -> [String] {
            let words = text.split(separator: " ").map(String.init)
            guard !words.isEmpty else { return [text] }
            var lines: [String] = []
            var current = ""
            for word in words {
                let candidate = current.isEmpty ? word : current + " " + word
                if current.isEmpty || measure(candidate, nodeFontSize).width <= textWidth {
                    current = candidate
                } else {
                    lines.append(current)
                    current = word
                    if lines.count == maxLines - 1 { break }
                }
            }
            if !current.isEmpty { lines.append(current) }
            return lines.isEmpty ? [text] : lines
        }

        var columns: [KanbanLayout.Column] = []
        var cards: [KanbanLayout.Card] = []
        var maxColumnBottom: CGFloat = 0

        for (columnIndex, column) in board.columns.enumerated() {
            let x = margin + CGFloat(columnIndex) * (columnWidth + columnGap)
            columns.append(KanbanLayout.Column(
                title: column.title,
                headerFrame: CGRect(x: x, y: margin, width: columnWidth, height: headerHeight),
                colorIndex: columnIndex
            ))

            var y = margin + headerHeight + cardGap
            for card in column.cards {
                let lines = wrap(card.text)
                let cardHeight = cardPadding * 2 + CGFloat(lines.count) * lineHeight
                    + (card.ticket == nil ? 0 : ticketHeight)
                cards.append(KanbanLayout.Card(
                    lines: lines,
                    ticket: card.ticket,
                    frame: CGRect(x: x, y: y, width: columnWidth, height: cardHeight),
                    colorIndex: columnIndex
                ))
                y += cardHeight + cardGap
            }
            maxColumnBottom = max(maxColumnBottom, y)
        }

        let width = margin + CGFloat(board.columns.count) * (columnWidth + columnGap) - columnGap + margin
        return KanbanLayout(
            size: CGSize(width: width, height: maxColumnBottom + margin - cardGap),
            columns: columns,
            cards: cards
        )
    }
}
