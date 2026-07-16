import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for a `block-beta` diagram: a uniform grid of block frames plus
/// orthogonally-routed edges between their borders. Pure geometry — the
/// renderer only draws.
public struct BlockLayout: Sendable {
    /// A block with its grid-cell frame.
    public struct Node: Sendable {
        public let frame: CGRect
        public let label: String
        public let shape: BlockDiagram.Shape
        /// Palette index (by grid row) for a subtle categorical tint.
        public let colorIndex: Int
        /// Creates a placed block.
        public init(frame: CGRect, label: String, shape: BlockDiagram.Shape, colorIndex: Int) {
            self.frame = frame
            self.label = label
            self.shape = shape
            self.colorIndex = colorIndex
        }
    }

    /// A connection between two blocks.
    public struct Edge: Sendable {
        /// Border-to-border route; the arrowhead sits at the last point.
        public let points: [CGPoint]
        public let label: String?
        /// Creates a routed edge.
        public init(points: [CGPoint], label: String?) {
            self.points = points
            self.label = label
        }
    }

    public let size: CGSize
    public let nodes: [Node]
    public let edges: [Edge]

    /// Creates a block layout.
    public init(size: CGSize, nodes: [Node], edges: [Edge]) {
        self.size = size
        self.nodes = nodes
        self.edges = edges
    }
}

extension DiagramLayoutEngine {

    /// Lays out a `block-beta` diagram: blocks fill a uniform grid (the
    /// declared column count, clamped) in declaration order — `space` blocks
    /// leave their cell empty — and edges route orthogonally through the
    /// empty gap channels between cells so they never cross a non-endpoint
    /// block. Pure geometry — the renderer only draws.
    public static func layout(_ diagram: BlockDiagram, measure: DiagramTextMeasurer) -> BlockLayout {
        let margin: CGFloat = 18
        let gapX: CGFloat = 30
        let gapY: CGFloat = 42
        let cellHeight: CGFloat = 46

        let cols = min(max(1, diagram.columns), 12)

        // A uniform cell width sized to the widest label (clamped) keeps grid
        // centers regular so orthogonal edges align.
        var widest: CGFloat = 0
        for block in diagram.blocks where block.shape != .space {
            widest = max(widest, measure(block.label, nodeFontSize).width)
        }
        let cellWidth = min(max(widest + 30, 96), 220)

        let count = diagram.blocks.count
        let rows = max(1, Int((Double(count) / Double(cols)).rounded(.up)))

        func frame(atIndex i: Int) -> CGRect {
            let col = i % cols
            let row = i / cols
            return CGRect(
                x: margin + CGFloat(col) * (cellWidth + gapX),
                y: margin + CGFloat(row) * (cellHeight + gapY),
                width: cellWidth, height: cellHeight
            )
        }

        // Grid position (col/row) alongside the frame, so routing can travel
        // the empty gap channels rather than cutting straight through cells.
        struct Placed { let col: Int; let row: Int; let frame: CGRect }

        var nodes: [BlockLayout.Node] = []
        var placedByID: [String: Placed] = [:]
        for (i, block) in diagram.blocks.enumerated() {
            let f = frame(atIndex: i)
            if block.shape != .space {
                nodes.append(BlockLayout.Node(
                    frame: f, label: block.label, shape: block.shape, colorIndex: i / cols
                ))
                if placedByID[block.id] == nil {
                    placedByID[block.id] = Placed(col: i % cols, row: i / cols, frame: f)
                }
            }
        }

        let width = margin * 2 + CGFloat(cols) * cellWidth + CGFloat(cols - 1) * gapX
        let height = margin * 2 + CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gapY

        // Gap-channel centre lines. Every row-gap is a full-width band with no
        // nodes in it; every column-gap is a full-height band with no nodes.
        // Routing inside these bands can never cross a non-endpoint cell.
        func gapBelow(_ r: Int) -> CGFloat { margin + CGFloat(r) * (cellHeight + gapY) + cellHeight + gapY / 2 }
        func gapAbove(_ r: Int) -> CGFloat { margin + CGFloat(r) * (cellHeight + gapY) - gapY / 2 }
        func gapRight(_ c: Int) -> CGFloat { margin + CGFloat(c) * (cellWidth + gapX) + cellWidth + gapX / 2 }
        func gapLeft(_ c: Int) -> CGFloat { margin + CGFloat(c) * (cellWidth + gapX) - gapX / 2 }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, 4), height - 4) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, 4), width - 4) }

        // Orthogonal routing that stays inside the empty gap channels between
        // cells, so an edge never passes through a block that isn't its endpoint.
        func route(_ a: Placed, _ b: Placed) -> [CGPoint] {
            let af = a.frame, bf = b.frame
            let aCx = af.midX, aCy = af.midY
            let bCx = bf.midX, bCy = bf.midY

            // Same row.
            if a.row == b.row {
                if abs(a.col - b.col) == 1 {
                    return b.col > a.col
                        ? [CGPoint(x: af.maxX, y: aCy), CGPoint(x: bf.minX, y: bCy)]
                        : [CGPoint(x: af.minX, y: aCy), CGPoint(x: bf.maxX, y: bCy)]
                }
                // Non-adjacent: dip into an adjacent row-gap and run along it.
                let down = a.row < rows - 1
                let chan = clampY(down ? gapBelow(a.row) : gapAbove(a.row))
                let ay = down ? af.maxY : af.minY
                let by = down ? bf.maxY : bf.minY
                return [CGPoint(x: aCx, y: ay), CGPoint(x: aCx, y: chan),
                        CGPoint(x: bCx, y: chan), CGPoint(x: bCx, y: by)]
            }

            // Same column.
            if a.col == b.col {
                if abs(a.row - b.row) == 1 {
                    return b.row > a.row
                        ? [CGPoint(x: aCx, y: af.maxY), CGPoint(x: bCx, y: bf.minY)]
                        : [CGPoint(x: aCx, y: af.minY), CGPoint(x: bCx, y: bf.maxY)]
                }
                // Non-adjacent: step out into an adjacent column-gap and run down it.
                let right = a.col < cols - 1
                let chan = clampX(right ? gapRight(a.col) : gapLeft(a.col))
                let ax = right ? af.maxX : af.minX
                let bx = right ? bf.maxX : bf.minX
                return [CGPoint(x: ax, y: aCy), CGPoint(x: chan, y: aCy),
                        CGPoint(x: chan, y: bCy), CGPoint(x: bx, y: bCy)]
            }

            // Different row and column.
            let down = b.row > a.row
            let ay = down ? af.maxY : af.minY
            let by = down ? bf.minY : bf.maxY

            // Adjacent rows: one L through the shared row-gap.
            if abs(a.row - b.row) == 1 {
                let chan = clampY(down ? gapBelow(a.row) : gapAbove(a.row))
                return [CGPoint(x: aCx, y: ay), CGPoint(x: aCx, y: chan),
                        CGPoint(x: bCx, y: chan), CGPoint(x: bCx, y: by)]
            }

            // Rows more than one apart: exit A into its adjacent row-gap, cross
            // to a column-gap beside B, drop down that column-gap to B's
            // adjacent row-gap, then step into B — every leg lives in a gap.
            let chanA = clampY(down ? gapBelow(a.row) : gapAbove(a.row))
            let chanB = clampY(down ? gapAbove(b.row) : gapBelow(b.row))
            let vchan: CGFloat = b.col > a.col ? clampX(gapLeft(b.col))
                : b.col < a.col ? clampX(gapRight(b.col))
                : clampX(b.col < cols - 1 ? gapRight(b.col) : gapLeft(b.col))
            return [CGPoint(x: aCx, y: ay), CGPoint(x: aCx, y: chanA),
                    CGPoint(x: vchan, y: chanA), CGPoint(x: vchan, y: chanB),
                    CGPoint(x: bCx, y: chanB), CGPoint(x: bCx, y: by)]
        }

        var edges: [BlockLayout.Edge] = []
        for edge in diagram.edges {
            guard let a = placedByID[edge.from], let b = placedByID[edge.to] else { continue }
            edges.append(BlockLayout.Edge(points: route(a, b), label: edge.label))
        }

        return BlockLayout(
            size: CGSize(width: min(max(width, 120), 3800),
                         height: min(max(height, 80), 3800)),
            nodes: nodes,
            edges: edges
        )
    }
}
