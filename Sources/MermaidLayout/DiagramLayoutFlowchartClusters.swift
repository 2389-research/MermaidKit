import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Recursive cluster (subgraph) layout for flowcharts.
///
/// The core layered engine (`layoutFlat`) knows nothing about groups. This
/// wrapper lays out each subgraph's interior as its own independent flowchart,
/// wraps that sub-layout in box chrome (a label header + padding), and hands
/// the parent a single sized placeholder node in its place. The parent's
/// Sugiyama pass then positions the whole group as one rectangle — which
/// guarantees group boxes never overlap non-members, so the geometry linter
/// stays satisfied. After the parent places the placeholder, the sub-layout is
/// translated into it and emitted as a `Container`.
///
/// Edges are resolved to their representative at each scope: an edge crossing
/// into (or naming) a group terminates on that group's box border. This is
/// what kills the old "edge to a subgraph id mints a phantom node" bug — the
/// id now resolves to the container.
///
/// One box in one row can't sit both above and below an outside node, so a
/// group that an edge leaves and a path re-enters would make its parent
/// reverse an edge that lies on no cycle (#103). Such a group is unfolded
/// instead: it is laid out with its parent's nodes, as a block whose box spans
/// the rows its members take (`DiagramLayoutFlowchartBlocks.swift`), and it
/// takes its parent's direction, as mermaid's does. A chart with no such group
/// lays out exactly as it did before.
extension DiagramLayoutEngine {

    /// Header strip reserved at the top of every group box for its 11pt
    /// label, which is centered in it: 22 at the default size, grown with the
    /// text. Layout, both renderers and the lint scene place the label by it.
    package static func clusterHeader(_ measure: DiagramTextMeasurer) -> CGFloat {
        grown(22, fontSize: 11, measure)
    }
    /// Interior padding between a group's box and its contents (and the gap
    /// below the header before content starts is `clusterHeader`).
    static let clusterPad: CGFloat = 12

    static func layoutClustered(_ chart: Flowchart, measure: DiagramTextMeasurer,
                                spacing: DiagramSpacing) -> FlowchartLayout {
        let ctx = clusterContext(chart)
        let scope = layoutScope(ctx, scope: nil, inherited: chart.direction, depth: 0,
                                measure: measure, spacing: spacing)
        return FlowchartLayout(size: scope.size, nodes: scope.nodes,
                               edges: separatedAcrossScopes(scope.edges, nodes: scope.nodes,
                                                            containers: scope.containers),
                               containers: scope.containers)
    }

    /// The subgraphs laid out with their parent's nodes rather than as one
    /// box in one row (#103), as `layoutClustered` decides them.
    static func unfoldedSubgraphs(_ chart: Flowchart) -> Set<String> {
        chart.subgraphs.isEmpty ? [] : clusterContext(chart).unfolded
    }

    private static func clusterContext(_ chart: Flowchart) -> ClusterContext {
        // Membership: node/subgraph id -> its innermost containing subgraph id
        // (absent = top level). Built once, read throughout the recursion.
        var containerOf: [String: String] = [:]
        for sub in chart.subgraphs {
            for nid in sub.nodeIDs { containerOf[nid] = sub.id }
            for cid in sub.childIDs { containerOf[cid] = sub.id }
        }
        let nodeByID = Dictionary(chart.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let subByID = Dictionary(chart.subgraphs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ctx = ClusterContext(chart: chart, containerOf: containerOf,
                                 nodeByID: nodeByID, subByID: subByID, edgeLCA: [], ancestors: [:], unfolded: [])
        for id in Set(chart.nodes.map(\.id) + chart.subgraphs.map(\.id) + chart.edges.flatMap { [$0.from, $0.to] }) {
            var up: [String] = []
            var cur = containerOf[id]
            while let c = cur { up.append(c); cur = containerOf[c] }
            ctx.ancestors[id] = up
        }
        ctx.edgeLCA = chart.edges.map { lca(ctx, $0.from, $0.to) }
        ctx.unfolded = decideUnfolded(ctx)
        return ctx
    }

    /// Per-diagram lookup tables shared across the recursion. The measurer
    /// is threaded as a parameter, not stored, so it stays non-escaping (the
    /// public `layout` closure is not `@escaping`).
    private struct ClusterContext {
        let chart: Flowchart
        let containerOf: [String: String]
        let nodeByID: [String: Flowchart.Node]
        let subByID: [String: Flowchart.Subgraph]
        /// Each edge's innermost subgraph holding both ends (nil = top level).
        var edgeLCA: [String?]
        /// Each id's subgraphs, innermost first.
        var ancestors: [String: [String]]
        /// Subgraphs laid out with their parent's nodes (#103).
        var unfolded: Set<String>
    }

    private struct ScopeResult {
        var nodes: [FlowchartLayout.PlacedNode]
        var edges: [FlowchartLayout.PlacedEdge]
        var containers: [FlowchartLayout.Container]
        var size: CGSize
    }

    /// One scope's flat chart: what it places (its own nodes, one box per
    /// child subgraph, and, for an unfolded child, what that child places),
    /// the edges it owns resolved to those, and the unfolded children as
    /// blocks.
    private struct ReducedScope {
        var chart: Flowchart
        /// The boxes laid out on their own, in order.
        var boxes: [String]
        var blocks: [FlowBlock]
        /// Unfolded subgraphs between each box or block and the scope.
        var nesting: [String: Int]
        /// The chart edges each reduced edge stands for.
        var origins: [[Int]]
        /// Reduced edges that name an unfolded subgraph, by block index.
        var clips: [Int: (from: Int?, to: Int?)]
        /// The stand-in an edge naming an unfolded subgraph ranks with.
        var standIns: Set<String>
        /// An unfolded subgraph's own self-loops (`S --> S`), by block index:
        /// drawn on its box once it is placed.
        var loops: [(block: Int, edge: Flowchart.Edge)]
    }

    /// The stand-in for unfolded subgraph `id`: an invisible point in its
    /// box that an edge naming the subgraph ranks with, cut at the box.
    private static func standIn(_ id: String) -> String { "\u{a7}sub:" + id }

    private static func reduce(_ ctx: ClusterContext, scope: String?,
                               direction: Flowchart.Direction) -> ReducedScope {
        // 1. What the scope places. With nothing unfolded: its nodes, then one
        //    box per child subgraph. An unfolded child places its own nodes
        //    and children, the same way, in its place.
        var nodeIDs: [String] = []
        var boxes: [String] = []
        var blocks: [FlowBlock] = []
        var blockIndex: [String: Int] = [:]
        var nesting: [String: Int] = [:]
        func members(_ scope: String?) -> (nodes: [String], children: [String]) {
            if let scope, let sub = ctx.subByID[scope] { return (sub.nodeIDs, sub.childIDs) }
            return (ctx.chart.nodes.filter { ctx.containerOf[$0.id] == nil }.map(\.id),
                    ctx.chart.subgraphs.filter { ctx.containerOf[$0.id] == nil }.map(\.id))
        }
        func place(_ group: String?, block: Int?, level: Int) {
            let (nodes, children) = members(group)
            var items = nodes
            nodeIDs += nodes
            for child in children {
                if ctx.unfolded.contains(child) {
                    let index = blocks.count
                    blockIndex[child] = index
                    nesting[child] = level
                    blocks.append(FlowBlock(id: child, label: ctx.subByID[child]?.label ?? "",
                                            parent: block, items: []))
                    place(child, block: index, level: level + 1)
                } else {
                    boxes.append(child)
                    nesting[child] = level
                    items.append(child)
                }
            }
            if let block {
                let b = blocks[block]
                blocks[block] = FlowBlock(id: b.id, label: b.label, parent: b.parent, items: items)
            }
        }
        place(scope, block: nil, level: 0)
        var reducedNodes: [Flowchart.Node] = nodeIDs.compactMap { ctx.nodeByID[$0] }
        for box in boxes { reducedNodes.append(Flowchart.Node(id: box, label: "", shape: .rectangle)) }

        // 2. The edges this scope owns: those whose ends' innermost shared
        //    subgraph is this scope, or unfolded into it. Each end resolves to
        //    what the scope places; an end naming an unfolded subgraph ranks
        //    with the subgraph's stand-in and is cut at its box.
        var standIns: Set<String> = []
        var loops: [(block: Int, edge: Flowchart.Edge)] = []
        var reducedEdges: [Flowchart.Edge] = []
        var origins: [[Int]] = []
        var clips: [Int: (from: Int?, to: Int?)] = [:]
        var seen: [Flowchart.Edge: Int] = [:]
        for (index, edge) in ctx.chart.edges.enumerated() {
            var owner = ctx.edgeLCA[index]
            while let o = owner, ctx.unfolded.contains(o) { owner = ctx.containerOf[o] }
            guard owner == scope else { continue }
            // An unfolded subgraph's own loop goes round its box.
            if edge.from == edge.to, let b = blockIndex[edge.from] {
                loops.append((b, edge))
                continue
            }
            // An unfolded subgraph and what's in it link nothing, as they
            // would folded into one box.
            if ctx.unfolded.contains(edge.to), inside(ctx, edge.from, edge.to) { continue }
            if ctx.unfolded.contains(edge.from), inside(ctx, edge.to, edge.from) { continue }
            func end(_ id: String) -> String {
                guard let b = blockIndex[id] else { return visible(ctx, id, scope: scope) }
                let point = standIn(id)
                if standIns.insert(point).inserted {
                    reducedNodes.append(Flowchart.Node(id: point, label: "", shape: .rectangle))
                    let block = blocks[b]
                    blocks[b] = FlowBlock(id: block.id, label: block.label, parent: block.parent,
                                          items: block.items + [point])
                }
                return point
            }
            let from = end(edge.from), to = end(edge.to)
            // Two ends folded into one group's box link nothing at this scope,
            // but a real self-loop (`A --> A`, or a group's own `G --> G`) is
            // kept, so `layoutFlat` draws it as a loop.
            guard from != to || edge.from == edge.to else { continue }
            let reduced = Flowchart.Edge(from: from, to: to, label: edge.label,
                                         dashed: edge.dashed, hasArrow: edge.hasArrow,
                                         backArrow: edge.backArrow, head: edge.head,
                                         thick: edge.thick, invisible: edge.invisible,
                                         length: edge.length)
            let clip = (from: blockIndex[edge.from], to: blockIndex[edge.to])
            if clip.from == nil, clip.to == nil, let known = seen[reduced] {
                origins[known].append(index)
                continue
            }
            if clip.from != nil || clip.to != nil {
                clips[reducedEdges.count] = clip
            } else {
                seen[reduced] = reducedEdges.count
            }
            reducedEdges.append(reduced)
            origins.append([index])
        }
        return ReducedScope(
            chart: Flowchart(direction: direction, nodes: reducedNodes, edges: reducedEdges),
            boxes: boxes, blocks: blocks, nesting: nesting, origins: origins, clips: clips,
            standIns: standIns, loops: loops)
    }

    /// Whether `id` is `group` or lies inside it.
    private static func inside(_ ctx: ClusterContext, _ id: String, _ group: String) -> Bool {
        var cur: String? = id
        while let c = cur { if c == group { return true }; cur = ctx.containerOf[c] }
        return false
    }

    /// Which subgraphs to unfold (#103). A subgraph laid out as one box in
    /// one row can't sit both above and below an outside node, so a path
    /// that leaves it and comes back makes a cycle the chart doesn't have,
    /// and breaking it can send an edge on no cycle back up. At each scope,
    /// the same back edges the layout will break are found; while one of
    /// them stands for a chart edge on no cycle, the first box on the cycle
    /// it closes is unfolded, and the scope is reduced again. Such a cycle
    /// always holds a box (a cycle through real nodes only would be the
    /// chart's own), and each round unfolds one, so it ends. A scope where no
    /// such edge is broken is reduced exactly as before, so it lays out
    /// exactly as before. Then each box still standing is decided the same
    /// way, inside.
    private static func decideUnfolded(_ ctx: ClusterContext) -> Set<String> {
        // Strongly connected components of the chart, a subgraph an edge
        // names being a vertex of its own, as its stand-in is once unfolded.
        var ids: [String] = []
        var index: [String: Int] = [:]
        func vertex(_ id: String) -> Int {
            if let i = index[id] { return i }
            index[id] = ids.count; ids.append(id)
            return ids.count - 1
        }
        let ends = ctx.chart.edges.map { (vertex($0.from), vertex($0.to)) }
        let component = stronglyConnectedComponents(count: ids.count, edges: ends)
        func onNoCycle(_ e: Int) -> Bool { component[ends[e].0] != component[ends[e].1] }

        var ctx = ctx
        var pending: [String?] = [nil]
        while let scope = pending.first {
            pending.removeFirst()
            var reduced = reduce(ctx, scope: scope, direction: .topDown)
            while true {
                let chart = reduced.chart
                let back = backEdgeIndices(ids: chart.nodes.map(\.id), edges: chart.edges.map { ($0.from, $0.to) })
                guard let broken = back.sorted().first(where: { reduced.origins[$0].contains(where: onNoCycle) })
                else { break }
                let boxes = Set(reduced.boxes.filter { hasNode(ctx, $0) })
                let edge = chart.edges[broken]
                guard let box = path(from: edge.to, to: edge.from, in: chart.edges)?.first(where: boxes.contains)
                else { break }
                ctx.unfolded.insert(box)
                reduced = reduce(ctx, scope: scope, direction: .topDown)
            }
            pending += reduced.boxes
        }
        return ctx.unfolded
    }

    /// A shortest path `from` → `to` over `edges`, by breadth-first search in
    /// edge order (deterministic), as the node list; nil if there is none.
    private static func path(from: String, to: String, in edges: [Flowchart.Edge]) -> [String]? {
        var out: [String: [String]] = [:]
        for e in edges { out[e.from, default: []].append(e.to) }
        var previous: [String: String] = [:]
        var queue = [from], head = 0
        var seen: Set<String> = [from]
        while head < queue.count {
            let v = queue[head]; head += 1
            if v == to {
                var path = [v], cur = v
                while let p = previous[cur] { path.append(p); cur = p }
                return path.reversed()
            }
            for w in out[v] ?? [] where seen.insert(w).inserted {
                previous[w] = v
                queue.append(w)
            }
        }
        return nil
    }

    /// Tarjan's strongly connected components, iteratively (deep charts
    /// must not overflow the stack): each vertex's component number.
    static func stronglyConnectedComponents(count: Int, edges: [(Int, Int)]) -> [Int] {
        var out = [[Int]](repeating: [], count: count)
        for (a, b) in edges { out[a].append(b) }
        var order = [Int](repeating: -1, count: count), low = [Int](repeating: 0, count: count)
        var component = [Int](repeating: -1, count: count)
        var onStack = [Bool](repeating: false, count: count)
        var stack: [Int] = [], next = 0, components = 0
        for root in 0..<count where order[root] == -1 {
            var work: [(v: Int, edge: Int)] = [(root, 0)]
            order[root] = next; low[root] = next; next += 1
            stack.append(root); onStack[root] = true
            while let (v, e) = work.last {
                if e < out[v].count {
                    work[work.count - 1].edge += 1
                    let w = out[v][e]
                    if order[w] == -1 {
                        order[w] = next; low[w] = next; next += 1
                        stack.append(w); onStack[w] = true
                        work.append((w, 0))
                    } else if onStack[w] {
                        low[v] = min(low[v], order[w])
                    }
                } else {
                    work.removeLast()
                    if let parent = work.last?.v { low[parent] = min(low[parent], low[v]) }
                    if low[v] == order[v] {
                        while let w = stack.popLast() {
                            onStack[w] = false
                            component[w] = components
                            if w == v { break }
                        }
                        components += 1
                    }
                }
            }
        }
        return component
    }

    /// Whether subgraph `id` holds a node, at any depth: one without has
    /// nothing to unfold.
    private static func hasNode(_ ctx: ClusterContext, _ id: String) -> Bool {
        guard let sub = ctx.subByID[id] else { return false }
        return !sub.nodeIDs.isEmpty || sub.childIDs.contains { hasNode(ctx, $0) }
    }

    /// What represents `id` in `scope`'s layout: the outermost thing on its
    /// way up to the scope that isn't an unfolded subgraph.
    private static func visible(_ ctx: ClusterContext, _ id: String, scope: String?) -> String {
        let up = ctx.ancestors[id] ?? []
        // The subgraphs strictly inside the scope, on the way up from `id`.
        let below = scope.flatMap { up.firstIndex(of: $0) } ?? up.count
        for k in stride(from: below - 1, through: 0, by: -1) where !ctx.unfolded.contains(up[k]) { return up[k] }
        return id
    }

    /// Lays out one scope — the whole chart (`scope == nil`) or one subgraph's
    /// interior — returning geometry in that scope's own coordinate space
    /// (origin at 0,0). Each box in it is laid out recursively first, then
    /// folded in as a placeholder; unfolded subgraphs are laid out here, with
    /// the scope's nodes, as blocks.
    private static func layoutScope(_ ctx: ClusterContext, scope: String?,
                                    inherited: Flowchart.Direction, depth: Int,
                                    measure: DiagramTextMeasurer,
                                    spacing: DiagramSpacing) -> ScopeResult {
        // An unfolded subgraph takes its parent's direction, as mermaid's does.
        let direction = scope.flatMap { ctx.subByID[$0]?.direction } ?? inherited
        let reduced = reduce(ctx, scope: scope, direction: direction)

        // Recurse into each box; wrap it in box chrome and remember both the
        // sub-layout and the placeholder size.
        var childResults: [String: ScopeResult] = [:]
        var sizeOverrides: [String: CGSize] = [:]
        for childID in reduced.boxes {
            let level = depth + (reduced.nesting[childID] ?? 0)
            let child = layoutScope(ctx, scope: childID, inherited: direction, depth: level + 1,
                                    measure: measure, spacing: spacing)
            childResults[childID] = child
            let labelW = ctx.subByID[childID].map {
                measure($0.label, nodeFontSize).width + 16
            } ?? 0
            let boxW = max(child.size.width + clusterPad * 2, labelW)
            let boxH = child.size.height + clusterHeader(measure) + clusterPad
            sizeOverrides[childID] = CGSize(width: boxW, height: boxH)
        }

        for point in reduced.standIns { sizeOverrides[point] = CGSize(width: 1, height: 1) }
        let flat = layoutFlat(reduced.chart, measure: measure, spacing: spacing,
                              sizeOverrides: sizeOverrides, blocks: reduced.blocks, clips: reduced.clips,
                              blockLoops: reduced.loops)
        let childIDSet = Set(reduced.boxes)

        // Fold each placeholder back into its sub-layout + a Container; keep
        // real nodes and the scope's edges as laid out. Blocks come first, so
        // a box inside one draws over it.
        var result = ScopeResult(nodes: [], edges: flat.edges, containers: [], size: flat.size)
        for block in flat.containers {
            result.containers.append(FlowchartLayout.Container(
                id: block.id, label: block.label, frame: block.frame,
                depth: depth + (reduced.nesting[block.id] ?? 0)))
        }
        for placed in flat.nodes where !reduced.standIns.contains(placed.id) {
            guard childIDSet.contains(placed.id), let child = childResults[placed.id] else {
                result.nodes.append(placed)
                continue
            }
            let dx = placed.frame.minX + clusterPad
            let dy = placed.frame.minY + clusterHeader(measure)
            result.containers.append(FlowchartLayout.Container(
                id: placed.id, label: ctx.subByID[placed.id]?.label ?? "",
                frame: placed.frame, depth: depth + (reduced.nesting[placed.id] ?? 0)))
            for node in child.nodes {
                result.nodes.append(FlowchartLayout.PlacedNode(
                    id: node.id, label: node.label, shape: node.shape,
                    frame: node.frame.offsetBy(dx: dx, dy: dy)))
            }
            for edge in child.edges { result.edges.append(offsetEdge(edge, dx: dx, dy: dy)) }
            for inner in child.containers {
                result.containers.append(FlowchartLayout.Container(
                    id: inner.id, label: inner.label,
                    frame: inner.frame.offsetBy(dx: dx, dy: dy), depth: inner.depth))
            }
        }
        return result
    }

    /// Each scope keeps its own edges off each other's lines, but an edge
    /// laid out in a group's interior and one laid out round it never met:
    /// one more pass over them all, nodes standing fast, self-loops fixed. A
    /// caption on a segment that moves moves with it.
    static func separatedAcrossScopes(
        _ edges: [FlowchartLayout.PlacedEdge], nodes: [FlowchartLayout.PlacedNode],
        containers: [FlowchartLayout.Container]
    ) -> [FlowchartLayout.PlacedEdge] {
        let frames = nodes.map(\.frame)
        // A self-loop starts and ends on one node, or on one group's border
        // (a loop on a box): it stands fast.
        func on(_ p: CGPoint, _ f: CGRect) -> Bool {
            p.x >= f.minX - 0.5 && p.x <= f.maxX + 0.5 && p.y >= f.minY - 0.5 && p.y <= f.maxY + 0.5
        }
        func onBorder(_ p: CGPoint, _ f: CGRect) -> Bool {
            on(p, f) && (abs(p.x - f.minX) < 0.5 || abs(p.x - f.maxX) < 0.5
                         || abs(p.y - f.minY) < 0.5 || abs(p.y - f.maxY) < 0.5)
        }
        let loops = Set(edges.indices.filter { i in
            let a = edges[i].start, b = edges[i].end
            return frames.contains { on(a, $0) && on(b, $0) }
                || containers.contains { onBorder(a, $0.frame) && onBorder(b, $0.frame) }
        })
        let before = edges.map(\.points)
        var routes = before
        separateDoubledRuns(&routes, fixed: loops, ignored: Set(edges.indices.filter { edges[$0].invisible }),
                            obstacles: frames, track: flowchartJogTrack, endRun: flowchartEndRun,
                            decisions: nodes.filter { $0.shape == .diamond }.map(\.frame))
        return edges.indices.map { i in
            let e = edges[i]
            guard routes[i] != before[i] else { return e }
            // The caption follows its segment: onto the new segment of the
            // same orientation whose line lies nearest the old one, at the
            // same place along it (held within the new segment).
            var label = e.labelPoint
            if let p = label, let k = before[i].indices.dropLast().first(where: { k in
                let a = before[i][k], b = before[i][k + 1]
                return p.x >= min(a.x, b.x) - 0.5 && p.x <= max(a.x, b.x) + 0.5
                    && p.y >= min(a.y, b.y) - 0.5 && p.y <= max(a.y, b.y) + 0.5
            }) {
                let a = before[i][k], b = before[i][k + 1]
                let horizontal = abs(a.y - b.y) < abs(a.x - b.x)
                let line = horizontal ? a.y : a.x
                let new = routes[i]
                let nearest = new.indices.dropLast().filter { j in
                    (abs(new[j].y - new[j + 1].y) < abs(new[j].x - new[j + 1].x)) == horizontal
                }.min { j, m in
                    // One spanning the caption's place first, then the nearest line.
                    func rank(_ j: Int) -> (Int, CGFloat) {
                        let c = new[j], d = new[j + 1]
                        let at = horizontal ? p.x : p.y
                        let spans = at >= min(horizontal ? c.x : c.y, horizontal ? d.x : d.y) - 0.5
                            && at <= max(horizontal ? c.x : c.y, horizontal ? d.x : d.y) + 0.5
                        return (spans ? 0 : 1, abs((horizontal ? c.y : c.x) - line))
                    }
                    return rank(j) < rank(m)
                }
                if let j = nearest {
                    let c = new[j], d = new[j + 1]
                    label = horizontal
                        ? CGPoint(x: min(max(p.x, min(c.x, d.x)), max(c.x, d.x)), y: p.y + c.y - line)
                        : CGPoint(x: p.x + c.x - line, y: min(max(p.y, min(c.y, d.y)), max(c.y, d.y)))
                }
            }
            return FlowchartLayout.PlacedEdge(
                start: routes[i].first!, end: routes[i].last!, points: routes[i],
                label: e.label, dashed: e.dashed, hasArrow: e.hasArrow, backArrow: e.backArrow,
                head: e.head, thick: e.thick, invisible: e.invisible, labelPoint: label)
        }
    }

    // MARK: - Scope resolution helpers

    /// The chain of subgraph ancestors of `id`, innermost first, terminated by
    /// `nil` (the top level). Membership is by the `containerOf` map.
    private static func chain(_ ctx: ClusterContext, _ id: String) -> [String?] {
        var out: [String?] = []
        var cur: String? = ctx.containerOf[id]
        while let c = cur { out.append(c); cur = ctx.containerOf[c] }
        out.append(nil)
        return out
    }

    /// Deepest subgraph containing BOTH endpoints, or nil (top level) — the
    /// scope whose layout owns this edge.
    private static func lca(_ ctx: ClusterContext, _ a: String, _ b: String) -> String? {
        let top = "\u{0}TOP"
        let bSet = Set(chain(ctx, b).map { $0 ?? top })
        for s in chain(ctx, a) where bSet.contains(s ?? top) { return s }
        return nil
    }

    private static func offsetEdge(_ edge: FlowchartLayout.PlacedEdge,
                                   dx: CGFloat, dy: CGFloat) -> FlowchartLayout.PlacedEdge {
        FlowchartLayout.PlacedEdge(
            start: edge.start.offsetBy(dx: dx, dy: dy),
            end: edge.end.offsetBy(dx: dx, dy: dy),
            points: edge.points.map { $0.offsetBy(dx: dx, dy: dy) },
            label: edge.label, dashed: edge.dashed, hasArrow: edge.hasArrow,
            backArrow: edge.backArrow, head: edge.head, thick: edge.thick, invisible: edge.invisible,
            labelPoint: edge.labelPoint.map { $0.offsetBy(dx: dx, dy: dy) })
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}
