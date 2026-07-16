import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for a requirement diagram: labelled boxes (requirements show their
/// stereotype, name, id, wrapped text, risk, and verify method; elements show
/// their type and doc reference) placed in a simple grid, with straight
/// verb-labelled connectors between related boxes. Pure geometry — the renderer
/// only draws.
public struct RequirementLayout: Sendable {

    /// A requirement or element box.
    public struct Box: Sendable {
        public let frame: CGRect
        /// Stereotype line, e.g. "«requirement»" or "«element»".
        public let stereotype: String
        public let name: String
        /// Pre-wrapped detail rows drawn under the name separator.
        public let detailLines: [String]
        public let isElement: Bool
        public let colorIndex: Int
    }

    /// A relation connector, labelled with its verb (e.g. "satisfies").
    public struct Edge: Sendable {
        /// The routed orthogonal polyline, source-box edge to dest-box edge,
        /// threaded through the empty channels between node rows/columns so it
        /// never crosses a non-endpoint box.
        public let points: [CGPoint]
        public let label: String
        /// First route point, on the source box's edge.
        public var from: CGPoint { points.first ?? .zero }
        /// Last route point, on the dest box's edge.
        public var to: CGPoint { points.last ?? .zero }
    }

    public let size: CGSize
    public let boxes: [Box]
    public let edges: [Edge]
}

extension DiagramLayoutEngine {

    /// Lays out a requirement diagram: requirement then element boxes in a
    /// grid of at most three columns, relations routed through the clear
    /// row/column gutters with the relation verb as the edge label. Pure
    /// geometry — the renderer only draws.
    public static func layout(_ diagram: RequirementDiagram, measure: DiagramTextMeasurer) -> RequirementLayout {
        let margin: CGFloat = 16
        let boxWidth: CGFloat = 204
        let hGap: CGFloat = 40
        let vGap: CGFloat = 44
        let padding: CGFloat = 11
        let stereoH: CGFloat = 14
        let nameH: CGFloat = 20
        let sepGap: CGFloat = 8
        let lineH: CGFloat = 15
        let textWidth = boxWidth - padding * 2

        // Greedy word-wrap of a detail value, capped at `maxLines`.
        func wrap(_ text: String, maxLines: Int) -> [String] {
            let words = text.split(separator: " ").map(String.init)
            guard !words.isEmpty else { return [] }
            var lines: [String] = []
            var current = ""
            for word in words {
                let candidate = current.isEmpty ? word : current + " " + word
                if current.isEmpty || measure(candidate, labelFontSize).width <= textWidth {
                    current = candidate
                } else {
                    lines.append(current)
                    current = word
                    if lines.count == maxLines - 1 { break }
                }
            }
            if !current.isEmpty { lines.append(current) }
            return lines
        }

        // Build the drawable content (stereotype/name/detail rows) for every
        // requirement and element, in a stable order (requirements first).
        struct Content {
            let name: String
            let stereotype: String
            let details: [String]
            let isElement: Bool
            let colorIndex: Int
        }
        var contents: [Content] = []

        for req in diagram.requirements {
            var details: [String] = []
            if let id = req.id { details.append("id: \(id)") }
            if let text = req.text { details.append(contentsOf: wrap(text, maxLines: 3)) }
            if let risk = req.risk { details.append("risk: \(risk)") }
            if let verify = req.verifyMethod { details.append("verify: \(verify)") }
            let colorIndex = [RequirementDiagram.Kind.requirement, .functional, .performance,
                              .interface, .physical, .designConstraint]
                .firstIndex(of: req.kind) ?? 0
            contents.append(Content(name: req.name, stereotype: "«\(req.kind.rawValue)»",
                                    details: details, isElement: false, colorIndex: colorIndex))
        }
        for element in diagram.elements {
            var details: [String] = []
            if let type = element.type { details.append("type: \(type)") }
            if let docRef = element.docRef { details.append(contentsOf: wrap("ref: \(docRef)", maxLines: 2)) }
            contents.append(Content(name: element.name, stereotype: "«element»",
                                    details: details, isElement: true, colorIndex: 7))
        }

        func boxHeight(_ detailCount: Int) -> CGFloat {
            padding + stereoH + nameH + sepGap + CGFloat(detailCount) * lineH + padding
        }

        // Grid: at most three columns, wrapping in content order.
        let count = contents.count
        let columns = max(1, count <= 1 ? 1 : (count <= 4 ? 2 : 3))

        // Grid position of every box, so edges can be routed through the empty
        // channels (the hGap columns and vGap rows) rather than straight lines.
        struct Slot { let row: Int; let col: Int; let frame: CGRect }
        var boxes: [RequirementLayout.Box] = []
        var slotByName: [String: Slot] = [:]
        var rowTops: [CGFloat] = []
        var rowHeights: [CGFloat] = []
        var y = margin
        var row = 0
        while row * columns < count {
            let start = row * columns
            let end = min(start + columns, count)
            let rowHeight = (start..<end).map { boxHeight(contents[$0].details.count) }.max() ?? 0
            rowTops.append(y)
            rowHeights.append(rowHeight)
            for i in start..<end {
                let col = i - start
                let x = margin + CGFloat(col) * (boxWidth + hGap)
                let frame = CGRect(x: x, y: y, width: boxWidth, height: rowHeight)
                let c = contents[i]
                boxes.append(RequirementLayout.Box(
                    frame: frame, stereotype: c.stereotype, name: c.name,
                    detailLines: c.details, isElement: c.isElement, colorIndex: c.colorIndex))
                slotByName[c.name] = Slot(row: row, col: col, frame: frame)
            }
            y += rowHeight + vGap
            row += 1
        }
        let rowCount = row

        // A vertical line at a column boundary is clear for the full canvas
        // height (every row leaves the same hGap between columns); a horizontal
        // line at a row boundary is clear for the full width. Edges hop between
        // these channels so they never cross a box.
        func columnGapX(after col: Int) -> CGFloat {
            // Centre of the hGap to the right of `col` (valid for 0..<columns-1).
            margin + CGFloat(col) * (boxWidth + hGap) + boxWidth + hGap / 2
        }
        let leftMarginX = margin / 2
        func gutterAbove(_ r: Int) -> CGFloat {
            r == 0 ? margin / 2 : rowTops[r - 1] + rowHeights[r - 1] + vGap / 2
        }
        func gutterBelow(_ r: Int) -> CGFloat {
            r == rowCount - 1 ? rowTops[r] + rowHeights[r] + margin / 2
                              : rowTops[r] + rowHeights[r] + vGap / 2
        }

        // A clear vertical channel x sitting to one side of both columns.
        func channelX(between colA: Int, and colB: Int) -> CGFloat {
            if colA != colB { return columnGapX(after: min(colA, colB)) }
            if colA < columns - 1 { return columnGapX(after: colA) }
            if colA > 0 { return columnGapX(after: colA - 1) }
            return leftMarginX
        }

        func route(_ s: Slot, _ d: Slot) -> [CGPoint] {
            let sx = s.frame.midX, dx = d.frame.midX

            // Same row: run along the shared gutter above the row.
            if s.row == d.row {
                let g = gutterAbove(s.row)
                return [CGPoint(x: sx, y: s.frame.minY), CGPoint(x: sx, y: g),
                        CGPoint(x: dx, y: g), CGPoint(x: dx, y: d.frame.minY)]
            }

            // Same column, adjacent rows: the gap between them is clear — go
            // straight down/up through it.
            if s.col == d.col && abs(s.row - d.row) == 1 {
                if d.row > s.row {
                    return [CGPoint(x: sx, y: s.frame.maxY), CGPoint(x: dx, y: d.frame.minY)]
                }
                return [CGPoint(x: sx, y: s.frame.minY), CGPoint(x: dx, y: d.frame.maxY)]
            }

            // General case: exit toward the dest, cross the width along the
            // source gutter, drop/rise through a clear column channel, then run
            // the dest gutter in to the dest box.
            let down = d.row > s.row
            let sEdgeY = down ? s.frame.maxY : s.frame.minY
            let dEdgeY = down ? d.frame.minY : d.frame.maxY
            let sGut = down ? gutterBelow(s.row) : gutterAbove(s.row)
            let dGut = down ? gutterAbove(d.row) : gutterBelow(d.row)
            let cx = channelX(between: s.col, and: d.col)
            return [CGPoint(x: sx, y: sEdgeY), CGPoint(x: sx, y: sGut),
                    CGPoint(x: cx, y: sGut), CGPoint(x: cx, y: dGut),
                    CGPoint(x: dx, y: dGut), CGPoint(x: dx, y: dEdgeY)]
        }

        var edges: [RequirementLayout.Edge] = []
        for relation in diagram.relations {
            guard let s = slotByName[relation.source],
                  let d = slotByName[relation.dest] else { continue }
            edges.append(RequirementLayout.Edge(points: route(s, d), label: relation.kind.rawValue))
        }

        let usedColumns = min(columns, max(count, 1))
        let width = margin + CGFloat(usedColumns) * boxWidth + CGFloat(usedColumns - 1) * hGap + margin
        let height = max(y - vGap + margin, margin * 2 + 1)
        return RequirementLayout(
            size: CGSize(width: min(width, 3990), height: min(height, 3990)),
            boxes: boxes,
            edges: edges)
    }
}
