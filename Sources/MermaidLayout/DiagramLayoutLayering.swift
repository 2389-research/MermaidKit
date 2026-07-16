import Foundation

// Layer assignment for the layered (Sugiyama) family — flowcharts and the
// class/ER/state box diagrams.
//
// The old strategy was longest-path: correct, but it shoves every node as
// deep as its longest chain allows, stretching edges and inflating the
// canvas. The industry-standard replacement (ELK Layered's and Graphviz
// dot's default) is NETWORK SIMPLEX layering — Gansner, Koutsofios, North &
// Vo, "A Technique for Drawing Directed Graphs" (1993), §2: minimize the sum
// of edge lengths Σ (layer(head) − layer(tail)) subject to every edge
// spanning ≥ 1 layer. Shorter edges → tighter, wider, more readable layouts.
extension DiagramLayoutEngine {

    /// Minimum-total-edge-length layer assignment (network simplex), with the
    /// longest-path result as both the initial feasible solution and the
    /// fallback if the optimizer hits its iteration cap. Input edges must be
    /// acyclic (callers strip back-edges first); self-edges are ignored.
    static func assignLayers(ids: [String], edges: [(String, String)]) -> [String: Int] {
        let longest = longestPathLayers(ids: ids, edges: edges)
        guard ids.count > 2, !edges.isEmpty else { return longest }

        // Index the graph. Parallel edges are kept (they weight the objective
        // like Gansner's multi-edges); self-edges never constrain layering.
        var indexOf: [String: Int] = [:]
        for (i, id) in ids.enumerated() where indexOf[id] == nil { indexOf[id] = i }
        let n = ids.count
        var edgeList: [(tail: Int, head: Int)] = []
        for (from, to) in edges {
            guard let u = indexOf[from], let v = indexOf[to], u != v else { continue }
            edgeList.append((u, v))
        }
        guard !edgeList.isEmpty else { return longest }

        var rank = [Int](repeating: 0, count: n)
        for (id, i) in indexOf { rank[i] = longest[id] ?? 0 }

        // Optimize each weakly-connected component independently (the tight
        // spanning tree needs a connected graph).
        var componentOf = [Int](repeating: -1, count: n)
        var componentCount = 0
        var adjacency = [[Int]](repeating: [], count: n)
        for (index, e) in edgeList.enumerated() {
            adjacency[e.tail].append(index)
            adjacency[e.head].append(index)
        }
        for start in 0..<n where componentOf[start] == -1 {
            var stack = [start]
            componentOf[start] = componentCount
            while let node = stack.popLast() {
                for ei in adjacency[node] {
                    let other = edgeList[ei].tail == node ? edgeList[ei].head : edgeList[ei].tail
                    if componentOf[other] == -1 { componentOf[other] = componentCount; stack.append(other) }
                }
            }
            componentCount += 1
        }

        for component in 0..<componentCount {
            let nodes = (0..<n).filter { componentOf[$0] == component }
            guard nodes.count > 1 else { continue }
            let localEdges = edgeList.indices.filter { componentOf[edgeList[$0].tail] == component }
            guard !localEdges.isEmpty else { continue }
            if !networkSimplex(nodes: nodes, edgeIndices: localEdges, edges: edgeList,
                               rank: &rank, adjacency: adjacency) {
                // Optimizer bailed (iteration cap): restore longest-path ranks
                // for this component — feasible and known-good.
                for i in nodes { rank[i] = longest[ids[i]] ?? 0 }
            }
        }

        // Normalize each component to start at layer 0 (matches the old
        // behavior, which every caller assumes).
        var minOfComponent = [Int](repeating: .max, count: componentCount)
        for i in 0..<n { minOfComponent[componentOf[i]] = min(minOfComponent[componentOf[i]], rank[i]) }
        var result: [String: Int] = [:]
        for (id, i) in indexOf { result[id] = rank[i] - minOfComponent[componentOf[i]] }
        // Duplicated ids (shouldn't happen, but the old code tolerated them):
        for id in ids where result[id] == nil { result[id] = 0 }
        return result
    }

    /// The previous strategy, kept as seed + fallback: relax until every edge
    /// spans at least one layer.
    static func longestPathLayers(ids: [String], edges: [(String, String)]) -> [String: Int] {
        var layerOf: [String: Int] = [:]
        for id in ids { layerOf[id] = 0 }
        for _ in 0..<(ids.count + 1) {
            var changed = false
            for (from, to) in edges {
                guard let a = layerOf[from], let b = layerOf[to] else { continue }
                if b < a + 1 { layerOf[to] = a + 1; changed = true }
            }
            if !changed { break }
        }
        return layerOf
    }

    /// Gansner et al. network simplex on one connected component. Returns
    /// false if the iteration cap was hit (caller falls back).
    private static func networkSimplex(
        nodes: [Int], edgeIndices: [Int], edges: [(tail: Int, head: Int)],
        rank: inout [Int], adjacency: [[Int]]
    ) -> Bool {
        let inComponent = Set(nodes)
        func slack(_ ei: Int) -> Int { rank[edges[ei].head] - rank[edges[ei].tail] - 1 }

        // --- feasible tight tree ------------------------------------------
        // Grow a spanning tree of slack-0 edges; when stuck, shift the tree's
        // ranks by the minimum slack of any edge leaving it, which tightens
        // that edge without breaking feasibility.
        var inTree = Set<Int>()          // node set
        var treeEdges = Set<Int>()       // edge-index set
        inTree.insert(nodes[0])
        while inTree.count < nodes.count {
            // Add every tight edge reachable from the current tree.
            var grew = true
            while grew {
                grew = false
                // Sorted iteration: Set order is unspecified, and layer
                // assignment must be bit-for-bit reproducible (ELK's
                // "consider model order" starts with determinism).
                for node in inTree.sorted() {
                    for ei in adjacency[node] where !treeEdges.contains(ei) {
                        let e = edges[ei]
                        guard inComponent.contains(e.tail), inComponent.contains(e.head) else { continue }
                        let other = e.tail == node ? e.head : e.tail
                        if !inTree.contains(other), slack(ei) == 0 {
                            inTree.insert(other); treeEdges.insert(ei); grew = true
                        }
                    }
                }
            }
            if inTree.count == nodes.count { break }
            // Minimum-slack edge with exactly one endpoint in the tree.
            var best: (ei: Int, delta: Int)?
            for ei in edgeIndices {
                let e = edges[ei]
                let tailIn = inTree.contains(e.tail), headIn = inTree.contains(e.head)
                guard tailIn != headIn else { continue }
                let s = slack(ei)
                let delta = tailIn ? s : -s   // shift tree so this edge tightens
                if best == nil || abs(s) < abs(slack(best!.ei)) { best = (ei, delta) }
            }
            guard let found = best else { return false }   // disconnected?? bail
            for node in inTree { rank[node] += found.delta }
        }

        // --- optimize ------------------------------------------------------
        // Cut value of a tree edge = (edges tail-side → head-side) minus
        // (head-side → tail-side). Negative means the layering shrinks by
        // swapping it out. Recomputed from scratch each iteration — O(V·E),
        // fine at diagram scale (≤ maxEdges).
        func tailComponent(removing cut: Int) -> Set<Int> {
            var side = Set([edges[cut].tail])
            var stack = [edges[cut].tail]
            while let node = stack.popLast() {
                for ei in adjacency[node] where treeEdges.contains(ei) && ei != cut {
                    let e = edges[ei]
                    let other = e.tail == node ? e.head : e.tail
                    if inComponent.contains(other), !side.contains(other) {
                        side.insert(other); stack.append(other)
                    }
                }
            }
            return side
        }

        let cap = 8 * edgeIndices.count + 64
        for _ in 0..<cap {
            var swapped = false
            for cut in treeEdges.sorted() {
                let tailSide = tailComponent(removing: cut)
                var cutValue = 0
                for ei in edgeIndices {
                    let e = edges[ei]
                    if tailSide.contains(e.tail), !tailSide.contains(e.head) { cutValue += 1 }
                    if !tailSide.contains(e.tail), tailSide.contains(e.head) { cutValue -= 1 }
                }
                guard cutValue < 0 else { continue }
                // Entering edge: head-side → tail-side with minimum slack.
                var enter: Int?
                for ei in edgeIndices where ei != cut {
                    let e = edges[ei]
                    if !tailSide.contains(e.tail), tailSide.contains(e.head) {
                        if enter == nil || slack(ei) < slack(enter!) { enter = ei }
                    }
                }
                guard let entering = enter else { continue }
                let s = slack(entering)
                if s > 0 { for node in tailSide { rank[node] -= s } }
                treeEdges.remove(cut)
                treeEdges.insert(entering)
                swapped = true
                break
            }
            if !swapped { return true }   // optimal: no negative cut values
        }
        return false
    }
}
