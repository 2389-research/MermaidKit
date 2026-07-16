import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a mindmap as a tidy horizontal tree: the root at the left,
    /// depth increasing rightward, siblings stacked vertically. Leaves pack
    /// top-to-bottom and each parent centers on the span of its children
    /// (the classic Reingold–Tilford first pass). Each top-level branch keeps
    /// its own tint. Pure geometry — the renderer only draws.
    public static func layout(_ mindmap: Mindmap, measure: DiagramTextMeasurer) -> MindmapLayout {
        let margin: CGFloat = 14
        let nodeHeight: CGFloat = 26
        let vGap: CGFloat = 10          // between stacked leaves
        let hGap: CGFloat = 34          // between depth columns
        let pad: CGFloat = 12           // text inset inside a node

        // Flatten the tree into an indexed array so y-assignment and edge
        // building can reference nodes by index. Preorder, so a parent always
        // precedes its children.
        struct Item {
            let label: String
            let depth: Int
            let parent: Int?
            var children: [Int]
            let colorIndex: Int
            let width: CGFloat
            var centerY: CGFloat
        }
        var items: [Item] = []

        func nodeWidth(_ label: String) -> CGFloat {
            min(max(measure(label, nodeFontSize).width + pad * 2, 44), 240)
        }

        @discardableResult
        func build(_ node: MindmapNode, depth: Int, parent: Int?, branch: Int) -> Int {
            let index = items.count
            items.append(Item(label: node.label, depth: depth, parent: parent,
                              children: [], colorIndex: branch,
                              width: nodeWidth(node.label), centerY: 0))
            var childIndices: [Int] = []
            for (childOrder, child) in node.children.enumerated() {
                // Depth-1 nodes seed the branches; deeper nodes inherit.
                let childBranch = depth == 0 ? childOrder : branch
                childIndices.append(build(child, depth: depth + 1, parent: index, branch: childBranch))
            }
            items[index].children = childIndices
            return index
        }
        build(mindmap.root, depth: 0, parent: nil, branch: 0)

        // Column x per depth: each column right of the widest node in the one
        // before it, so nodes never overlap their parents.
        let maxDepth = items.map(\.depth).max() ?? 0
        var maxWidthAtDepth = [CGFloat](repeating: 0, count: maxDepth + 1)
        for item in items { maxWidthAtDepth[item.depth] = max(maxWidthAtDepth[item.depth], item.width) }
        var columnX = [CGFloat](repeating: margin, count: maxDepth + 1)
        if maxDepth >= 1 {
            for depth in 1...maxDepth {
                columnX[depth] = columnX[depth - 1] + maxWidthAtDepth[depth - 1] + hGap
            }
        }

        // Vertical placement: leaves pack downward; each parent centers on the
        // midpoint of its first and last child.
        var nextLeafY = margin
        func assignY(_ index: Int) -> CGFloat {
            if items[index].children.isEmpty {
                let y = nextLeafY + nodeHeight / 2
                nextLeafY += nodeHeight + vGap
                items[index].centerY = y
                return y
            }
            let childCenters = items[index].children.map { assignY($0) }
            let center = (childCenters.first! + childCenters.last!) / 2
            items[index].centerY = center
            return center
        }
        _ = assignY(0)

        var nodes: [MindmapLayout.Node] = []
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for item in items {
            let frame = CGRect(x: columnX[item.depth], y: item.centerY - nodeHeight / 2,
                               width: item.width, height: nodeHeight)
            nodes.append(MindmapLayout.Node(label: item.label, frame: frame,
                                            depth: item.depth, colorIndex: item.colorIndex))
            maxX = max(maxX, frame.maxX)
            maxY = max(maxY, frame.maxY)
        }

        var edges: [MindmapLayout.Edge] = []
        for (index, item) in items.enumerated() {
            guard let parent = item.parent else { continue }
            let parentFrame = nodes[parent].frame
            let childFrame = nodes[index].frame
            edges.append(MindmapLayout.Edge(
                from: CGPoint(x: parentFrame.maxX, y: parentFrame.midY),
                to: CGPoint(x: childFrame.minX, y: childFrame.midY),
                colorIndex: item.colorIndex
            ))
        }

        return MindmapLayout(
            size: CGSize(width: maxX + margin, height: maxY + margin),
            nodes: nodes,
            edges: edges
        )
    }
}
