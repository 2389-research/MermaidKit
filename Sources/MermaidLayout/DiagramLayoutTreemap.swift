import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a treemap with the squarified algorithm (Bruls et al.):
    /// children fill their parent's rectangle in rows chosen to keep cells as
    /// square as possible, recursing into each internal node. Leaves are tinted
    /// by their top-level branch. Pure geometry — the renderer only draws.
    public static func layout(_ treemap: Treemap, measure: DiagramTextMeasurer) -> TreemapLayout {
        let margin: CGFloat = 14
        let boardWidth: CGFloat = 540
        let boardHeight: CGFloat = 340
        let headerHeight: CGFloat = 16
        let gap: CGFloat = 2

        var cells: [TreemapLayout.Cell] = []

        func place(_ node: TreemapNode, in rect: CGRect, colorIndex: Int, depth: Int) {
            guard rect.width > 1, rect.height > 1 else { return }
            if node.children.isEmpty {
                cells.append(TreemapLayout.Cell(label: node.label, value: node.value,
                                                frame: rect, colorIndex: colorIndex, isLeaf: true, depth: depth))
                return
            }
            // Group rect (drawn as an outline + header behind its children).
            cells.append(TreemapLayout.Cell(label: node.label, value: node.value,
                                            frame: rect, colorIndex: colorIndex, isLeaf: false, depth: depth))
            let inner = rect.insetBy(dx: gap, dy: gap)
            let reserve: CGFloat = inner.height > 44 ? headerHeight : 0
            let content = CGRect(x: inner.minX, y: inner.minY + reserve,
                                 width: inner.width, height: inner.height - reserve)
            for (child, childRect) in squarify(node.children, in: content) {
                place(child, in: childRect, colorIndex: colorIndex, depth: depth + 1)
            }
        }

        let board = CGRect(x: margin, y: margin, width: boardWidth, height: boardHeight)
        if treemap.root.children.isEmpty {
            place(treemap.root, in: board, colorIndex: 0, depth: 0)
        } else {
            for (index, (child, rect)) in squarify(treemap.root.children, in: board).enumerated() {
                place(child, in: rect, colorIndex: index, depth: 1)
            }
        }

        return TreemapLayout(
            size: CGSize(width: boardWidth + margin * 2, height: boardHeight + margin * 2),
            cells: cells
        )
    }

    /// Squarified placement of `nodes` (by value) filling `rect`.
    static func squarify(_ nodes: [TreemapNode], in rect: CGRect) -> [(TreemapNode, CGRect)] {
        let total = nodes.map(\.value).reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return nodes.map { ($0, .zero) } }
        let scale = Double(rect.width * rect.height) / total   // value → pixel area

        var remaining = nodes.sorted { $0.value > $1.value }.map { ($0, $0.value * scale) }
        var result: [(TreemapNode, CGRect)] = []
        var r = rect

        func worst(_ areas: [Double], side: Double) -> Double {
            let s = areas.reduce(0, +)
            guard s > 0, let mx = areas.max(), let mn = areas.min(), mn > 0, side > 0 else { return .infinity }
            return Swift.max(side * side * mx / (s * s), s * s / (side * side * mn))
        }

        while !remaining.isEmpty {
            let side = Double(Swift.min(r.width, r.height))
            var row = [remaining[0]]
            var i = 1
            while i < remaining.count,
                  worst((row + [remaining[i]]).map(\.1), side: side) <= worst(row.map(\.1), side: side) {
                row.append(remaining[i]); i += 1
            }
            let rowArea = row.map(\.1).reduce(0, +)
            if r.width >= r.height {
                let stripWidth = CGFloat(rowArea / Double(r.height))
                var y = r.minY
                for (node, area) in row {
                    let h = CGFloat(area / rowArea) * r.height
                    result.append((node, CGRect(x: r.minX, y: y, width: stripWidth, height: h)))
                    y += h
                }
                r = CGRect(x: r.minX + stripWidth, y: r.minY, width: r.width - stripWidth, height: r.height)
            } else {
                let stripHeight = CGFloat(rowArea / Double(r.width))
                var x = r.minX
                for (node, area) in row {
                    let w = CGFloat(area / rowArea) * r.width
                    result.append((node, CGRect(x: x, y: r.minY, width: w, height: stripHeight)))
                    x += w
                }
                r = CGRect(x: r.minX, y: r.minY + stripHeight, width: r.width, height: r.height - stripHeight)
            }
            remaining.removeFirst(row.count)
        }
        return result
    }
}
