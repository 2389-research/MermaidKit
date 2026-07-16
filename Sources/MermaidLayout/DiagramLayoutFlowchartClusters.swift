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
extension DiagramLayoutEngine {

    /// Header strip reserved at the top of every group box for its label.
    private static let clusterHeader: CGFloat = 22
    /// Interior padding between a group's box and its contents (and the gap
    /// below the header before content starts is `clusterHeader`).
    private static let clusterPad: CGFloat = 12

    static func layoutClustered(_ chart: Flowchart, measure: DiagramTextMeasurer,
                                spacing: DiagramSpacing) -> FlowchartLayout {
        // Membership: node/subgraph id -> its innermost containing subgraph id
        // (absent = top level). Built once, read throughout the recursion.
        var containerOf: [String: String] = [:]
        for sub in chart.subgraphs {
            for nid in sub.nodeIDs { containerOf[nid] = sub.id }
            for cid in sub.childIDs { containerOf[cid] = sub.id }
        }
        let nodeByID = Dictionary(chart.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let subByID = Dictionary(chart.subgraphs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let ctx = ClusterContext(chart: chart, containerOf: containerOf,
                                 nodeByID: nodeByID, subByID: subByID)
        let scope = layoutScope(ctx, scope: nil, inherited: chart.direction, depth: 0,
                                measure: measure, spacing: spacing)
        return FlowchartLayout(size: scope.size, nodes: scope.nodes,
                               edges: scope.edges, containers: scope.containers)
    }

    /// Immutable per-diagram lookup tables shared across the recursion. The
    /// measurer is threaded as a parameter, not stored, so it stays
    /// non-escaping (the public `layout` closure is not `@escaping`).
    private struct ClusterContext {
        let chart: Flowchart
        let containerOf: [String: String]
        let nodeByID: [String: Flowchart.Node]
        let subByID: [String: Flowchart.Subgraph]
    }

    private struct ScopeResult {
        var nodes: [FlowchartLayout.PlacedNode]
        var edges: [FlowchartLayout.PlacedEdge]
        var containers: [FlowchartLayout.Container]
        var size: CGSize
    }

    /// Lays out one scope — the whole chart (`scope == nil`) or one subgraph's
    /// interior — returning geometry in that scope's own coordinate space
    /// (origin at 0,0). Direct child subgraphs are laid out recursively first,
    /// then folded in as placeholders.
    private static func layoutScope(_ ctx: ClusterContext, scope: String?,
                                    inherited: Flowchart.Direction, depth: Int,
                                    measure: DiagramTextMeasurer,
                                    spacing: DiagramSpacing) -> ScopeResult {
        // 1. Direct members of this scope.
        let directNodeIDs: [String]
        let directChildIDs: [String]
        let direction: Flowchart.Direction
        if let scope, let sub = ctx.subByID[scope] {
            directNodeIDs = sub.nodeIDs
            directChildIDs = sub.childIDs
            direction = sub.direction ?? inherited
        } else {
            directNodeIDs = ctx.chart.nodes.filter { ctx.containerOf[$0.id] == nil }.map(\.id)
            directChildIDs = ctx.chart.subgraphs.filter { ctx.containerOf[$0.id] == nil }.map(\.id)
            direction = inherited
        }

        // 2. Recurse into each direct child subgraph; wrap it in box chrome and
        //    remember both the sub-layout and the placeholder size.
        var childResults: [String: ScopeResult] = [:]
        var sizeOverrides: [String: CGSize] = [:]
        for childID in directChildIDs {
            let child = layoutScope(ctx, scope: childID, inherited: direction, depth: depth + 1,
                                    measure: measure, spacing: spacing)
            childResults[childID] = child
            let labelW = ctx.subByID[childID].map {
                measure($0.label, nodeFontSize).width + 16
            } ?? 0
            let boxW = max(child.size.width + clusterPad * 2, labelW)
            let boxH = child.size.height + clusterHeader + clusterPad
            sizeOverrides[childID] = CGSize(width: boxW, height: boxH)
        }

        // 3. Build the reduced flat chart for this scope: real member nodes plus
        //    one placeholder node per child group; edges resolved to their
        //    representative here (deduplicated so two arrows into the same group
        //    don't stack).
        var reducedNodes: [Flowchart.Node] = directNodeIDs.compactMap { ctx.nodeByID[$0] }
        for childID in directChildIDs {
            reducedNodes.append(Flowchart.Node(id: childID, label: "", shape: .rectangle))
        }
        var reducedEdges: [Flowchart.Edge] = []
        var seenEdges = Set<String>()
        for edge in ctx.chart.edges {
            guard lca(ctx, edge.from, edge.to) == scope else { continue }
            let from = rep(ctx, edge.from, scope: scope)
            let to = rep(ctx, edge.to, scope: scope)
            guard from != to else { continue }
            let key = "\(from)\u{1}\(to)\u{1}\(edge.label ?? "")\u{1}\(edge.dashed)\u{1}\(edge.hasArrow)\u{1}\(edge.backArrow)"
            guard seenEdges.insert(key).inserted else { continue }
            reducedEdges.append(Flowchart.Edge(from: from, to: to, label: edge.label,
                                               dashed: edge.dashed, hasArrow: edge.hasArrow,
                                               backArrow: edge.backArrow))
        }

        let reduced = Flowchart(direction: direction, nodes: reducedNodes, edges: reducedEdges)
        let flat = layoutFlat(reduced, measure: measure, spacing: spacing,
                              sizeOverrides: sizeOverrides)
        let childIDSet = Set(directChildIDs)

        // 4. Fold each placeholder back into its sub-layout + a Container; keep
        //    real nodes and the parent-level edges as laid out.
        var result = ScopeResult(nodes: [], edges: flat.edges, containers: [], size: flat.size)
        for placed in flat.nodes {
            guard childIDSet.contains(placed.id), let child = childResults[placed.id] else {
                result.nodes.append(placed)
                continue
            }
            let dx = placed.frame.minX + clusterPad
            let dy = placed.frame.minY + clusterHeader
            result.containers.append(FlowchartLayout.Container(
                id: placed.id, label: ctx.subByID[placed.id]?.label ?? "",
                frame: placed.frame, depth: depth))
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

    /// The ancestor of `id` that is a DIRECT child of `scope` — the node or
    /// child-group that represents `id` in `scope`'s reduced layout.
    private static func rep(_ ctx: ClusterContext, _ id: String, scope: String?) -> String {
        var cur = id
        while ctx.containerOf[cur] != scope {
            guard let next = ctx.containerOf[cur] else { return cur }
            cur = next
        }
        return cur
    }

    private static func offsetEdge(_ edge: FlowchartLayout.PlacedEdge,
                                   dx: CGFloat, dy: CGFloat) -> FlowchartLayout.PlacedEdge {
        FlowchartLayout.PlacedEdge(
            start: edge.start.offsetBy(dx: dx, dy: dy),
            end: edge.end.offsetBy(dx: dx, dy: dy),
            points: edge.points.map { $0.offsetBy(dx: dx, dy: dy) },
            label: edge.label, dashed: edge.dashed, hasArrow: edge.hasArrow,
            backArrow: edge.backArrow,
            labelPoint: edge.labelPoint.map { $0.offsetBy(dx: dx, dy: dy) })
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}
