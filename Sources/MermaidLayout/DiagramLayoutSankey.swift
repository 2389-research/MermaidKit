import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a Sankey flow diagram left-to-right. Nodes are assigned to
    /// columns by longest-path depth from the sources; each node's bar height
    /// is proportional to its total flow (max of in/out). Links become bands
    /// whose thickness equals their value, stacked down each node's edges.
    /// Pure geometry — the renderer only fills bands, bars, and labels.
    public static func layout(_ d: SankeyDiagram, measure: DiagramTextMeasurer) -> SankeyLayout {
        let margin: CGFloat = 16
        let thickness: CGFloat = 16
        let columnSpacing: CGFloat = 230
        let nodeGap: CGFloat = 12
        let labelSize: Double = 11
        let labelPad: CGFloat = 6
        let minBarHeight: CGFloat = 6

        let names = d.nodes
        let n = names.count
        guard n > 0 else {
            return SankeyLayout(size: CGSize(width: 120, height: 80), nodes: [], links: [])
        }
        // Keyed by first occurrence; `uniquingKeysWith` because a hand-built
        // SankeyDiagram may repeat a node name and a public entry point must
        // not trap on malformed input.
        let index = Dictionary(names.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        // Flow totals and predecessor lists.
        var inValue = [Double](repeating: 0, count: n)
        var outValue = [Double](repeating: 0, count: n)
        var incoming: [[Int]] = Array(repeating: [], count: n)
        for link in d.links {
            guard let s = index[link.source], let t = index[link.target] else { continue }
            outValue[s] += link.value
            inValue[t] += link.value
            incoming[t].append(s)
        }
        let nodeValue = (0..<n).map { max(inValue[$0], outValue[$0], 0.0001) }

        // Longest-path depth from sources, with a cycle guard.
        var depthMemo = [Int?](repeating: nil, count: n)
        var visiting = [Bool](repeating: false, count: n)
        func depth(_ i: Int) -> Int {
            if let cached = depthMemo[i] { return cached }
            if visiting[i] { return 0 }
            visiting[i] = true
            var best = 0
            for p in incoming[i] { best = max(best, depth(p) + 1) }
            visiting[i] = false
            depthMemo[i] = best
            return best
        }
        var depths = (0..<n).map { depth($0) }
        let deepest = depths.max() ?? 0
        // Justify alignment (d3-sankey's default `nodeAlign`): a SINK — a node
        // with no outgoing flow — belongs in the RIGHTMOST column, not merely
        // at its longest path from a source. Without this, "Shipping"
        // (Crude Oil → Refined Fuels → Shipping) has depth 2 and floats in a
        // middle column instead of lining up on the right edge with the other
        // outputs (Useful Energy, Waste Heat, Grid Losses), exactly as Clint
        // spotted. `outValue[i] == 0` ⇔ the node emits nothing ⇔ it's a sink.
        for i in 0..<n where outValue[i] <= 0 { depths[i] = deepest }
        let maxDepth = depths.max() ?? 0

        // Group node indices by column, preserving first-appearance order.
        var columns: [[Int]] = Array(repeating: [], count: maxDepth + 1)
        for i in 0..<n { columns[depths[i]].append(i) }

        // Crossing minimization: reorder each column by the barycenter of its
        // neighbours' positions in the adjacent column, alternating forward and
        // backward sweeps. Without this the columns keep their arbitrary
        // first-appearance order and the bands weave over each other.
        var outgoing: [[Int]] = Array(repeating: [], count: n)
        for link in d.links {
            if let s = index[link.source], let t = index[link.target] { outgoing[s].append(t) }
        }
        var posInCol = [Int](repeating: 0, count: n)
        func recordPositions() {
            for col in columns { for (k, i) in col.enumerated() { posInCol[i] = k } }
        }
        recordPositions()
        func barycenter(_ i: Int, _ neighbours: [[Int]], inColumn c: Int) -> Double {
            let ns = neighbours[i].filter { depths[$0] == c }
            guard !ns.isEmpty else { return Double(posInCol[i]) }
            return Double(ns.reduce(0) { $0 + posInCol[$1] }) / Double(ns.count)
        }
        if maxDepth >= 1 {
            for _ in 0..<4 {
                for c in 1...maxDepth {
                    columns[c].sort { barycenter($0, incoming, inColumn: c - 1) < barycenter($1, incoming, inColumn: c - 1) }
                    recordPositions()
                }
                for c in stride(from: maxDepth - 1, through: 0, by: -1) {
                    columns[c].sort { barycenter($0, outgoing, inColumn: c + 1) < barycenter($1, outgoing, inColumn: c + 1) }
                    recordPositions()
                }
            }
        }

        // Choose a value→pixel scale so the busiest column fits a target height.
        let targetHeight: CGFloat = 520
        var maxColValue = 0.0001
        for col in columns { maxColValue = max(maxColValue, col.reduce(0) { $0 + nodeValue[$1] }) }
        let maxColCount = columns.map(\.count).max() ?? 1
        var scale = (targetHeight - CGFloat(max(maxColCount - 1, 0)) * nodeGap) / CGFloat(maxColValue)
        // A low floor: `minBarHeight` already guarantees tiny nodes stay
        // visible, so a big 3px/unit floor only inflates the canvas into a
        // tall, cramped portrait. Keep it small so the plot stays landscape.
        scale = min(max(scale, 1.2), 60)

        func barHeight(_ i: Int) -> CGFloat { max(CGFloat(nodeValue[i]) * scale, minBarHeight) }

        // Column pixel heights and the tallest (content) height.
        let colHeights: [CGFloat] = columns.map { col in
            guard !col.isEmpty else { return 0 }
            return CGFloat(col.count - 1) * nodeGap + col.reduce(CGFloat(0)) { $0 + barHeight($1) }
        }
        let contentHeight = max(colHeights.max() ?? thickness, thickness)

        // Horizontal room for outboard labels.
        func maxLabelWidth(_ col: [Int]) -> CGFloat {
            col.reduce(CGFloat(0)) { max($0, measure(names[$1], labelSize).width) }
        }
        let leftRoom = maxLabelWidth(columns.first ?? []) + labelPad
        let rightRoom = maxLabelWidth(columns.last ?? []) + labelPad
        let originX = margin + leftRoom
        let topOffset = margin

        // ---- Coordinate assignment: a faithful port of d3-sankey's
        // computeNodeBreadths (github.com/d3/d3-sankey). Node bar heights are
        // value*scale; y-positions start stacked per column, then relax toward
        // the LINK-ATTACHMENT point (targetTop/sourceTop), weighted by
        // value × layer-distance, over `iterations` passes — each doing
        // relaxRightToLeft then relaxLeftToRight, re-sorting links by breadth,
        // with GENTLE α-damped centre-outward collision resolution that
        // preserves the relaxation (a hard re-stack, which I did before, undoes
        // it and reads worse). This is the algorithm every real Sankey uses. ----
        let iterations = 32
        let py = Swift.min(nodeGap, contentHeight / CGFloat(Swift.max(maxColCount - 1, 1)))
        let yTop = topOffset, yBot = topOffset + contentHeight
        func nh(_ i: Int) -> CGFloat { barHeight(i) }
        var y0 = [CGFloat](repeating: 0, count: n)   // node top edge
        for col in columns {
            let colH = col.reduce(CGFloat(0)) { $0 + nh($1) } + CGFloat(Swift.max(col.count - 1, 0)) * py
            var y = yTop + (contentHeight - colH) / 2
            for i in col { y0[i] = y; y += nh(i) + py }
        }

        // Directed links with pixel width; per-node out/in lists (re-sorted by
        // the connected node's breadth each pass, so the attachment maths track).
        struct DL { let other: Int; let width: CGFloat }
        var srcLinks = [[DL]](repeating: [], count: n)   // outgoing (this = source)
        var tgtLinks = [[DL]](repeating: [], count: n)   // incoming (this = target)
        for link in d.links {
            guard let s = index[link.source], let t = index[link.target] else { continue }
            let w = CGFloat(link.value) * scale
            srcLinks[s].append(DL(other: t, width: w))
            tgtLinks[t].append(DL(other: s, width: w))
        }

        // Ideal y0 for `t` so its link from `s` lines up (and vice versa).
        func targetTop(_ s: Int, _ t: Int) -> CGFloat {
            var y = y0[s] - CGFloat(srcLinks[s].count - 1) * py / 2
            for dl in srcLinks[s] { if dl.other == t { break }; y += dl.width + py }
            for dl in tgtLinks[t] { if dl.other == s { break }; y -= dl.width }
            return y
        }
        func sourceTop(_ s: Int, _ t: Int) -> CGFloat {
            var y = y0[t] - CGFloat(tgtLinks[t].count - 1) * py / 2
            for dl in tgtLinks[t] { if dl.other == s { break }; y += dl.width + py }
            for dl in srcLinks[s] { if dl.other == t { break }; y -= dl.width }
            return y
        }
        func resolveCollisions(_ col: [Int], _ alpha: CGFloat) {
            let nodes = col.sorted { y0[$0] < y0[$1] }
            guard !nodes.isEmpty else { return }
            func topToBottom(_ startY: CGFloat, _ from: Int) {
                var y = startY, i = from
                while i < nodes.count {
                    let dy = (y - y0[nodes[i]]) * alpha
                    if dy > 1e-6 { y0[nodes[i]] += dy }
                    y = y0[nodes[i]] + nh(nodes[i]) + py; i += 1
                }
            }
            func bottomToTop(_ startY: CGFloat, _ from: Int) {
                var y = startY, i = from
                while i >= 0 {
                    let dy = (y0[nodes[i]] + nh(nodes[i]) - y) * alpha
                    if dy > 1e-6 { y0[nodes[i]] -= dy }
                    y = y0[nodes[i]] - py; i -= 1
                }
            }
            let mid = nodes.count / 2
            bottomToTop(y0[nodes[mid]] - py, mid - 1)
            topToBottom(y0[nodes[mid]] + nh(nodes[mid]) + py, mid + 1)
            bottomToTop(yBot, nodes.count - 1)
            topToBottom(yTop, 0)
        }

        if maxDepth >= 1 {
            for iter in 0..<iterations {
                let alpha = pow(0.99, CGFloat(iter))
                // reorder links by the connected node's current breadth
                for i in 0..<n {
                    srcLinks[i].sort { y0[$0.other] < y0[$1.other] }
                    tgtLinks[i].sort { y0[$0.other] < y0[$1.other] }
                }
                // relaxRightToLeft: position each node from its outgoing links
                for c in stride(from: maxDepth - 1, through: 0, by: -1) {
                    for s in columns[c] where !srcLinks[s].isEmpty {
                        var y: CGFloat = 0, w: CGFloat = 0
                        for dl in srcLinks[s] {
                            let v = dl.width * CGFloat(Swift.max(depths[dl.other] - depths[s], 1))
                            y += (sourceTop(s, dl.other)) * v; w += v
                        }
                        if w > 0 { y0[s] += (y / w - y0[s]) * alpha }
                    }
                    resolveCollisions(columns[c], alpha)
                }
                // relaxLeftToRight: position each node from its incoming links
                for c in 1...maxDepth {
                    for t in columns[c] where !tgtLinks[t].isEmpty {
                        var y: CGFloat = 0, w: CGFloat = 0
                        for dl in tgtLinks[t] {
                            let v = dl.width * CGFloat(Swift.max(depths[t] - depths[dl.other], 1))
                            y += (targetTop(dl.other, t)) * v; w += v
                        }
                        if w > 0 { y0[t] += (y / w - y0[t]) * alpha }
                    }
                    resolveCollisions(columns[c], alpha)
                }
            }
        }
        // Final HARD collision pass per column (alpha = 1). The damped
        // per-iteration passes converge but can leave residual overlap; one
        // firm separation at the end guarantees no bars overlap and all stay
        // in-bounds — without the every-iteration re-stacking that flattened
        // the layout in my earlier attempt.
        for c in 0...maxDepth { resolveCollisions(columns[c], 1.0) }
        for i in 0..<n { y0[i] = Swift.min(Swift.max(y0[i], yTop), yBot - nh(i)) }

        var rects = [CGRect](repeating: .zero, count: n)
        for (c, col) in columns.enumerated() {
            let colX = originX + CGFloat(c) * columnSpacing
            for i in col { rects[i] = CGRect(x: colX, y: y0[i], width: thickness, height: nh(i)) }
        }

        // Bands: stack outgoing on each source's right edge, incoming on each
        // target's left edge, in link declaration order.
        //
        // A link whose target is more than one column past its source would,
        // as a straight source→target centerline, pass through the bars in the
        // skipped column(s). We give such links a routed centerline that climbs
        // into the node-free band above every bar, runs across, and drops back
        // down at the target — the vertical legs hug the source's right edge and
        // the target's left edge (never entering another bar), and the crossbar
        // rides above the tallest column's top, so the route clears every
        // intermediate node. Depth is a longest-path rank, so a target's column
        // is always strictly greater than its source's; `ct - cs >= 2` is
        // exactly the set of column-skipping links.
        let clearY = topOffset - 6   // above every bar (bars start at topOffset)
        // Stack each node's outgoing bands by their target's vertical position
        // and incoming bands by their source's — so bands leave and arrive in
        // the same order as the nodes they connect and don't cross at the bar
        // edges (the second half of untangling, after the column ordering).
        struct Flow { let li: Int; let s: Int; let t: Int; let w: CGFloat }
        var flows: [Flow] = []
        for (li, link) in d.links.enumerated() {
            guard let s = index[link.source], let t = index[link.target] else { continue }
            flows.append(Flow(li: li, s: s, t: t, w: CGFloat(link.value) * scale))
        }
        var sourceTopY = [Int: CGFloat](), targetTopY = [Int: CGFloat]()
        var srcOffset = [CGFloat](repeating: 0, count: n), tgtOffset = [CGFloat](repeating: 0, count: n)
        for s in 0..<n {
            for f in flows.filter({ $0.s == s }).sorted(by: { rects[$0.t].midY < rects[$1.t].midY }) {
                sourceTopY[f.li] = rects[s].minY + srcOffset[s]; srcOffset[s] += f.w
            }
        }
        for t in 0..<n {
            for f in flows.filter({ $0.t == t }).sorted(by: { rects[$0.s].midY < rects[$1.s].midY }) {
                targetTopY[f.li] = rects[t].minY + tgtOffset[t]; tgtOffset[t] += f.w
            }
        }
        var links: [SankeyLayout.Link] = []
        for f in flows {
            let s = f.s, t = f.t, w = f.w
            let sTop = sourceTopY[f.li] ?? rects[s].minY
            let tTop = targetTopY[f.li] ?? rects[t].minY
            let sourceCenter = CGPoint(x: rects[s].maxX, y: sTop + w / 2)
            let targetCenter = CGPoint(x: rects[t].minX, y: tTop + w / 2)
            let route: [CGPoint]
            if depths[t] - depths[s] >= 2 {
                route = [
                    sourceCenter,
                    CGPoint(x: sourceCenter.x, y: clearY),
                    CGPoint(x: targetCenter.x, y: clearY),
                    targetCenter
                ]
            } else {
                route = [sourceCenter, targetCenter]
            }
            links.append(SankeyLayout.Link(
                sourceTop: CGPoint(x: rects[s].maxX, y: sTop),
                sourceBottom: CGPoint(x: rects[s].maxX, y: sTop + w),
                targetTop: CGPoint(x: rects[t].minX, y: tTop),
                targetBottom: CGPoint(x: rects[t].minX, y: tTop + w),
                colorIndex: s,
                route: route
            ))
        }

        // Node bars + their labels (leftmost column labels sit left, others
        // right, just outboard of the bar and centered on it).
        var nodes: [SankeyLayout.Node] = []
        for i in 0..<n {
            let r = rects[i]
            let labelWidth = measure(names[i], labelSize).width
            let labelCenter: CGPoint
            if depths[i] == 0 {
                labelCenter = CGPoint(x: r.minX - labelPad - labelWidth / 2, y: r.midY)
            } else {
                labelCenter = CGPoint(x: r.maxX + labelPad + labelWidth / 2, y: r.midY)
            }
            nodes.append(SankeyLayout.Node(
                label: names[i], rect: r, colorIndex: i, labelCenter: labelCenter
            ))
        }

        let rawWidth = originX + CGFloat(maxDepth) * columnSpacing + thickness + rightRoom + margin
        let rawHeight = topOffset + contentHeight + margin
        let size = CGSize(
            width: min(max(rawWidth, 80), 3800),
            height: min(max(rawHeight, 60), 3800)
        )
        return SankeyLayout(size: size, nodes: nodes, links: links)
    }
}

/// Placed Sankey geometry: node bars in columns plus flow bands between them.
/// Top-left-origin points; `size` is the canvas.
public struct SankeyLayout: Sendable {
    /// A node's bar (fixed thickness; height proportional to its total flow).
    public struct Node: Sendable {
        public let label: String
        public let rect: CGRect
        /// Cycled palette slot — the node's index in the diagram's node list.
        public let colorIndex: Int
        /// Center of the name label: left of the bar for first-column nodes,
        /// right of it otherwise.
        public let labelCenter: CGPoint
    }

    /// A flow band; the renderer draws a cubic band between the two edges
    /// defined by the four corner points (band thickness = flow value).
    public struct Link: Sendable {
        /// Band top on the source bar's right edge.
        public let sourceTop: CGPoint
        /// Band bottom on the source bar's right edge.
        public let sourceBottom: CGPoint
        /// Band top on the target bar's left edge.
        public let targetTop: CGPoint
        /// Band bottom on the target bar's left edge.
        public let targetBottom: CGPoint
        /// The source node's palette slot — bands take their source's color.
        public let colorIndex: Int
        /// The band's centerline as a routed polyline (source edge → target
        /// edge). For links spanning more than one column it detours through the
        /// node-free band above the bars so it never crosses an intermediate
        /// node; adjacent links are a straight two-point centerline. The
        /// renderer draws its own cubic band from the four corner points — this
        /// route is the flow's logical path for geometry checks.
        public let route: [CGPoint]
    }

    public let size: CGSize
    public let nodes: [Node]
    public let links: [Link]
}
