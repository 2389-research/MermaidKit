import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Flowchart (layered / Sugiyama-style), sequence, and pie layout engines.
/// Split from DiagramLayout.swift for navigability; the shared placement and
/// routing primitives live there.
extension DiagramLayoutEngine {

    // MARK: Flowchart (layered / Sugiyama-style)

    private static let flowchartMargin: CGFloat = 12
    private static let flowchartLayerGap: CGFloat = 56
    private static let flowchartNodeGap: CGFloat = 26
    /// Cross-axis breadth a dummy node reserves — a narrow channel a long edge
    /// runs through, between real nodes.
    private static let dummyBreadth: CGFloat = 16
    /// Minimum separation between two edges fanned onto the same node face —
    /// 2×corner-radius (5) + arrowhead half-width (~7) + clearance.
    private static let flowchartPortSep: CGFloat = 20
    /// Track spacing for concurrent edge jogs crossing the same layer gap.
    private static let flowchartJogTrack: CGFloat = 10
    /// A cross-axis step at or below this reads as a needless zag, not a real
    /// jog — below the port/track separations (20/10) it can never be one, so
    /// `straightenJogs` collapses it onto a straight run.
    static let flowchartMinJog: CGFloat = 8
    /// Minimum visible connector stub on each side of an edge label: a labeled
    /// edge reserves `labelExtent + 2*stub` along its straight run so the line
    /// always reads on both sides of the caption.
    static let flowchartLabelStub: CGFloat = 14
    /// Length the drawn arrowhead consumes at an edge's head end, back from the
    /// route's last point. Matches `DiagramRenderer.drawArrowhead` (an 8.5pt
    /// filled head) plus the 3pt gap the flowchart renderer insets the tip from
    /// the node border (`DiagramRenderer+Flowchart`). The *labelable* run is the
    /// straight segment MINUS this at the head end (and minus a back-arrow head
    /// at the tail), so a caption centers on the arrow-FREE stretch instead of
    /// hugging the arrowhead.
    static let flowchartArrowheadLen: CGFloat = 11.5

    /// Lays out a flowchart with the layered (Sugiyama/dagre-style) pipeline:
    /// cycle-safe layer assignment, dummy-node channels for long edges,
    /// barycenter ordering, Brandes–Köpf cross coordinates, orthogonal edge
    /// routing, and collision-scored edge-label placement. Layers stack
    /// top-down, or left-to-right for an LR/RL chart. Pure geometry — the
    /// renderer only draws.
    public static func layout(_ chart: Flowchart, measure: DiagramTextMeasurer,
                              spacing: DiagramSpacing = .regular) -> FlowchartLayout {
        // Flat charts (the common case) take the algorithm below directly.
        // Subgraphs route through the recursive cluster wrapper, which lays
        // out each group's interior as its own sub-chart and places it as a
        // sized box in the parent — so this core never has to know about them.
        if chart.subgraphs.isEmpty {
            return layoutFlat(chart, measure: measure, spacing: spacing)
        }
        return layoutClustered(chart, measure: measure, spacing: spacing)
    }

    static func layoutFlat(_ chart: Flowchart, measure: DiagramTextMeasurer,
                           spacing: DiagramSpacing = .regular,
                           sizeOverrides: [String: CGSize] = [:]) -> FlowchartLayout {
        let flowchartMargin = spacing.resolvedMargin(base: Self.flowchartMargin)
        let flowchartLayerGap = spacing.resolvedLayerGap(base: Self.flowchartLayerGap)
        let flowchartNodeGap = spacing.resolvedNodeGap(base: Self.flowchartNodeGap)
        let horizontal = chart.direction == .leftRight || chart.direction == .rightLeft

        let ids = chart.nodes.map(\.id)
        let allEdges = chart.edges.map { ($0.from, $0.to) }

        // 1. Break cycles, then assign layers on the acyclic forward edges.
        let backEdges = backEdgeIndices(ids: ids, edges: allEdges)
        let forwardEdges = chart.edges.enumerated()
            .filter { !backEdges.contains($0.offset) }
            .map { ($0.element.from, $0.element.to) }
        let layerOf = assignLayers(ids: ids, edges: forwardEdges)
        let layerCount = (layerOf.values.max() ?? 0) + 1

        // 2. Insert dummy nodes for every edge spanning more than one layer
        // (forward or back). Dummies join their layer and reserve channel space
        // in ordering + placement, so a long edge routes *between* the nodes it
        // crosses rather than under them (Sugiyama/dagre-style routing). Each
        // edge's waypoint chain [u, dummies…, v] drives its route.
        var layers: [[String]] = Array(repeating: [], count: layerCount)
        for id in ids { layers[layerOf[id]!].append(id) }
        var sizes = flowchartNodeSizes(chart.nodes, measure: measure)
        // Cluster placeholders arrive pre-sized (their sub-layout dimensions
        // plus box chrome); that measurement overrides the label-based guess.
        for (id, size) in sizeOverrides { sizes[id] = size }
        var chains: [[String]] = []
        var segmentEdges: [(String, String)] = []
        var dummies: Set<String> = []
        for (index, edge) in chart.edges.enumerated() {
            guard let lu = layerOf[edge.from], let lv = layerOf[edge.to] else { chains.append([]); continue }
            let lo = min(lu, lv), hi = max(lu, lv)
            if hi - lo <= 1 {
                chains.append([edge.from, edge.to])
                segmentEdges.append((edge.from, edge.to))
                continue
            }
            var midByLayer: [(layer: Int, id: String)] = []
            for layer in (lo + 1)...(hi - 1) {
                let dummy = "\u{a7}\(index).\(layer)"
                layers[layer].append(dummy)
                sizes[dummy] = CGSize(width: dummyBreadth, height: 1)
                dummies.insert(dummy)
                midByLayer.append((layer, dummy))
            }
            let mids = (lu < lv ? midByLayer : midByLayer.reversed()).map(\.id)
            let chain = [edge.from] + mids + [edge.to]
            chains.append(chain)
            for k in 0..<(chain.count - 1) { segmentEdges.append((chain[k], chain[k + 1])) }
        }

        // 3. Order every layer (real + dummy) by barycenter; 4. assign cross
        // coordinates with Brandes–Köpf so chains and dummy channels align into
        // straight runs (the cross axis is x for TD, y for LR).
        let ordered = barycenterOrder(layers: layers, edges: segmentEdges)
        var crossBreadth: [String: CGFloat] = [:]
        for layer in ordered {
            for id in layer { crossBreadth[id] = horizontal ? (sizes[id]?.height ?? 0) : (sizes[id]?.width ?? 0) }
        }
        var crossCenter = brandesKoepfX(
            layers: ordered, segments: segmentEdges, breadth: crossBreadth,
            dummies: dummies, minGap: flowchartNodeGap)
        // 4b. Straighten near-aligned chains. BK's balancing step averages
        // four candidate alignments, so a node with an off-centre sibling
        // subtree lands NEAR its lone parent's centre but not ON it — a
        // 5-20pt jog in what should be a straight spine, with the edge label
        // sitting on the kink. Snap degree-1 connections onto their
        // neighbour's centre wherever layer gaps allow (Gansner's priority
        // method, gap-clamped).
        straightenChains(layers: ordered, segments: segmentEdges,
                         breadth: crossBreadth, minGap: flowchartNodeGap,
                         center: &crossCenter)

        // Reserve extra main-axis length on a layer boundary that carries a
        // labeled adjacent-layer edge, so the ARROW-FREE run (the straight run
        // minus the arrowhead the head end eats) still fits `labelExtent +
        // 2*stub` and the connector stays visible on each side of the caption.
        // The edge's straight run spans the layer gap, so growing the gap to
        // `arrowheadLen + labelExtent + 2*stub` guarantees an arrow-free run of
        // `labelExtent + 2*stub` — we grow the gap up front rather than
        // place-and-hope. Only the boundary the edge actually spans grows.
        var layerGaps = [CGFloat](repeating: flowchartLayerGap, count: max(layerCount, 1))
        for edge in chart.edges {
            guard let text = edge.label, !text.isEmpty,
                  let lu = layerOf[edge.from], let lv = layerOf[edge.to],
                  abs(lu - lv) == 1 else { continue }
            let sz = measure(text, labelFontSize)
            let along = horizontal ? sz.width + 6 : sz.height + 2
            let boundary = min(lu, lv)
            let headEat = edge.hasArrow ? flowchartArrowheadLen : 0
            let tailEat = edge.backArrow ? flowchartArrowheadLen : 0
            layerGaps[boundary] = max(
                layerGaps[boundary], headEat + tailEat + along + 2 * flowchartLabelStub)
        }
        let placement = placeFlowchartFrames(
            layers: ordered, sizes: sizes, crossCenter: crossCenter, horizontal: horizontal,
            layerGaps: layerGaps)

        // 5. Route each edge through its chain's waypoints.
        let (placedEdges, crossLimit) = routeChains(
            chart: chart, chains: chains, frames: placement.frames,
            horizontal: horizontal, crossExtent: placement.crossExtent,
            backEdges: backEdges
        )

        // 6. Place edge labels clear of node boxes and each other.
        let labeledEdges = placeEdgeLabels(
            placedEdges, nodeFrames: chart.nodes.compactMap { placement.frames[$0.id] }, measure: measure
        )

        let contentCross = crossLimit + flowchartMargin
        var size = horizontal
            ? CGSize(width: placement.mainContentEnd, height: contentCross)
            : CGSize(width: contentCross, height: placement.mainContentEnd)
        // Grow the canvas for any label nudged past the content box.
        for edge in labeledEdges {
            guard let lp = edge.labelPoint, let label = edge.label, !label.isEmpty else { continue }
            let sz = measure(label, labelFontSize)
            size.width = max(size.width, lp.x + sz.width / 2 + flowchartMargin)
            size.height = max(size.height, lp.y + sz.height / 2 + flowchartMargin)
        }

        let placedNodes = chart.nodes.compactMap { node -> FlowchartLayout.PlacedNode? in
            guard let frame = placement.frames[node.id] else { return nil }
            return FlowchartLayout.PlacedNode(id: node.id, label: node.label, shape: node.shape, frame: frame)
        }
        return FlowchartLayout(size: size, nodes: placedNodes, edges: labeledEdges)
    }

    /// Places each edge label centered on the LONGEST straight (axis-aligned)
    /// run of its route — never on a vertex/bend — then collision-avoids: a
    /// candidate that overlaps a node frame, another label, an edge bend, or an
    /// edge crossing, or that leaves less than `flowchartLabelStub` of visible
    /// connector on either side of the caption, is penalized so the label
    /// slides along the run, nudges perpendicular, or falls back to the next
    /// longest run until it sits on a clean, uncluttered stretch. Deterministic:
    /// runs are ranked by length with the model-order segment index breaking
    /// ties, and edges are placed in model order, so no hashed iteration reaches
    /// the geometry (issue #1).
    private static func placeEdgeLabels(
        _ edges: [FlowchartLayout.PlacedEdge],
        nodeFrames: [CGRect],
        measure: DiagramTextMeasurer
    ) -> [FlowchartLayout.PlacedEdge] {
        let labelSizes = edges.map { edge -> CGSize? in
            guard let label = edge.label, !label.isEmpty else { return nil }
            return measure(label, labelFontSize)
        }
        // The head end eats the drawn arrowhead; a bidirectional edge's tail
        // eats a second one. Subtracting these makes the placer center on the
        // arrow-FREE run instead of the full segment (so the caption stops
        // hugging the arrowhead).
        let headInsets = edges.map { $0.hasArrow ? flowchartArrowheadLen : 0 }
        let tailInsets = edges.map { $0.backArrow ? flowchartArrowheadLen : 0 }
        let anchors = placeRunLabels(routes: edges.map(\.points),
                                     labelSizes: labelSizes, nodeFrames: nodeFrames,
                                     headInsets: headInsets, tailInsets: tailInsets)
        return zip(edges, anchors).map { edge, anchor in
            anchor.map { placed(edge, at: $0) } ?? edge
        }
    }

    /// Rebuilds a placed edge with a chosen label anchor.
    private static func placed(_ edge: FlowchartLayout.PlacedEdge, at point: CGPoint) -> FlowchartLayout.PlacedEdge {
        FlowchartLayout.PlacedEdge(
            start: edge.start, end: edge.end, points: edge.points,
            label: edge.label, dashed: edge.dashed, hasArrow: edge.hasArrow,
            backArrow: edge.backArrow, labelPoint: point)
    }

    /// Comfortable clearance a caption keeps from any obstacle it does not sit
    /// on — an arrowhead tip, a foreign node box, another caption. Matched to the
    /// stub minimum so a label visibly breathes on every side (~1 cell).
    static let flowchartLabelGap: CGFloat = 12

    /// Places each caption at the MIDPOINT of a straight (axis-aligned) run of
    /// its route — the default — and nudges only when that midpoint violates a
    /// clearance. The clearance obstacles are the things a reader should see
    /// *around* the word: other edges' arrowhead tips (the endpoint region, not
    /// just the shaft), node boxes, other captions, and the interior bends /
    /// crossings of any route. When the midpoint is clear the label stays put;
    /// when it is not, the label first slides ALONG the run (staying as close to
    /// the midpoint as it can while keeping `flowchartLabelStub` of connector on
    /// each side), then nudges PERPENDICULAR, and only as a last resort falls
    /// back to the next-longest run. `labelSizes[i]` is the measured caption of
    /// route i (nil = unlabeled → no anchor). Deterministic: runs rank by length
    /// with the model-order segment index breaking ties, candidate offsets are a
    /// fixed sweep, and routes are placed in model order, so no hashed iteration
    /// reaches the geometry (issue #1). Shared by the flowchart pipeline and the
    /// layered (state/class/ER) router, so both place captions the same way.
    /// `headInsets[i]` / `tailInsets[i]` (default 0) shrink route i's labelable
    /// run at its head end (the arrowhead the head eats) and tail end (a
    /// back-arrow head), so the caption centers on the arrow-FREE stretch and
    /// keeps a real stub clear of the arrowhead. Only the terminal runs — the
    /// ones touching the route's first/last point — are shrunk.
    static func placeRunLabels(
        routes: [[CGPoint]],
        labelSizes: [CGSize?],
        nodeFrames: [CGRect],
        headInsets: [CGFloat] = [],
        tailInsets: [CGFloat] = []
    ) -> [CGPoint?] {
        let obstacles = nodeFrames.map { $0.insetBy(dx: -3, dy: -3) }
        // Fixtures every caption must avoid: the interior bends of every route
        // (a corner) and the points where two routes cross (a junction).
        var bends: [CGPoint] = []
        for pts in routes where pts.count > 2 { bends.append(contentsOf: pts[1..<(pts.count - 1)]) }
        let crossings = routeCrossingPoints(routes)
        // Arrowhead tips: the head end of every route (last point). Treated as a
        // small obstacle REGION, not just a point, so a label keeps clear of the
        // arrowhead rather than hugging it. A route's own tips are excluded when
        // scoring it — its own stub already reserves space at the run ends.
        let arrowTips: [(route: Int, p: CGPoint)] = routes.indices.compactMap {
            routes[$0].count >= 2 ? ($0, routes[$0].last!) : nil
        }
        let gap = flowchartLabelGap

        // Distance from a point to the nearest edge of a rect (0 inside/on it).
        func pointRectDistance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX)
            let dy = max(r.minY - p.y, 0, p.y - r.maxY)
            return hypot(dx, dy)
        }

        var anchors = [CGPoint?](repeating: nil, count: routes.count)
        var labelRects: [CGRect] = []

        for i in routes.indices {
            guard let sz = labelSizes[i], routes[i].count >= 2 else { continue }
            let pts = routes[i]
            let w = sz.width + 6, h = sz.height + 2
            let ownTips = [pts.first!, pts.last!]
            let hIn = i < headInsets.count ? headInsets[i] : 0
            let tIn = i < tailInsets.count ? tailInsets[i] : 0

            // Straight runs of this route (segments; the polyline is already
            // collinear-simplified, so each segment is a maximal run). lo/hi are
            // the ARROW-FREE bounds: the terminal runs are shrunk by the head /
            // tail arrowhead so the caption centers on the arrow-free stretch.
            struct Run { let horizontal: Bool; let lo: CGFloat; let hi: CGFloat; let fixed: CGFloat; let index: Int }
            var runs: [Run] = []
            for k in 0..<(pts.count - 1) {
                let a = pts[k], b = pts[k + 1]
                let dx = abs(a.x - b.x), dy = abs(a.y - b.y)
                guard max(dx, dy) > 0.5 else { continue }
                let horiz = dx >= dy
                var lo = horiz ? min(a.x, b.x) : min(a.y, b.y)
                var hi = horiz ? max(a.x, b.x) : max(a.y, b.y)
                func alongCoord(_ p: CGPoint) -> CGFloat { horiz ? p.x : p.y }
                if k == 0, tIn > 0 {                       // this run touches the tail
                    if abs(alongCoord(a) - lo) < 0.5 { lo += tIn } else { hi -= tIn }
                }
                if k == pts.count - 2, hIn > 0 {           // this run touches the head
                    if abs(alongCoord(b) - hi) < 0.5 { hi -= hIn } else { lo += hIn }
                }
                if hi < lo { let m = (lo + hi) / 2; lo = m; hi = m }   // fully eaten: hairline
                runs.append(Run(
                    horizontal: horiz, lo: lo, hi: hi,
                    fixed: horiz ? a.y : a.x, index: k))
            }
            guard !runs.isEmpty else {
                let a = pts[0], b = pts[pts.count - 1]
                let p = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                labelRects.append(CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h))
                anchors[i] = p; continue
            }
            // Longest run first; segment index breaks ties (deterministic).
            let ranked = runs.enumerated().sorted {
                let la = $0.element.hi - $0.element.lo, lb = $1.element.hi - $1.element.lo
                return la != lb ? la > lb : $0.element.index < $1.element.index
            }.map(\.element)

            var best = CGPoint(x: 0, y: 0)
            var bestScore = CGFloat.greatestFiniteMagnitude
            var haveBest = false
            for (rank, run) in ranked.enumerated() {
                let along = run.horizontal ? w : h        // caption extent along the run
                let perp = run.horizontal ? h : w         // caption extent across the run
                let mid = (run.lo + run.hi) / 2
                // Slide range along the run that keeps a full stub on each side;
                // a fine sweep so the label can settle JUST clear of an obstacle
                // instead of jumping to the far end. da = 0 is always the
                // midpoint (the default), and the |da| penalty keeps it there
                // unless a clearance forces a move.
                let slack = max(0, (run.hi - run.lo) / 2 - along / 2 - flowchartLabelStub)
                var alongShifts: [CGFloat] = [0]
                if slack > 1 {
                    let steps = 12
                    for s in 1...steps {
                        let v = slack * CGFloat(s) / CGFloat(steps)
                        alongShifts.append(v); alongShifts.append(-v)
                    }
                    // Comfort-stagger candidates: the MINIMAL slide along this run
                    // that clears the comfort gap just past an already-placed
                    // caption (measuring on the run's OWN axis). The uniform sweep
                    // above is coarse — its first step can overshoot into a
                    // neighbouring node's clearance and lose to the crowded
                    // midpoint — so we add the exact offset that opens a comfort
                    // gap and nothing more. The DOWN/RIGHT slide is offered first
                    // so the later, further-along caption is the one that yields.
                    for l in labelRects {
                        let lLo = run.horizontal ? l.minX : l.minY
                        let lHi = run.horizontal ? l.maxX : l.maxY
                        let down = (lHi + gap + along / 2 + 0.5) - mid
                        let up   = (lLo - gap - along / 2 - 0.5) - mid
                        for s in [down, up] where abs(s) <= slack { alongShifts.append(s) }
                    }
                }
                let perpNudges: [CGFloat] = [0, perp / 2 + gap / 2, -(perp / 2 + gap / 2)]
                for da in alongShifts {
                    for dp in perpNudges {
                        let cAlong = mid + da
                        let cx = run.horizontal ? cAlong : run.fixed + dp
                        let cy = run.horizontal ? run.fixed + dp : cAlong
                        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
                        var score: CGFloat = 0
                        for o in obstacles { score += overlapArea(rect, o) * 4 }
                        for l in labelRects {
                            score += overlapArea(rect, l) * 3
                            // Comfort gap: two captions that don't overlap but sit
                            // within `gap` of each other on BOTH axes still read as
                            // crowded (e.g. `fail`/`reject` on parallel vertical
                            // back-edge channels — routing-fixed x's, similar y's).
                            // `sep` is the clearance on the better-separated axis; a
                            // shortfall is penalized so the label slides ALONG its
                            // own run to open the gap. Sliding along the run is the
                            // cheapest move, so the stagger lands on the crowding
                            // axis: parallel vertical runs stagger vertically (the
                            // sweep tries the DOWN shift first, so the later/rightmost
                            // caption is pushed down), parallel horizontal runs
                            // stagger horizontally. Only bites when the gap is
                            // violated; otherwise it is 0 and the label stays put.
                            let dxGap = max(l.minX - rect.maxX, rect.minX - l.maxX, 0)
                            let dyGap = max(l.minY - rect.maxY, rect.minY - l.maxY, 0)
                            let sep = max(dxGap, dyGap)
                            if sep < gap { score += (gap - sep) * 8 }
                        }
                        let probe = rect.insetBy(dx: -1, dy: -1)
                        for v in bends where probe.contains(v) { score += 120 }
                        for x in crossings where probe.contains(x) { score += 120 }
                        // Arrowhead clearance: a foreign arrowhead tip within the
                        // comfortable gap of the caption frame is an obstacle.
                        for tip in arrowTips where tip.route != i {
                            if ownTips.contains(where: { hypot($0.x - tip.p.x, $0.y - tip.p.y) < 0.5 }) { continue }
                            let d = pointRectDistance(tip.p, rect)
                            if d < gap { score += (gap - d) * 6 }
                        }
                        // Stub on each side of the caption on this run.
                        let stub = min((cAlong - along / 2) - run.lo, run.hi - (cAlong + along / 2))
                        if stub < flowchartLabelStub { score += (flowchartLabelStub - stub) * 6 }
                        score += abs(da) * 1.4           // stay at the MIDPOINT
                        score += abs(dp) * 1.5           // prefer sitting ON the line
                        score += CGFloat(rank) * 2       // prefer the longer run
                        if rect.minX < flowchartMargin || rect.minY < flowchartMargin { score += 1_000 }
                        if !haveBest || score < bestScore {
                            bestScore = score; best = CGPoint(x: cx, y: cy); haveBest = true
                        }
                    }
                }
            }
            labelRects.append(CGRect(x: best.x - w / 2, y: best.y - h / 2, width: w, height: h))
            anchors[i] = best
        }
        return anchors
    }

    /// The points where two DIFFERENT routes' segments properly cross — the
    /// junctions a label must not sit on.
    private static func routeCrossingPoints(_ routes: [[CGPoint]]) -> [CGPoint] {
        var pts: [CGPoint] = []
        for i in routes.indices where routes[i].count >= 2 {
            for j in routes.indices where j > i && routes[j].count >= 2 {
                let pi = routes[i], pj = routes[j]
                for a in 0..<(pi.count - 1) {
                    for b in 0..<(pj.count - 1) {
                        if let p = segmentCrossPoint(pi[a], pi[a + 1], pj[b], pj[b + 1]) { pts.append(p) }
                    }
                }
            }
        }
        return pts
    }

    /// The intersection point of segments a–b and c–d when they properly cross
    /// (strictly interior to both); nil for parallel, collinear, or endpoint
    /// touches.
    static func segmentCrossPoint(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denom = r.x * s.y - r.y * s.x
        guard abs(denom) > 1e-9 else { return nil }
        let qp = CGPoint(x: c.x - a.x, y: c.y - a.y)
        let t = (qp.x * s.y - qp.y * s.x) / denom
        let u = (qp.x * r.y - qp.y * r.x) / denom
        guard t > 1e-6, t < 1 - 1e-6, u > 1e-6, u < 1 - 1e-6 else { return nil }
        return CGPoint(x: a.x + t * r.x, y: a.y + t * r.y)
    }

    /// Area of the intersection of two rects (0 when disjoint).
    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ix = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let iy = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        return ix * iy
    }

    /// Node box sizes from their labels, with per-shape adjustments
    /// (diamonds widen, circles square up, state terminals are fixed dots).
    private static func flowchartNodeSizes(
        _ nodes: [Flowchart.Node],
        measure: DiagramTextMeasurer
    ) -> [String: CGSize] {
        let paddingX: CGFloat = 14
        let paddingY: CGFloat = 9
        var sizes: [String: CGSize] = [:]
        for node in nodes {
            let text = measure(node.label, nodeFontSize)
            var size = CGSize(width: text.width + paddingX * 2, height: text.height + paddingY * 2)
            switch node.shape {
            case .diamond:
                size = CGSize(width: size.width * 1.3, height: size.height * 1.5)
            case .circle:
                let d = max(size.width, size.height)
                size = CGSize(width: d, height: d)
            case .stateStart:
                size = CGSize(width: 14, height: 14)
            case .stateEnd:
                size = CGSize(width: 18, height: 18)
            case .cylinder:
                size.height += 12   // room for the top/bottom ellipse caps
            default:
                break
            }
            if node.shape != .stateStart && node.shape != .stateEnd {
                size.width = max(size.width, 56)
            }
            sizes[node.id] = size
        }
        return sizes
    }

    /// Places the ordered layers along the main axis (down for TD, across for
    /// LR), using the Brandes–Köpf `crossCenter` for each node's cross-axis
    /// position (normalized so the leftmost/topmost edge sits at the margin).
    /// `mainContentEnd` is the final main-axis dimension (trailing layer gap
    /// trimmed, margin added); `crossExtent` is the full cross span.
    private static func placeFlowchartFrames(
        layers: [[String]],
        sizes: [String: CGSize],
        crossCenter: [String: CGFloat],
        horizontal: Bool,
        layerGaps: [CGFloat]
    ) -> (frames: [String: CGRect], mainContentEnd: CGFloat, crossExtent: CGFloat) {
        let margin = flowchartMargin

        // Normalize BK's relative coordinates so the min cross edge = margin.
        func breadth(_ id: String) -> CGFloat { horizontal ? sizes[id]!.height : sizes[id]!.width }
        var minCross = CGFloat.greatestFiniteMagnitude
        var maxCross = -CGFloat.greatestFiniteMagnitude
        for layer in layers {
            for id in layer {
                let c = crossCenter[id] ?? 0
                minCross = min(minCross, c - breadth(id) / 2)
                maxCross = max(maxCross, c + breadth(id) / 2)
            }
        }
        let shift = margin - (minCross.isFinite ? minCross : 0)
        let crossExtent = maxCross > minCross ? maxCross - minCross : 0

        var frames: [String: CGRect] = [:]
        var mainOffset = margin
        for (li, layer) in layers.enumerated() {
            let mainSize = layer.map { horizontal ? sizes[$0]!.width : sizes[$0]!.height }.max() ?? 0
            for id in layer {
                let size = sizes[id]!
                let center = (crossCenter[id] ?? 0) + shift
                if horizontal {
                    frames[id] = CGRect(
                        x: mainOffset + (mainSize - size.width) / 2,
                        y: center - size.height / 2,
                        width: size.width, height: size.height
                    )
                } else {
                    frames[id] = CGRect(
                        x: center - size.width / 2,
                        y: mainOffset + (mainSize - size.height) / 2,
                        width: size.width, height: size.height
                    )
                }
            }
            mainOffset += mainSize
            if li < layers.count - 1 {
                mainOffset += (li < layerGaps.count ? layerGaps[li] : (layerGaps.last ?? 0))
            }
        }

        return (frames, mainOffset + margin, crossExtent)
    }

    /// Routes every edge through its dummy-node waypoint chain. The exit/enter
    /// faces and direction come from the chain's geometry, so forward edges
    /// leave the bottom and enter the top while back edges go the other way;
    /// intermediate dummy centers become the bend points. Because the dummies
    /// reserved channel space in placement, the resulting polyline runs
    /// between the nodes it crosses rather than under them. Attach points are
    /// fanned across each node face so sibling edges never share a stub, and
    /// projected onto the node's actual outline (diamonds/circles) so they
    /// don't float off a bounding-box corner. Routes can push the cross
    /// dimension out, so the grown `crossLimit` is returned alongside the
    /// edges.
    private static func routeChains(
        chart: Flowchart,
        chains: [[String]],
        frames: [String: CGRect],
        horizontal: Bool,
        crossExtent: CGFloat,
        backEdges: Set<Int> = []
    ) -> (edges: [FlowchartLayout.PlacedEdge], crossLimit: CGFloat) {
        let shapeOf = Dictionary(uniqueKeysWithValues: chart.nodes.map { ($0.id, $0.shape) })

        // Projects a cross coordinate onto a node's outline on the chosen face.
        // `isSource` marks the edge's tail (the node it leaves) vs. its head.
        // Decisions are handled by `diamondPort`, never here.
        func attach(_ id: String, cross: CGFloat, rightOrBottom: Bool, isSource: Bool) -> CGPoint {
            let f = frames[id]!
            let shape = shapeOf[id] ?? .rectangle
            if horizontal {
                // Keep the attach point off the very corners of a box so an edge
                // whose channel runs past the box edge is pulled onto the face
                // rather than pinned to a corner.
                let inset = min(f.height * 0.22, f.height / 2)
                let y = min(max(cross, f.minY + inset), f.maxY - inset)
                let hh = max(f.height / 2, 0.001)
                var x = rightOrBottom ? f.maxX : f.minX
                switch shape {
                case .circle, .stateStart, .stateEnd:
                    let dx = (f.width / 2) * sqrt(max(0, 1 - pow((y - f.midY) / hh, 2)))
                    x = rightOrBottom ? f.midX + dx : f.midX - dx
                default: break
                }
                return CGPoint(x: x, y: y)
            } else {
                let inset = min(f.width * 0.22, f.width / 2)
                let x = min(max(cross, f.minX + inset), f.maxX - inset)
                let hw = max(f.width / 2, 0.001)
                var y = rightOrBottom ? f.maxY : f.minY
                switch shape {
                case .circle, .stateStart, .stateEnd:
                    let dy = (f.height / 2) * sqrt(max(0, 1 - pow((x - f.midX) / hw, 2)))
                    y = rightOrBottom ? f.midY + dy : f.midY - dy
                default: break
                }
                return CGPoint(x: x, y: y)
            }
        }

        // A decision attaches at the vertex facing its neighbor and leaves/enters
        // heading straight out of that point — the flowchart convention.
        //
        // An *incoming* edge enters on the main-axis face (top for TD, left for
        // LR; the opposite for a back edge), so flow arrives "into the top" and
        // the alignment jog happens in the layer gap — this reserves the side
        // vertices for the branches. An *outgoing* branch whose neighbor sits
        // clearly to a side (beyond ~15% of the half-width) leaves from the
        // west/east vertex with a short stub carrying it out before vertical
        // routing resumes; otherwise it leaves the south/north vertex.
        func diamondPort(_ f: CGRect, toward next: CGPoint, isSource: Bool) -> (vertex: CGPoint, stub: CGPoint?) {
            if !isSource {
                return horizontal
                    ? (CGPoint(x: next.x <= f.midX ? f.minX : f.maxX, y: f.midY), nil)
                    : (CGPoint(x: f.midX, y: next.y <= f.midY ? f.minY : f.maxY), nil)
            }
            if horizontal {
                let eps = f.height * 0.15
                let dy = next.y - f.midY
                if dy < -eps {
                    let v = CGPoint(x: f.midX, y: f.minY)
                    return (v, next.y < v.y - 1 ? CGPoint(x: v.x, y: next.y) : nil)
                } else if dy > eps {
                    let v = CGPoint(x: f.midX, y: f.maxY)
                    return (v, next.y > v.y + 1 ? CGPoint(x: v.x, y: next.y) : nil)
                }
                return (CGPoint(x: next.x >= f.midX ? f.maxX : f.minX, y: f.midY), nil)
            } else {
                let eps = f.width * 0.15
                let dx = next.x - f.midX
                if dx < -eps {
                    let v = CGPoint(x: f.minX, y: f.midY)
                    return (v, next.x < v.x - 1 ? CGPoint(x: next.x, y: v.y) : nil)
                } else if dx > eps {
                    let v = CGPoint(x: f.maxX, y: f.midY)
                    return (v, next.x > v.x + 1 ? CGPoint(x: next.x, y: v.y) : nil)
                }
                return (CGPoint(x: f.midX, y: next.y >= f.midY ? f.maxY : f.minY), nil)
            }
        }

        // The cross coordinate at which an edge descends out of its source — a
        // decision's vertex/stub, or a plain box's face port clamped toward the
        // next waypoint. Used to line the target port up with the actual run.
        func sourceExitCross(srcDiamond: Bool, from f: CGRect, toward next: CGPoint) -> CGFloat {
            if srcDiamond {
                let (v, stub) = diamondPort(f, toward: next, isSource: true)
                let p = stub ?? v
                return horizontal ? p.y : p.x
            }
            if horizontal {
                let inset = min(f.height * 0.22, f.height / 2)
                return min(max(next.y, f.minY + inset), f.maxY - inset)
            }
            let inset = min(f.width * 0.22, f.width / 2)
            return min(max(next.x, f.minX + inset), f.maxX - inset)
        }

        // Per-edge geometry, computed once so a port-distribution pass can run
        // between geometry and routing.
        struct EdgeGeo {
            var valid = false
            var chain: [String] = []
            var dummyCenters: [CGPoint] = []
            var fromFrame = CGRect.zero
            var toFrame = CGRect.zero
            var firstNext = CGPoint.zero
            var lastPrev = CGPoint.zero
            var srcDiamond = false
            var dstDiamond = false
            var exitBottom = false
            var enterBottom = false
        }
        var geos = [EdgeGeo](repeating: EdgeGeo(), count: chart.edges.count)

        // A face port request: which edge-end wants to attach to a node face,
        // and the cross coordinate it would naturally take (its channel).
        var buckets: [String: [(edge: Int, isSource: Bool, wanted: CGFloat)]] = [:]
        func faceKey(_ node: String, bottom: Bool) -> String { "\(node)|\(bottom)" }

        for index in chart.edges.indices {
            let chain = index < chains.count ? chains[index] : []
            guard chain.count >= 2,
                  let ff = frames[chain[0]], let tf = frames[chain[chain.count - 1]] else { continue }
            var g = EdgeGeo()
            g.valid = true; g.chain = chain; g.fromFrame = ff; g.toFrame = tf
            g.dummyCenters = chain[1..<(chain.count - 1)].compactMap { id in
                frames[id].map { CGPoint(x: $0.midX, y: $0.midY) }
            }
            g.firstNext = g.dummyCenters.first ?? CGPoint(x: tf.midX, y: tf.midY)
            g.lastPrev = g.dummyCenters.last ?? CGPoint(x: ff.midX, y: ff.midY)
            g.exitBottom = horizontal ? (g.firstNext.x >= ff.midX) : (g.firstNext.y >= ff.midY)
            g.enterBottom = horizontal ? (g.lastPrev.x > tf.midX) : (g.lastPrev.y > tf.midY)
            g.srcDiamond = shapeOf[chain[0]] == .diamond
            g.dstDiamond = shapeOf[chain[chain.count - 1]] == .diamond
            geos[index] = g
            if !g.srcDiamond {
                buckets[faceKey(chain[0], bottom: g.exitBottom), default: []]
                    .append((index, true, horizontal ? g.firstNext.y : g.firstNext.x))
            }
            if !g.dstDiamond {
                // The target port wants to sit where the edge actually descends,
                // not under the source's centre. For a routed (dummy) edge that
                // is the last dummy's channel; for an adjacent edge it's where
                // the source exits — so the two ends line up into a straight run
                // or a single clean bend instead of an S back to the source x.
                let wanted: CGFloat
                if g.dummyCenters.isEmpty {
                    wanted = sourceExitCross(srcDiamond: g.srcDiamond, from: ff, toward: g.firstNext)
                } else {
                    wanted = horizontal ? g.lastPrev.y : g.lastPrev.x
                }
                buckets[faceKey(chain[chain.count - 1], bottom: g.enterBottom), default: []]
                    .append((index, false, wanted))
            }
        }

        // Place each face port at the coordinate it actually wants (its channel
        // / the direction of its far endpoint), then push neighbours apart only
        // enough to keep a minimum separation. A lone edge keeps its channel and
        // stays straight; two edges that want opposite sides stay on opposite
        // sides — evenly centering them made a node's incoming edge and its
        // outgoing back edge squish together and curl into a tuning-fork.
        var portCross: [String: CGFloat] = [:]   // "edge|isSource" -> cross
        func portKey(_ edge: Int, _ isSource: Bool) -> String { "\(edge)|\(isSource)" }
        for (key, ports) in buckets {
            let node = String(key.split(separator: "|")[0])
            let f = frames[node]!
            let (lo, hi): (CGFloat, CGFloat) = horizontal
                ? (f.minY + min(f.height * 0.22, f.height / 2), f.maxY - min(f.height * 0.22, f.height / 2))
                : (f.minX + min(f.width * 0.22, f.width / 2), f.maxX - min(f.width * 0.22, f.width / 2))
            let sorted = ports.sorted { $0.wanted < $1.wanted }
            let minSep = min(flowchartPortSep, (hi - lo) / CGFloat(max(sorted.count, 1)))
            var pos = sorted.map { min(max($0.wanted, lo), hi) }
            for i in 1..<max(pos.count, 1) where pos[i] < pos[i - 1] + minSep {
                pos[i] = pos[i - 1] + minSep
            }
            if let last = pos.last, last > hi {   // block overflowed; slide it left
                let shift = last - hi
                for i in pos.indices { pos[i] -= shift }
                for i in 1..<max(pos.count, 1) where pos[i] < pos[i - 1] + minSep {
                    pos[i] = pos[i - 1] + minSep
                }
            }
            for (i, p) in sorted.enumerated() { portCross[portKey(p.edge, p.isSource)] = pos[i] }
        }

        // Give each edge entering the same target a distinct jog track, ordered
        // by its approach position, so their bend corners don't nest into one
        // another (the "double corner" where two edges turn into one box).
        var jogBias = [CGFloat](repeating: 0, count: chart.edges.count)
        var targetGroups: [String: [Int]] = [:]
        for index in chart.edges.indices where geos[index].valid {
            targetGroups[geos[index].chain[geos[index].chain.count - 1], default: []].append(index)
        }
        for idxs in targetGroups.values where idxs.count > 1 {
            let ordered = idxs.sorted {
                (horizontal ? geos[$0].lastPrev.y : geos[$0].lastPrev.x)
                    < (horizontal ? geos[$1].lastPrev.y : geos[$1].lastPrev.x)
            }
            let n = ordered.count
            for (rank, idx) in ordered.enumerated() {
                jogBias[idx] = (CGFloat(rank) - CGFloat(n - 1) / 2) * flowchartJogTrack
            }
        }

        var routes = [[CGPoint]](repeating: [], count: chart.edges.count)
        for index in chart.edges.indices {
            let g = geos[index]
            guard g.valid else { continue }

            // Head (leaves the source) and tail (enters the target). A decision
            // uses vertex ports; every other shape uses its distributed face port.
            let head: [CGPoint]
            if g.srcDiamond {
                let (v, stub) = diamondPort(g.fromFrame, toward: g.firstNext, isSource: true)
                head = stub.map { [v, $0] } ?? [v]
            } else {
                let cross = portCross[portKey(index, true)] ?? (horizontal ? g.firstNext.y : g.firstNext.x)
                head = [attach(g.chain[0], cross: cross, rightOrBottom: g.exitBottom, isSource: true)]
            }
            let tail: [CGPoint]
            if g.dstDiamond {
                let (v, stub) = diamondPort(g.toFrame, toward: g.lastPrev, isSource: false)
                tail = stub.map { [$0, v] } ?? [v]
            } else {
                let cross = portCross[portKey(index, false)] ?? (horizontal ? g.lastPrev.y : g.lastPrev.x)
                tail = [attach(g.chain[g.chain.count - 1], cross: cross, rightOrBottom: g.enterBottom, isSource: false)]
            }

            routes[index] = routePolyline(head + g.dummyCenters + tail, horizontal: horizontal, jogBias: jogBias[index])
        }

        // Separate coincident main-axis runs: two different edges whose runs
        // share a track (an incoming edge's descent and a back edge's channel
        // land on one node column) read as a single doubled line. Nudge the
        // movable run — one whose ends are interior bends, not anchored to a
        // box — aside to restore the minimum separation.
        separateRuns(&routes, horizontal: horizontal, minSep: flowchartPortSep)

        // Straighten needless zags: a waypoint (a diamond vertex vs. its dummy
        // channel, a stub vs. a face port) can step a run sideways by only a
        // cell before it resumes straight. Collapse that tiny jog so the run is
        // one straight stretch, never introducing a step where the ends could be
        // joined straight.
        straightenJogs(&routes, horizontal: horizontal, maxJog: flowchartMinJog)

        // A back edge that still threads UP THROUGH the node stack (a multi-bend
        // zigzag re-entering the occupied column, with its label crossing the
        // forward edges) reads far cleaner as a C: exit the source's side face,
        // run the return in a gutter clear of every node, and enter the target's
        // same face. Applied only when the gutter route is node-clear AND has
        // strictly fewer bends AND no more crossings — so a back edge that
        // already routes cleanly on the boundary (few bends) is left alone and
        // no fixture regresses.
        rerouteBackEdgesThroughGutter(
            &routes, backEdges: backEdges, chart: chart, frames: frames,
            horizontal: horizontal)

        var placedEdges: [FlowchartLayout.PlacedEdge] = []
        var crossLimit = flowchartMargin + crossExtent
        for f in frames.values { crossLimit = max(crossLimit, horizontal ? f.maxY : f.maxX) }
        for (index, edge) in chart.edges.enumerated() {
            var pts = routes[index]
            if pts.count < 2 {
                // The chain-based route collapsed (a cycle back-edge whose
                // waypoints degenerated, or an endpoint whose frame is missing).
                // Never ship the old `[.zero, .zero]` stub — that renders as a
                // dangling wire / stray line at the origin (issue #1). Fall back
                // to a straight border-to-border segment between the two nodes'
                // frames, so the edge is always a real, node-attached polyline.
                if let ff = frames[edge.from], let tf = frames[edge.to] {
                    let a = CGPoint(x: ff.midX, y: ff.midY)
                    let b = CGPoint(x: tf.midX, y: tf.midY)
                    pts = [rectBorderPoint(ff, toward: b), rectBorderPoint(tf, toward: a)]
                } else {
                    // Truly unresolvable (endpoint node never placed): keep the
                    // one-entry-per-edge invariant but with a zero-length point,
                    // not a spurious diagonal. Nothing to attach to.
                    let f = frames[edge.from] ?? frames[edge.to]
                    let p = f.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
                    pts = [p, p]
                }
            }
            for p in pts { crossLimit = max(crossLimit, horizontal ? p.y : p.x) }
            placedEdges.append(FlowchartLayout.PlacedEdge(
                start: pts.first!, end: pts.last!, points: pts,
                label: edge.label, dashed: edge.dashed, hasArrow: edge.hasArrow,
                    backArrow: edge.backArrow))
        }
        return (placedEdges, crossLimit)
    }

    /// Connects waypoints with an orthogonal polyline. For a top-down chart the
    /// vertical runs sit at each waypoint's x (the reserved dummy channels) and
    /// the horizontal jogs happen between consecutive waypoints — i.e. in the
    /// gaps between layers, never across a node's row. `jogBias` shifts each jog
    /// off the gap midpoint (clamped to stay in the gap) so concurrent edges
    /// crossing the same gap can take distinct tracks and their bend corners
    /// don't nest. Collinear runs are merged so straight edges stay two-point.
    static func routePolyline(_ waypoints: [CGPoint], horizontal: Bool, jogBias: CGFloat = 0) -> [CGPoint] {
        guard waypoints.count >= 2 else { return waypoints }
        var pts: [CGPoint] = [waypoints[0]]
        for i in 0..<(waypoints.count - 1) {
            let a = waypoints[i], b = waypoints[i + 1]
            if horizontal {
                if abs(a.y - b.y) > 0.5 {
                    let jx = min(max((a.x + b.x) / 2 + jogBias, min(a.x, b.x)), max(a.x, b.x))
                    pts.append(CGPoint(x: jx, y: a.y))
                    pts.append(CGPoint(x: jx, y: b.y))
                }
            } else if abs(a.x - b.x) > 0.5 {
                let midY = (a.y + b.y) / 2
                let jy = min(max(midY + jogBias, min(a.y, b.y)), max(a.y, b.y))
                pts.append(CGPoint(x: a.x, y: jy))
                pts.append(CGPoint(x: b.x, y: jy))
            }
        }
        pts.append(waypoints[waypoints.count - 1])
        return simplifyCollinear(pts)
    }

    /// Pushes apart main-axis runs (vertical for TD, horizontal for LR) that
    /// belong to different edges yet share a track — the same cross coordinate
    /// with an overlapping extent — so two edges don't render as one doubled
    /// line. Only a *movable* run is nudged: one whose two endpoints are both
    /// interior bends, so shifting its cross coordinate is absorbed by the
    /// connecting cross-axis segments without detaching an endpoint from a box.
    /// A few relaxation passes let a nudge that creates a fresh clash settle.
    static func separateRuns(_ routes: inout [[CGPoint]], horizontal: Bool, minSep: CGFloat) {
        let tol: CGFloat = 4
        func cross(_ p: CGPoint) -> CGFloat { horizontal ? p.y : p.x }
        func main(_ p: CGPoint) -> CGFloat { horizontal ? p.x : p.y }
        // Is segment (a,b) a main-axis run? (constant cross, changing main.)
        func isRun(_ a: CGPoint, _ b: CGPoint) -> Bool {
            abs(cross(a) - cross(b)) < 0.5 && abs(main(a) - main(b)) > tol
        }
        for _ in 0..<4 {
            // Collect runs: (edge, segment index, cross, mainLo, mainHi, movable).
            var runs: [(e: Int, i: Int, c: CGFloat, lo: CGFloat, hi: CGFloat, movable: Bool)] = []
            for (e, pts) in routes.enumerated() where pts.count >= 2 {
                for i in 0..<(pts.count - 1) where isRun(pts[i], pts[i + 1]) {
                    let movable = i > 0 && i + 1 < pts.count - 1
                    runs.append((e, i, cross(pts[i]),
                                 min(main(pts[i]), main(pts[i + 1])),
                                 max(main(pts[i]), main(pts[i + 1])), movable))
                }
            }
            var moved = false
            for a in 0..<runs.count {
                for b in (a + 1)..<runs.count where runs[a].e != runs[b].e {
                    let ra = runs[a], rb = runs[b]
                    guard abs(ra.c - rb.c) < tol else { continue }          // same track
                    guard min(ra.hi, rb.hi) - max(ra.lo, rb.lo) > tol else { continue } // overlap
                    let t = ra.movable ? a : (rb.movable ? b : -1)
                    guard t >= 0 else { continue }
                    let other = (t == a ? rb : ra)
                    let s = runs[t]
                    let dir: CGFloat = s.c >= other.c ? 1 : -1              // push away
                    let shift = dir * minSep - (s.c - other.c)
                    routes[s.e][s.i] = offsetCross(routes[s.e][s.i], by: shift, horizontal: horizontal)
                    routes[s.e][s.i + 1] = offsetCross(routes[s.e][s.i + 1], by: shift, horizontal: horizontal)
                    runs[t].c += shift
                    moved = true
                }
            }
            if !moved { break }
        }
        for e in routes.indices { routes[e] = simplifyCollinear(routes[e]) }
    }

    private static func offsetCross(_ p: CGPoint, by d: CGFloat, horizontal: Bool) -> CGPoint {
        horizontal ? CGPoint(x: p.x, y: p.y + d) : CGPoint(x: p.x + d, y: p.y)
    }

    /// Reroutes a back edge that threads through the node stack into a clean side
    /// channel. For each back edge whose current polyline zigzags (more than a
    /// single bend), it builds a candidate on each side of the layout — exit the
    /// source's side face, run the return along the main axis in a gutter set
    /// clear of every node, and enter the target's same face — then adopts the
    /// candidate ONLY when it is node-clear, has strictly fewer bends, and adds
    /// no crossings, choosing the side with fewer crossings (ties → the nearer
    /// gutter). A back edge already routing cleanly on the boundary is untouched,
    /// so nothing regresses. Deterministic: back edges are processed in index
    /// order and side selection is a fixed comparison.
    static func rerouteBackEdgesThroughGutter(
        _ routes: inout [[CGPoint]],
        backEdges: Set<Int>,
        chart: Flowchart,
        frames: [String: CGRect],
        horizontal: Bool
    ) {
        guard !backEdges.isEmpty else { return }
        func crossHi(_ f: CGRect) -> CGFloat { horizontal ? f.maxY : f.maxX }
        func crossLo(_ f: CGRect) -> CGFloat { horizontal ? f.minY : f.minX }
        func mainMid(_ f: CGRect) -> CGFloat { horizontal ? f.midX : f.midY }
        func makePoint(cross: CGFloat, main: CGFloat) -> CGPoint {
            horizontal ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main)
        }
        // Gutters and node-clearance use only REAL nodes: dummy channels are
        // invisible reserved space, not obstacles, so the gutter hugs the node
        // stack instead of the widest dummy.
        let realFrames = chart.nodes.compactMap { frames[$0.id] }
        let realIDs = Set(chart.nodes.map(\.id))
        guard let gutterEast = realFrames.map(crossHi).max().map({ $0 + flowchartPortSep }),
              let gutterWest = realFrames.map(crossLo).min().map({ $0 - flowchartPortSep }) else { return }

        // Straight segment (a,b) travels >6pt inside rect r's interior?
        func passesThrough(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> Bool {
            let inner = r.insetBy(dx: 2, dy: 2)
            guard inner.width > 0, inner.height > 0 else { return false }
            // Orthogonal segments only here: clip the 1-D overlap on each axis.
            let loX = min(a.x, b.x), hiX = max(a.x, b.x)
            let loY = min(a.y, b.y), hiY = max(a.y, b.y)
            let ox = max(0, min(hiX, inner.maxX) - max(loX, inner.minX))
            let oy = max(0, min(hiY, inner.maxY) - max(loY, inner.minY))
            return ox > 6 && oy > 6
        }
        func nodeClear(_ route: [CGPoint], skip: Set<String>) -> Bool {
            for (id, f) in frames where realIDs.contains(id) && !skip.contains(id) {
                for k in 0..<(route.count - 1) where passesThrough(route[k], route[k + 1], f) {
                    return false
                }
            }
            return true
        }
        func bendCount(_ route: [CGPoint]) -> Int { max(route.count - 2, 0) }
        func crossings(_ route: [CGPoint], against ignore: Int) -> Int {
            var n = 0
            for (j, other) in routes.enumerated() where j != ignore && other.count >= 2 {
                for a in 0..<(route.count - 1) {
                    for b in 0..<(other.count - 1) where segmentCrossPoint(route[a], route[a + 1], other[b], other[b + 1]) != nil {
                        n += 1
                    }
                }
            }
            return n
        }

        for index in backEdges.sorted() where index < chart.edges.count {
            let route = routes[index]
            guard route.count >= 2, bendCount(route) > 1 else { continue }
            let edge = chart.edges[index]
            guard let fs = frames[edge.from], let ft = frames[edge.to] else { continue }
            let skip: Set<String> = [edge.from, edge.to]
            let curBends = bendCount(route)
            let curCross = crossings(route, against: index)

            var chosen: [CGPoint]?
            var chosenCross = Int.max
            var chosenGutterDist = CGFloat.greatestFiniteMagnitude
            for east in [true, false] {
                let channel = east ? gutterEast : gutterWest
                // A west gutter that would fall off the canvas can't be used (we
                // can't shift the whole layout from here).
                if !east && channel < flowchartMargin { continue }
                let sCross = east ? crossHi(fs) : crossLo(fs)
                let tCross = east ? crossHi(ft) : crossLo(ft)
                let p0 = makePoint(cross: sCross, main: mainMid(fs))
                let p3 = makePoint(cross: tCross, main: mainMid(ft))
                // A diamond source/target attaches at its side vertex, which is
                // exactly (crossHi/Lo, mainMid) on this face — so the same
                // construction lands on the vertex with no special case.
                let cand = simplifyCollinear([
                    p0,
                    makePoint(cross: channel, main: mainMid(fs)),
                    makePoint(cross: channel, main: mainMid(ft)),
                    p3,
                ])
                guard nodeClear(cand, skip: skip) else { continue }
                guard bendCount(cand) < curBends else { continue }
                let candCross = crossings(cand, against: index)
                guard candCross <= curCross else { continue }
                let gutterDist = abs(channel - (east ? crossHi(fs) : crossLo(fs)))
                if candCross < chosenCross || (candCross == chosenCross && gutterDist < chosenGutterDist) {
                    chosen = cand; chosenCross = candCross; chosenGutterDist = gutterDist
                }
            }
            if let cand = chosen { routes[index] = cand }
        }
    }

    /// Removes a needless zag: a segment `b→c` that steps the route sideways
    /// (across the main axis) by at most `maxJog` while the runs before (`a→b`)
    /// and after (`c→d`) both travel ALONG the main axis. The two runs are then
    /// collinear-ish — the jog only exists because a waypoint (a diamond vertex,
    /// a face-port channel) sat a cell off the neighbouring run's track. Snap the
    /// two runs onto one track so the route reads straight. Only a run whose FAR
    /// end is an interior bend is moved, so a run anchored on a node border never
    /// detaches; when both are movable the longer run's track wins (least visual
    /// change). A few passes let a collapse that exposes another tiny jog settle.
    static func straightenJogs(_ routes: inout [[CGPoint]], horizontal: Bool, maxJog: CGFloat) {
        func cross(_ p: CGPoint) -> CGFloat { horizontal ? p.y : p.x }
        func main(_ p: CGPoint) -> CGFloat { horizontal ? p.x : p.y }
        func setCross(_ p: CGPoint, _ c: CGFloat) -> CGPoint {
            horizontal ? CGPoint(x: p.x, y: c) : CGPoint(x: c, y: p.y)
        }
        for e in routes.indices {
            var pts = routes[e]
            var pass = 0
            while pass < 6, pts.count >= 4 {
                pass += 1
                var collapsed = false
                for k in 1..<(pts.count - 2) {
                    let a = pts[k - 1], b = pts[k], c = pts[k + 1], d = pts[k + 2]
                    // b→c is a small cross step with no main travel (a pure jog).
                    let step = abs(cross(b) - cross(c))
                    guard step > 0.5, step <= maxJog, abs(main(b) - main(c)) < 0.5 else { continue }
                    // Both neighbours must be main-axis runs (constant cross).
                    guard abs(cross(a) - cross(b)) < 0.5, abs(cross(c) - cross(d)) < 0.5,
                          abs(main(a) - main(b)) > 0.5, abs(main(c) - main(d)) > 0.5 else { continue }
                    let beforeMovable = (k - 1) >= 1               // a is an interior bend
                    let afterMovable = (k + 2) <= pts.count - 2    // d is an interior bend
                    let beforeLen = abs(main(a) - main(b)), afterLen = abs(main(c) - main(d))
                    let moveAfter: Bool
                    if afterMovable && beforeMovable { moveAfter = afterLen <= beforeLen }
                    else if afterMovable { moveAfter = true }
                    else if beforeMovable { moveAfter = false }
                    else { continue }                              // neither: can't straighten safely
                    if moveAfter {                                 // after-run onto the before track
                        pts[k + 1] = setCross(c, cross(b))
                        pts[k + 2] = setCross(d, cross(b))
                    } else {                                       // before-run onto the after track
                        pts[k - 1] = setCross(a, cross(c))
                        pts[k] = setCross(b, cross(c))
                    }
                    collapsed = true
                    break
                }
                pts = simplifyCollinear(pts)
                if !collapsed { break }
            }
            routes[e] = pts
        }
    }

    /// The point on `rect`'s border where the ray from its center toward
    /// `target` exits — used by the routing fallback to land a collapsed edge on
    /// its node's actual border rather than at its center or the origin.
    static func rectBorderPoint(_ rect: CGRect, toward target: CGPoint) -> CGPoint {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - c.x, dy = target.y - c.y
        if abs(dx) < 0.0001 && abs(dy) < 0.0001 { return CGPoint(x: rect.maxX, y: c.y) }
        let hw = rect.width / 2, hh = rect.height / 2
        // Largest t in (0,1] keeping the point inside the box on both axes.
        let tx = abs(dx) < 0.0001 ? CGFloat.greatestFiniteMagnitude : hw / abs(dx)
        let ty = abs(dy) < 0.0001 ? CGFloat.greatestFiniteMagnitude : hh / abs(dy)
        let t = min(tx, ty)
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }

    /// Drops points that lie on a straight run with their neighbours, and exact
    /// duplicates, so a polyline carries only its real bends.
    static func simplifyCollinear(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out: [CGPoint] = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let a = out.last!, b = pts[i], c = pts[i + 1]
            if abs(a.x - b.x) < 0.5, abs(a.y - b.y) < 0.5 { continue }         // duplicate
            let straightH = abs(a.y - b.y) < 0.5 && abs(b.y - c.y) < 0.5
            let straightV = abs(a.x - b.x) < 0.5 && abs(b.x - c.x) < 0.5
            if straightH || straightV { continue }                            // collinear
            out.append(b)
        }
        out.append(pts[pts.count - 1])
        return out
    }

    // MARK: Sequence

    /// Lays out a sequence diagram: participant heads across the top (columns
    /// widened for adjacent-participant message labels), one message arrow per
    /// row below, self-messages as loops. Pure geometry — the renderer only
    /// draws.
    /// Any `<br …>` tag, case-insensitive: covers `<br>`, `<br/>`, `<br />`,
    /// extra whitespace, and even stray attributes (`<br class="x">`). The `\b`
    /// after `br` stops it matching words like `<brilliant>`. Compiled once.
    private static let brTagRegex =
        try? NSRegularExpression(pattern: "<br\\b[^>]*>", options: .caseInsensitive)

    /// Splits `text` into visual lines on every line-break form mermaid diagrams
    /// use interchangeably: any `<br…>` HTML tag, a literal backslash-n (`\n`,
    /// the two characters authors often type), and any real newline character
    /// (`\n`, `\r`, `\r\n`, Unicode line/paragraph separators). Each line is
    /// trimmed and empties are dropped, so stray, leading, trailing, or repeated
    /// breaks never produce blank lines. Public so the renderer draws exactly
    /// the lines the layout measured.
    public static func brLines(_ text: String) -> [String] {
        var s = text
        if let re = brTagRegex {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n")
        }
        s = s.replacingOccurrences(of: "\\n", with: "\n")   // literal backslash-n
        return s.components(separatedBy: .newlines)          // every real newline form
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Collapses every line break (see `brLines`) to a single space — for fixed
    /// single-line chrome (pie legends/titles, chart axis ticks) where wrapping
    /// would overflow a row sized for one line. Boxes that grow to their label
    /// (nodes, notes) keep the raw text and let `drawText` stack the lines.
    public static func flattenLines(_ text: String) -> String {
        let lines = brLines(text)
        return lines.isEmpty ? text.trimmingCharacters(in: .whitespaces)
                             : lines.joined(separator: " ")
    }

    public static func layout(_ diagram: SequenceDiagram, measure: DiagramTextMeasurer) -> SequenceLayout {
        let margin: CGFloat = 12
        let headPaddingX: CGFloat = 14
        let headHeight: CGFloat = 30
        let rowHeight: CGFloat = 34
        let minColumn: CGFloat = 110

        // Column widths driven by head labels and message texts.
        var columnWidth: [CGFloat] = diagram.participants.map { participant in
            max(measure(participant.label, nodeFontSize).width + headPaddingX * 2, minColumn)
        }
        var indexOf: [String: Int] = [:]
        for (i, participant) in diagram.participants.enumerated() { indexOf[participant.id] = i }
        for message in diagram.messages {
            guard let a = indexOf[message.from], let b = indexOf[message.to], abs(a - b) == 1 else { continue }
            let widest = brLines(message.text).map { measure($0, labelFontSize).width }.max() ?? 0
            let needed = widest + 24
            let lo = min(a, b)
            columnWidth[lo] = max(columnWidth[lo], needed)
        }

        var heads: [SequenceLayout.Head] = []
        var x = margin
        let boxed = Set(diagram.boxes.flatMap(\.memberIDs))
        for (i, participant) in diagram.participants.enumerated() {
            let width = columnWidth[i]
            // Boxed participants drop 12pt so the band's label has clear
            // headroom above their head boxes.
            let headY = boxed.contains(participant.id) ? margin + 12 : margin
            heads.append(SequenceLayout.Head(
                label: participant.label,
                frame: CGRect(x: x, y: headY, width: width, height: headHeight),
                isActor: participant.isActor,
                kind: participant.kind.rawValue
            ))
            x += width + 24
        }

        let arrowsTop = margin + headHeight + 18
        // ROW STREAM: messages, notes, and fragment frames consume rows in
        // exact source order, each row sized to its content — the memo's
        // "typed row stream" model. Legacy diagrams (hand-built, no events)
        // synthesize a stream from messages + anchored notes.
        var events = diagram.events
        if events.isEmpty {
            var noteIndex = 0
            let sorted = diagram.notes.enumerated()
                .sorted { ($0.element.afterMessage, $0.offset) < ($1.element.afterMessage, $1.offset) }
            for index in diagram.messages.indices {
                while noteIndex < sorted.count, sorted[noteIndex].element.afterMessage <= index {
                    events.append(.note(sorted[noteIndex].offset)); noteIndex += 1
                }
                events.append(.message(index))
            }
            while noteIndex < sorted.count { events.append(.note(sorted[noteIndex].offset)); noteIndex += 1 }
        }

        let noteRowHeight = rowHeight
        let openRowHeight: CGFloat = 24
        let dividerRowHeight: CGFloat = 22
        let closeRowHeight: CGFloat = 12

        struct OpenFrame {
            let fragment: Int
            let tabY: CGFloat
            let depth: Int
            var minX: CGFloat = .greatestFiniteMagnitude
            var maxX: CGFloat = -.greatestFiniteMagnitude
            var dividers: [SequenceLayout.Frame.Divider] = []
        }
        var arrows: [SequenceLayout.Arrow] = []
        var noteBoxes: [SequenceLayout.NoteBox] = []
        var frames: [SequenceLayout.Frame] = []
        var frameStack: [OpenFrame] = []
        // Activation bars: a per-participant stack of open bars; closing one
        // yields a depth interval on that lifeline.
        var barStack: [String: [(top: CGFloat, depth: Int)]] = [:]
        var bars: [SequenceLayout.Bar] = []
        func openBar(_ id: String, at barY: CGFloat) {
            let depth = barStack[id, default: []].count
            barStack[id, default: []].append((barY, depth))
        }
        func closeBar(_ id: String, at barY: CGFloat) {
            guard let open = barStack[id]?.popLast(),
                  let index = indexOf[id] else { return }
            bars.append(.init(x: heads[index].lifelineX, depth: open.depth,
                              top: open.top, bottom: barY))
        }
        var y = arrowsTop

        func widen(_ lo: CGFloat, _ hi: CGFloat) {
            for i in frameStack.indices {
                frameStack[i].minX = min(frameStack[i].minX, lo)
                frameStack[i].maxX = max(frameStack[i].maxX, hi)
            }
        }

        for event in events {
            switch event {
            case .message(let index):
                let message = diagram.messages[index]
                guard let a = indexOf[message.from], let b = indexOf[message.to] else { continue }
                let isSelf = a == b
                let toX = isSelf ? heads[a].lifelineX + 34 : heads[b].lifelineX
                // Multiline labels stack above the arrow: the row grows.
                let extraLines = CGFloat(max(brLines(message.text).count - 1, 0)) * 12
                arrows.append(SequenceLayout.Arrow(
                    fromX: heads[a].lifelineX, toX: toX,
                    y: y + extraLines + rowHeight - 14,
                    text: message.text, dashed: message.dashed,
                    isSelfMessage: isSelf, head: message.head, number: message.number))
                widen(min(heads[a].lifelineX, toX), max(heads[a].lifelineX, toX))
                let arrowY = y + extraLines + rowHeight - 14
                if message.activatesTarget { openBar(message.to, at: arrowY) }
                if message.deactivatesSender { closeBar(message.from, at: arrowY) }
                y += rowHeight + extraLines
            case .note(let index):
                let noteItem = diagram.notes[index]
                let ids = noteItem.ids.compactMap { indexOf[$0] }
                guard !ids.isEmpty else { y += noteRowHeight; continue }
                let lines = brLines(noteItem.text)
                let textWidth = lines.map { measure($0, labelFontSize).width }.max() ?? 0
                let boxHeight = max(noteRowHeight - 10, CGFloat(lines.count) * 13 + 9)
                var frame: CGRect
                switch noteItem.position {
                case .rightOf:
                    frame = CGRect(x: heads[ids[0]].lifelineX + 12, y: y + 4,
                                   width: textWidth + 16, height: boxHeight)
                case .leftOf:
                    let x1 = heads[ids[0]].lifelineX - 12
                    frame = CGRect(x: x1 - textWidth - 16, y: y + 4,
                                   width: textWidth + 16, height: boxHeight)
                case .over:
                    let lo = heads[ids.min()!].lifelineX
                    let hi = heads[ids.max()!].lifelineX
                    let spanWidth = max(hi - lo + 48, textWidth + 16)
                    frame = CGRect(x: (lo + hi) / 2 - spanWidth / 2, y: y + 4,
                                   width: spanWidth, height: boxHeight)
                }
                frame.origin.x = max(frame.origin.x, 2)
                noteBoxes.append(.init(text: noteItem.text, frame: frame))
                widen(frame.minX, frame.maxX)
                y += boxHeight + 10
            case .open(let fragment):
                frameStack.append(OpenFrame(fragment: fragment, tabY: y, depth: frameStack.count))
                y += openRowHeight
            case .divider(let fragment, let label):
                if let top = frameStack.lastIndex(where: { $0.fragment == fragment }) {
                    frameStack[top].dividers.append(.init(y: y + dividerRowHeight / 2, label: label))
                }
                y += dividerRowHeight
            case .activate(let id):
                openBar(id, at: y + 4)   // consumes no row; the bar starts here
            case .deactivate(let id):
                closeBar(id, at: y + 4)
            case .create(let id):
                // The participant's head drops to this row; its lifeline
                // starts here instead of at the top.
                if let index = indexOf[id] {
                    heads[index].frame.origin.y = y + 4
                    widen(heads[index].frame.minX, heads[index].frame.maxX)
                }
                y += rowHeight
            case .destroy(let id):
                if let index = indexOf[id] {
                    heads[index].lifelineEndY = y + 10
                    heads[index].showsDestroyCross = true
                    closeBar(id, at: y + 10)   // any open bar dies with it
                }
                y += 18
            case .close(let fragment):
                guard let top = frameStack.lastIndex(where: { $0.fragment == fragment }) else { continue }
                let open = frameStack.remove(at: top)
                let spec = diagram.fragments[open.fragment]
                // Content extent, or the full participant span when empty;
                // nesting depth pads outward so sibling borders never touch.
                var lo = open.minX, hi = open.maxX
                if lo > hi {
                    lo = heads.first?.lifelineX ?? margin
                    hi = heads.last?.lifelineX ?? lo
                }
                let pad: CGFloat = 18
                let labelWidth = measure((spec.label ?? ""), labelFontSize).width
                    + measure(spec.kind.rawValue, labelFontSize).width + 40
                let rect = CGRect(x: lo - pad - CGFloat(open.depth) * 6,
                                  y: open.tabY + 4,
                                  width: max(hi - lo + 2 * pad + CGFloat(open.depth) * 12, labelWidth),
                                  height: y - open.tabY + closeRowHeight - 8)
                frames.append(.init(kind: spec.kind.rawValue, label: spec.label,
                                    rect: rect, dividers: open.dividers))
                widen(rect.minX, rect.maxX)
                y += closeRowHeight
            }
        }
        // Outermost first so the renderer paints outer frames beneath inner.
        frames.sort { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }
        // Bars the author never deactivated run to the lifeline bottom.
        for (id, opens) in barStack {
            guard let index = indexOf[id] else { continue }
            for open in opens {
                bars.append(.init(x: heads[index].lifelineX, depth: open.depth,
                                  top: open.top, bottom: y + 4))
            }
        }

        let bottom = max(y, arrowsTop + rowHeight)
        // Self-message labels sit to the right of the loop; widen the canvas
        // so a self-message on the last lifeline doesn't clip its label.
        var width = x - 24 + margin
        for arrow in arrows where arrow.isSelfMessage && !arrow.text.isEmpty {
            let labelRight = arrow.toX + 8 + measure(arrow.text, labelFontSize).width
            width = max(width, labelRight + margin)
        }
        for box in noteBoxes { width = max(width, box.frame.maxX + margin) }
        for frame in frames { width = max(width, frame.rect.maxX + margin) }

        // Box bands: full-height background groups around member heads.
        var boxBands: [SequenceLayout.BoxBand] = []
        for (index, box) in diagram.boxes.enumerated() {
            let members = box.memberIDs.compactMap { indexOf[$0] }
            guard !members.isEmpty else { continue }
            let lo = members.map { heads[$0].frame.minX }.min()! - 8
            let hi = members.map { heads[$0].frame.maxX }.max()! + 8
            boxBands.append(.init(
                label: box.label,
                rect: CGRect(x: lo, y: margin - 6,
                             width: hi - lo, height: bottom - margin + 12),
                colorIndex: index))
        }

        return SequenceLayout(
            size: CGSize(width: width, height: bottom + margin),
            heads: heads,
            lifelineBottom: bottom,
            arrows: arrows,
            notes: noteBoxes,
            frames: frames,
            bars: bars,
            boxBands: boxBands
        )
    }

    // MARK: Pie

    /// Lays out a pie chart: slice angles from the value fractions (clockwise
    /// from 12 o'clock), a legend column right of the disk, and left padding
    /// reserved so a title wider than the disk never clips. Pure geometry —
    /// the renderer only draws.
    public static func layout(_ pie: PieChart, measure: DiagramTextMeasurer) -> PieLayout {
        let margin: CGFloat = 14
        let radius: CGFloat = 76
        let titleHeight: CGFloat = pie.title == nil ? 0 : 26

        let total = pie.slices.reduce(0) { $0 + $1.value }
        var slices: [PieLayout.Slice] = []
        var angle = -Double.pi / 2
        for (index, slice) in pie.slices.enumerated() {
            let fraction = total > 0 ? slice.value / total : 0
            let sweep = fraction * 2 * .pi
            slices.append(PieLayout.Slice(
                // Legend/title are fixed single-line chrome: collapse any line
                // break to a space so a `<br/>` in a slice name doesn't wrap a
                // legend row (which is a fixed 20pt tall).
                label: flattenLines(slice.label),
                value: slice.value,
                fraction: fraction,
                startAngle: angle,
                endAngle: angle + sweep,
                colorIndex: index
            ))
            angle += sweep
        }

        let legendWidth = slices
            .map { measure("\($0.label) (0000)", labelFontSize).width + 22 }
            .max() ?? 80
        let legendHeight = CGFloat(pie.slices.count) * 20

        // The title is centred horizontally on the disk's centre (the renderer
        // draws it there). A long title is far wider than the disk, so unless
        // the disk is padded away from the left edge its left half spills off
        // canvas. Reserve enough left padding that the whole title clears x = 0,
        // and widen the canvas so its right half is bounded too. The width is
        // estimated as the larger of the measured glyph run and the scene
        // lowering's estimatedLabelSize heuristic, so both the render and the
        // geometry check fit.
        let flatTitle = pie.title.map(flattenLines)   // single-line chrome
        let titleWidth: CGFloat = flatTitle.map { title in
            max(measure(title, 12.5).width, DiagramScene.estimatedLabelSize(title).width)
        } ?? 0
        let leftPad = max(margin, titleWidth / 2 - radius + margin)
        let centerX = leftPad + radius
        let legendX = centerX + radius + 28

        let contentRight = legendX + legendWidth + margin
        let titleRight = centerX + titleWidth / 2 + margin
        let width = max(contentRight, titleRight)
        let height = margin + titleHeight + max(radius * 2, legendHeight) + margin
        return PieLayout(
            size: CGSize(width: width, height: height),
            center: CGPoint(x: centerX, y: margin + titleHeight + radius),
            radius: radius,
            title: flatTitle,
            slices: slices,
            legendOrigin: CGPoint(
                x: legendX,
                y: margin + titleHeight + max(0, (radius * 2 - legendHeight) / 2)
            )
        )
    }

}

extension DiagramLayoutEngine {
    /// Post-placement straightening (Gansner et al. §4.2 "priority method",
    /// reduced to the degree-1 case): a node whose sole in-segment comes from
    /// `u` wants `center[v] == center[u]`; a node whose sole out-segment goes
    /// to `v` wants the same from below. Alternating down and up sweeps snap
    /// those chains straight, each move clamped so the node keeps `minGap` to
    /// its layer neighbours — the pass can only realign, never overlap.
    /// Dummy nodes participate, so long-edge channels straighten too.
    static func straightenChains(
        layers: [[String]], segments: [(String, String)],
        breadth: [String: CGFloat], minGap: CGFloat,
        center: inout [String: CGFloat]
    ) {
        var inSegs: [String: [String]] = [:], outSegs: [String: [String]] = [:]
        for (from, to) in segments {
            inSegs[to, default: []].append(from)
            outSegs[from, default: []].append(to)
        }

        func snap(_ id: String, in layer: [String], at index: Int, toward target: CGFloat) {
            let current = center[id] ?? 0
            guard abs(target - current) > 0.01 else { return }
            var lo = -CGFloat.greatestFiniteMagnitude
            var hi = CGFloat.greatestFiniteMagnitude
            let half = (breadth[id] ?? 0) / 2
            if index > 0 {
                let left = layer[index - 1]
                lo = (center[left] ?? 0) + (breadth[left] ?? 0) / 2 + minGap + half
            }
            if index + 1 < layer.count {
                let right = layer[index + 1]
                hi = (center[right] ?? 0) - (breadth[right] ?? 0) / 2 - minGap - half
            }
            guard lo <= hi else { return }
            let clamped = min(max(target, lo), hi)
            // Only move when it strictly improves alignment to the target.
            if abs(clamped - target) < abs(current - target) { center[id] = clamped }
        }

        for _ in 0..<3 {
            // Down sweep: align each single-parent node under that parent.
            for layer in layers {
                for (index, id) in layer.enumerated() {
                    if let parents = inSegs[id], parents.count == 1,
                       let t = center[parents[0]] {
                        snap(id, in: layer, at: index, toward: t)
                    }
                }
            }
            // Up sweep: align each single-child node over that child.
            for layer in layers.reversed() {
                for (index, id) in layer.enumerated() {
                    if let children = outSegs[id], children.count == 1,
                       let t = center[children[0]] {
                        snap(id, in: layer, at: index, toward: t)
                    }
                }
            }
        }
    }
}
