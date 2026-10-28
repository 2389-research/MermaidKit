import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Subgraphs laid out with their parent's nodes (#103).
///
/// A subgraph is usually one box in one row of its parent
/// (`layoutClustered`). When that would send an edge on no cycle back up, the
/// cluster wrapper unfolds it instead: its members join the parent's layout,
/// and its box spans the rows they take, as dagre's compound layout does. This
/// file is the geometry that keeps such a box honest, in `layoutFlat`:
///
/// - **Borders.** The block gets a left and a right border node in every layer
///   from its top member's to its bottom member's, including layers with no
///   member, so ordering and placement see the box in every row it spans.
/// - **Ordering.** Each layer is ordered as a tree: a block's members, nested
///   blocks included, sit between its borders and everything else outside
///   them. Sibling blocks keep one order in every layer.
/// - **Clearing.** After cross coordinates, every left border of a block moves
///   to one line, every right border to another, and a single order-keeping
///   push restores every minimum gap. In each row a box spans, nothing outside
///   it lies between those lines.
/// - **Chrome.** The layer gaps above and below a box grow by its header and
///   padding, so it clears the rows outside it.
///
/// With no block, none of this runs, and `layoutFlat` is exactly what it was.
extension DiagramLayoutEngine {

    /// An unfolded subgraph, as `layoutFlat` lays it out.
    struct FlowBlock {
        let id: String
        let label: String
        /// The block it sits in, by index; nil for one directly in the scope.
        let parent: Int?
        /// The nodes and boxes directly in it (not in a nested block).
        let items: [String]
    }

    /// Where each block lies once layers are known.
    struct BlockPlan {
        let blocks: [FlowBlock]
        /// Innermost block of each item and long-edge stand-in.
        var blockOf: [String: Int] = [:]
        /// First and last layer of each block; nil for one with nothing laid out.
        var span: [(lo: Int, hi: Int)?] = []
        /// Each border node: its block, and whether it is the left one.
        var border: [String: (block: Int, left: Bool)] = [:]
        /// Nesting depth (0 = directly in the scope).
        var depth: [Int] = []

        func isAncestor(_ a: Int, of b: Int) -> Bool {
            var cur: Int? = b
            while let c = cur { if c == a { return true }; cur = blocks[c].parent }
            return false
        }
        /// The innermost block holding both, or nil.
        func common(_ a: Int?, _ b: Int?) -> Int? {
            guard var a, let b else { return nil }
            while !isAncestor(a, of: b) {
                guard let up = blocks[a].parent else { return nil }
                a = up
            }
            return a
        }
        func borderID(_ block: Int, _ layer: Int, left: Bool) -> String {
            "\u{a7}b\(left ? "l" : "r")\(block).\(layer)"
        }
    }

    /// Spans the blocks over `layerOf` and names their border nodes.
    static func planBlocks(_ blocks: [FlowBlock], layerOf: [String: Int]) -> BlockPlan {
        var plan = BlockPlan(blocks: blocks)
        plan.depth = blocks.indices.map { i in
            var d = 0, cur = blocks[i].parent
            while let c = cur { d += 1; cur = blocks[c].parent }
            return d
        }
        plan.span = Array(repeating: nil, count: blocks.count)
        for (b, block) in blocks.enumerated() {
            for item in block.items {
                plan.blockOf[item] = b
                guard let l = layerOf[item] else { continue }
                plan.span[b] = plan.span[b].map { (min($0.lo, l), max($0.hi, l)) } ?? (l, l)
            }
        }
        // A block spans its nested blocks too: deepest first, so each is
        // complete before its parent reads it.
        for b in blocks.indices.sorted(by: { plan.depth[$0] > plan.depth[$1] }) {
            guard let s = plan.span[b], let p = blocks[b].parent else { continue }
            plan.span[p] = plan.span[p].map { (min($0.lo, s.lo), max($0.hi, s.hi)) } ?? s
        }
        for (b, span) in plan.span.enumerated() {
            guard let span else { continue }
            for l in span.lo...span.hi {
                plan.border[plan.borderID(b, l, left: true)] = (b, true)
                plan.border[plan.borderID(b, l, left: false)] = (b, false)
            }
        }
        return plan
    }

    /// `barycenterOrder`, with every layer ordered as a tree of blocks: a
    /// block's entries between its two borders, and nothing else there.
    /// Within a block (or the scope), items sort by barycenter as
    /// `barycenterOrder` sorts them, and each nested block by one key for all
    /// layers, the mean position of everything in it, so sibling blocks keep
    /// the same order in every layer they share. `layers` hold no borders;
    /// the result holds them all.
    static func blockedBarycenterOrder(
        layers: [[String]], edges: [(String, String)], plan: BlockPlan, sweeps: Int = 2
    ) -> [[String]] {
        var layers = layers
        layers.removeAll(where: \.isEmpty)
        var predecessors: [String: [String]] = [:]
        for (from, to) in edges { predecessors[to, default: []].append(from) }
        var position: [String: Int] = [:]
        func recordPositions(_ index: Int) {
            for (i, id) in layers[index].enumerated() { position[id] = i }
        }
        func recordPositions() { for index in layers.indices { recordPositions(index) } }
        func barycenter(_ id: String) -> Double {
            let ps = (predecessors[id] ?? []).compactMap { position[$0] }
            return ps.isEmpty ? Double(position[id] ?? 0)
                              : Double(ps.reduce(0, +)) / Double(ps.count)
        }
        var blockKey = [Double](repeating: 0, count: plan.blocks.count)
        func recordBlockKeys() {
            var sum = [Double](repeating: 0, count: plan.blocks.count)
            var count = [Int](repeating: 0, count: plan.blocks.count)
            for layer in layers {
                for id in layer where plan.border[id] == nil {
                    var cur = plan.blockOf[id]
                    while let b = cur {
                        sum[b] += barycenter(id); count[b] += 1
                        cur = plan.blocks[b].parent
                    }
                }
            }
            for b in blockKey.indices { blockKey[b] = count[b] > 0 ? sum[b] / Double(count[b]) : 0 }
        }

        enum Entry { case item(String), block(Int) }
        func arrange(_ index: Int, byBarycenter: Bool) {
            let items = layers[index].filter { plan.border[$0] == nil }
            var children: [Int: [Entry]] = [:]      // -1 = the scope itself
            for id in items { children[plan.blockOf[id] ?? -1, default: []].append(.item(id)) }
            for (b, span) in plan.span.enumerated() {
                guard let span, span.lo <= index, index <= span.hi else { continue }
                children[plan.blocks[b].parent ?? -1, default: []].append(.block(b))
            }
            // Within a group, blocks keep one order in every layer (by their
            // all-layer key), and each sits among the items at its own
            // barycenter in this layer, raised where needed to keep that
            // order. Items sort by barycenter. Ties: items first, by their
            // current position; blocks by index. All keys differ, so the
            // order is total.
            // Each block's barycenter in this layer: one pass up from each item.
            var localSum: [Int: Double] = [:], localCount: [Int: Int] = [:]
            for id in items {
                let k = byBarycenter ? barycenter(id) : Double(position[id] ?? 0)
                var cur = plan.blockOf[id]
                while let c = cur { localSum[c, default: 0] += k; localCount[c, default: 0] += 1; cur = plan.blocks[c].parent }
            }
            func localKey(_ b: Int) -> Double {
                guard let n = localCount[b] else { return blockKey[b] }
                return localSum[b]! / Double(n)
            }
            var slot: [Int: (key: Double, rank: Int)] = [:]
            for (_, entries) in children {
                var floor = -Double.infinity
                let blocks = entries.compactMap { e -> Int? in if case .block(let b) = e { return b }; return nil }
                for (rank, b) in blocks.sorted(by: { (blockKey[$0], $0) < (blockKey[$1], $1) }).enumerated() {
                    floor = max(floor, localKey(b))
                    slot[b] = (floor, rank)
                }
            }
            func key(_ e: Entry) -> (Double, Int, Double) {
                switch e {
                case .item(let id):
                    return (byBarycenter ? barycenter(id) : Double(position[id] ?? 0), 0, Double(position[id] ?? 0))
                case .block(let b):
                    return (slot[b]!.key, 1, Double(slot[b]!.rank))
                }
            }
            func emit(_ group: Int) -> [String] {
                let sorted = (children[group] ?? []).sorted { key($0) < key($1) }
                return sorted.flatMap { e -> [String] in
                    switch e {
                    case .item(let id): return [id]
                    case .block(let b):
                        return [plan.borderID(b, index, left: true)] + emit(b)
                            + [plan.borderID(b, index, left: false)]
                    }
                }
            }
            layers[index] = emit(-1)
        }

        recordPositions()
        recordBlockKeys()
        for index in layers.indices { arrange(index, byBarycenter: false) }
        recordPositions()
        for _ in 0..<sweeps {
            recordBlockKeys()
            for index in layers.indices {
                // The first layer keeps its order, as in `barycenterOrder`.
                arrange(index, byBarycenter: index > 0)
                recordPositions(index)
            }
        }
        return layers
    }

    /// Moves every left border of a block to one line and every right border
    /// to another, and pushes whatever that crowds, keeping each layer's
    /// order and minimum gaps: a longest-path pass over the constraint graph
    /// whose vertices are the items, with each block side one vertex, started
    /// from the current coordinates. `minWidth[b]` keeps block `b`'s two lines
    /// at least that far apart. Ordering keeps sibling blocks in one order,
    /// so the graph is acyclic; were it not, nothing moves.
    static func clearBlocks(
        center: inout [String: CGFloat], layers: [[String]], breadth: [String: CGFloat],
        minGap: CGFloat, plan: BlockPlan, minWidth: [CGFloat]
    ) {
        func vertex(_ id: String) -> String {
            guard let b = plan.border[id] else { return id }
            return "\u{a7}side\(b.left ? "l" : "r")\(b.block)"
        }
        var x: [String: CGFloat] = [:]
        var order: [String] = []
        for layer in layers {
            for id in layer {
                let v = vertex(id), c = center[id] ?? 0
                if let known = x[v] {
                    if let b = plan.border[id] { x[v] = b.left ? min(known, c) : max(known, c) }
                } else {
                    x[v] = c
                    order.append(v)
                }
            }
        }
        var after: [String: [(String, CGFloat)]] = [:]
        var before: [String: Int] = [:]
        func require(_ a: String, _ b: String, _ gap: CGFloat) {
            after[a, default: []].append((b, gap))
            before[b, default: 0] += 1
        }
        for layer in layers {
            for k in layer.indices.dropLast() {
                let a = layer[k], b = layer[k + 1]
                require(vertex(a), vertex(b), (breadth[a] ?? 0) / 2 + (breadth[b] ?? 0) / 2 + minGap)
            }
        }
        for (b, span) in plan.span.enumerated() where span != nil {
            let l = "\u{a7}sidel\(b)", r = "\u{a7}sider\(b)"
            if x[l] != nil, x[r] != nil { require(l, r, minWidth[b]) }
        }
        // Kahn's order, seeded and drained in first-seen order: deterministic.
        var queue = order.filter { (before[$0] ?? 0) == 0 }
        var head = 0
        var settled = 0
        var result = x
        while head < queue.count {
            let v = queue[head]; head += 1; settled += 1
            for (w, gap) in after[v] ?? [] {
                result[w] = max(result[w]!, result[v]! + gap)
                before[w]! -= 1
                if before[w] == 0 { queue.append(w) }
            }
        }
        guard settled == order.count else { return }
        for layer in layers { for id in layer { center[id] = result[vertex(id)] } }
    }

    /// Grows the layer gaps (and the lead and tail pads) by each block's
    /// chrome along the main axis, and returns how far each box reaches
    /// before its first layer's band and past its last's. A top-down box has
    /// its header strip above its first row; a left-right box has it along its
    /// top, beside the rows, and is made long enough for its label. A box
    /// reaches out by its own chrome plus that of any nested box sharing its
    /// first (or last) layer; a gap grows by the furthest reach into it from
    /// either side.
    static func blockMainChrome(
        _ plan: BlockPlan, layers: [[String]], sizes: [String: CGSize], horizontal: Bool,
        layerGaps: inout [CGFloat], leadPad: inout CGFloat, tailPad: inout CGFloat,
        margin: CGFloat, measure: DiagramTextMeasurer
    ) -> [(lead: CGFloat, tail: CGFloat)] {
        let count = plan.blocks.count
        let header = clusterHeader(measure)
        let band = layers.map { layer in
            layer.map { horizontal ? (sizes[$0]?.width ?? 0) : (sizes[$0]?.height ?? 0) }.max() ?? 0
        }
        var extraBefore = [CGFloat](repeating: 0, count: layers.count)
        var extraAfter = [CGFloat](repeating: 0, count: layers.count)
        func gap(_ l: Int) -> CGFloat {
            (l < layerGaps.count ? layerGaps[l] : (layerGaps.last ?? 0)) + extraAfter[l] + extraBefore[l + 1]
        }
        var reach = [(lead: CGFloat, tail: CGFloat)](repeating: (0, 0), count: count)
        for b in (0..<count).sorted(by: { (plan.depth[$0], $0) > (plan.depth[$1], $1) }) {
            guard let span = plan.span[b], span.hi < layers.count else { continue }
            var lead = horizontal ? clusterPad + margin : header + margin
            var tail = clusterPad + margin
            var nestedLead: CGFloat = 0, nestedTail: CGFloat = 0
            for c in 0..<count where plan.blocks[c].parent == b {
                guard let cs = plan.span[c] else { continue }
                if cs.lo == span.lo { nestedLead = max(nestedLead, reach[c].lead) }
                if cs.hi == span.hi { nestedTail = max(nestedTail, reach[c].tail) }
            }
            lead += nestedLead
            tail += nestedTail
            if horizontal {
                // The label runs along the top: the box must be as long.
                var length = lead + tail
                for l in span.lo...span.hi { length += band[l] }
                for l in span.lo..<span.hi { length += gap(l) }
                let short = measure(plan.blocks[b].label, nodeFontSize).width + 16 - length
                if short > 0 { lead += short / 2; tail += short / 2 }
            }
            reach[b] = (lead, tail)
            extraBefore[span.lo] = max(extraBefore[span.lo], lead)
            extraAfter[span.hi] = max(extraAfter[span.hi], tail)
        }
        for l in layers.indices.dropLast() {
            while layerGaps.count <= l { layerGaps.append(layerGaps.last ?? 0) }
            layerGaps[l] += extraAfter[l] + extraBefore[l + 1]
        }
        if let first = extraBefore.first { leadPad += first }
        if let last = extraAfter.last { tailPad += last }
        return reach
    }

    /// The part of `points` up to where it first enters `box` from outside,
    /// or nil when it starts inside or never enters.
    static func clippedEntering(_ points: [CGPoint], _ box: CGRect) -> [CGPoint]? {
        guard let first = points.first, !box.insetBy(dx: 0.01, dy: 0.01).contains(first) else { return nil }
        for k in points.indices.dropLast() {
            let a = points[k], b = points[k + 1]
            // Liang–Barsky: the first t in [0, 1] where a→b is inside the box.
            var t0: CGFloat = 0, t1: CGFloat = 1
            let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
            var inside = true
            for (p, q) in [(-d.x, a.x - box.minX), (d.x, box.maxX - a.x),
                           (-d.y, a.y - box.minY), (d.y, box.maxY - a.y)] {
                if p == 0 {
                    if q < 0 { inside = false; break }
                } else {
                    let t = q / p
                    if p < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                }
            }
            guard inside, t0 <= t1 else { continue }
            // Entering at a bend: end there, with no zero-length last run
            // (an arrowhead needs a direction).
            if t0 == 0 { return k > 0 ? Array(points[0...k]) : nil }
            let entry = CGPoint(x: a.x + d.x * t0, y: a.y + d.y * t0)
            return Array(points[0...k]) + [entry]
        }
        return nil
    }
}
