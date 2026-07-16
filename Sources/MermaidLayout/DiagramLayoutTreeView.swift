import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Laid-out tree view: one row per node with glyph/text positions, plus the
/// elbow connector polylines that draw the tree structure.
public struct TreeViewLayout: Sendable {
    public struct Row: Sendable {
        public let label: String
        public let description: String?
        public let isDirectory: Bool
        public let depth: Int
        /// The folder/file glyph box.
        public let glyphFrame: CGRect
        /// Left-anchored label origin (text midline at glyph center).
        public let textOrigin: CGPoint
        /// Origin for the muted description, after the label (nil when none).
        public let descriptionOrigin: CGPoint?
        /// Row bounds (glyph through last text), for hit-testing and lint.
        public let frame: CGRect
    }
    public let size: CGSize
    public let rows: [Row]
    /// Tree guide lines (vertical drop + horizontal stub per child).
    public let connectors: [[CGPoint]]
}

extension DiagramLayoutEngine {
    /// Lays out a tree view as a vertical list: y advances one row per node
    /// (depth-first), x indents per level, and each child gets an elbow
    /// connector from its parent's glyph column.
    public static func layout(_ tree: TreeViewDiagram, measure: DiagramTextMeasurer) -> TreeViewLayout {
        let margin: CGFloat = 14
        let rowHeight: CGFloat = 22
        let indent: CGFloat = 20
        let glyph: CGFloat = 13

        var rows: [TreeViewLayout.Row] = []
        var connectors: [[CGPoint]] = []
        var rowIndex = 0
        var maxRight: CGFloat = 0

        func place(_ node: TreeViewNode, depth: Int) -> Int {
            let myRow = rowIndex
            rowIndex += 1
            let x = margin + CGFloat(depth) * indent
            let midY = margin + CGFloat(myRow) * rowHeight + rowHeight / 2
            let glyphFrame = CGRect(x: x, y: midY - glyph / 2, width: glyph, height: glyph)
            let labelSize = measure(node.label, nodeFontSize)
            let textOrigin = CGPoint(x: glyphFrame.maxX + 6, y: midY)
            var descOrigin: CGPoint?
            var right = textOrigin.x + labelSize.width
            if let description = node.description {
                descOrigin = CGPoint(x: right + 8, y: midY)
                right += 8 + measure(description, labelFontSize).width
            }
            maxRight = max(maxRight, right)
            rows.append(.init(
                label: node.label, description: node.description,
                isDirectory: node.isDirectory, depth: depth,
                glyphFrame: glyphFrame, textOrigin: textOrigin,
                descriptionOrigin: descOrigin,
                frame: CGRect(x: x, y: midY - rowHeight / 2,
                              width: right - x, height: rowHeight)))

            let childColumnX = glyphFrame.midX
            var childMids: [CGFloat] = []
            for child in node.children {
                let childRow = place(child, depth: depth + 1)
                childMids.append(margin + CGFloat(childRow) * rowHeight + rowHeight / 2)
            }
            if let lastMid = childMids.last {
                // ONE vertical drop per parent (to the last child's row), plus
                // one horizontal stub per child — emitting a full elbow per
                // child would stack collinear verticals the linter counts as
                // crossings, and overdraws the same pixels.
                connectors.append([
                    CGPoint(x: childColumnX, y: glyphFrame.maxY + 1),
                    CGPoint(x: childColumnX, y: lastMid),
                ])
                for childMid in childMids {
                    connectors.append([
                        CGPoint(x: childColumnX, y: childMid),
                        CGPoint(x: childColumnX + indent - glyph / 2 - 2, y: childMid),
                    ])
                }
            }
            return myRow
        }
        for root in tree.roots { _ = place(root, depth: 0) }

        return TreeViewLayout(
            size: CGSize(width: maxRight + margin,
                         height: margin * 2 + CGFloat(rowIndex) * rowHeight),
            rows: rows, connectors: connectors)
    }
}
