import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a treemap to the common scene IR: leaf cells are plain nodes,
    /// internal group rects are containers, and ids are disambiguated by
    /// depth and position. No edges and no free-standing labels.
    static func from(_ layout: TreemapLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        DiagramScene(
            name: "treemap",
            size: layout.size,
            // One Node per cell. Internal group rects (isLeaf == false) legitimately
            // contain their children, so they are containers and exempt from overlap
            // checks; leaves are ordinary nodes. IDs are disambiguated by depth +
            // position because sibling branches can reuse a label.
            nodes: layout.cells.map { cell in
                Node(
                    id: "\(cell.label)#d\(cell.depth)@\(Int(cell.frame.minX)),\(Int(cell.frame.minY))",
                    frame: cell.frame,
                    isContainer: !cell.isLeaf
                )
            },
            // Treemaps have no connectors.
            edges: [],
            // Leaf labels are centred inside their own rects (implicit in the
            // Node), but GROUP HEADERS are drawn left-anchored at the top of
            // container cells — free-standing text the linter must see
            // (mirrors the renderer's roominess + fits-width guards).
            labels: layout.cells.compactMap { cell in
                guard !cell.isLeaf, cell.frame.height > 44, cell.frame.width > 40 else { return nil }
                let width = measuredLabelSize(measure, cell.label).width
                guard width <= cell.frame.width - 12 else { return nil }
                return Label(
                    text: cell.label,
                    frame: CGRect(x: cell.frame.minX + 6, y: cell.frame.minY + 3,
                                  width: width, height: 14))
            }
        )
    }
}
