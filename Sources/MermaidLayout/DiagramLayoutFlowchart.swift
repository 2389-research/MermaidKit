import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Flowchart (layered / Sugiyama-style), sequence, and pie layout engines.
/// Split from DiagramLayout.swift for navigability; the shared placement and
/// routing primitives live there.
extension DiagramLayoutEngine {

    // MARK: Flowchart (layered / Sugiyama-style)

    static let flowchartMargin: CGFloat = 12
    private static let flowchartLayerGap: CGFloat = 56
    private static let flowchartNodeGap: CGFloat = 26
    /// Cross-axis breadth a dummy node reserves — a narrow channel a long edge
    /// runs through, between real nodes.
    private static let dummyBreadth: CGFloat = 16
    /// Minimum separation between two edges fanned onto the same node face —
    /// 2×corner-radius (5) + arrowhead half-width (~7) + clearance.
    private static let flowchartPortSep: CGFloat = 20
    /// Track spacing for concurrent edge jogs crossing the same layer gap.
    static let flowchartJogTrack: CGFloat = 10
    /// A cross-axis step at or below this reads as a needless zag, not a real
    /// jog — below the port/track separations (20/10) it can never be one, so
    /// `straightenJogs` collapses it onto a straight run.
    static let flowchartMinJog: CGFloat = 8
    /// The shortest straight run a bending route leaves or meets a node on:
    /// an arrowhead and the shortest step, so no end reads as a hook
    /// (`edge-end-hooked`).
    static let flowchartEndRun: CGFloat = flowchartArrowheadLen + flowchartMinJog
    /// Minimum visible connector stub on each side of an edge label: a labeled
    /// edge reserves `labelExtent + 2*stub` along its straight run so the line
    /// always reads on both sides of the caption. Shared by BOTH routers — the
    /// flowchart placer here AND the layered self-loop sizing in `DiagramLayout`
    /// — so a single source of truth keeps the two connector reservations in
    /// step (hence the family-neutral name, not `flowchart…`).
    static let edgeLabelStub: CGFloat = 14
    /// Length the drawn arrowhead consumes at an edge's head end, back from the
    /// route's last point. Matches `DiagramRenderer.drawArrowhead` (an 8.5pt
    /// filled head) plus the 3pt gap the flowchart renderer insets the tip from
    /// the node border (`DiagramRenderer+Flowchart`). The *labelable* run is the
    /// straight segment MINUS this at the head end (and minus a back-arrow head
    /// at the tail), so a caption centers on the arrow-FREE stretch instead of
    /// hugging the arrowhead.
    static let flowchartArrowheadLen: CGFloat = 11.5
    /// Space between a double circle's rings (the renderers inset the inner
    /// ring by this much).
    static let doubleCircleGap: CGFloat = 4
    /// The most ranks longer links (`--->`) add to one chart. Each is a node
    /// for layering, which is quadratic in nodes, so a chart of maximum-length
    /// links at the edge cap would otherwise take tens of seconds; real charts
    /// stretch a link or two.
    static let maxExtraRanks = 100

    /// The outline of a slanted node (`[/…/]`, `[\…\]`, `[/…\]`, `[\…/]`) or a
    /// flag (`>…]`) inscribed in `f`, clockwise from the top left; nil for any
    /// other shape. The slant (and the flag's notch) is the hexagon's end
    /// inset. Edge ports and `RenderScene` share it; the CoreGraphics renderer
    /// draws the same points.
    static func polygonOutline(_ shape: Flowchart.NodeShape, in f: CGRect) -> [CGPoint]? {
        let s = min(f.width * 0.22, f.height / 2)
        switch shape {
        case .parallelogram:
            return [CGPoint(x: f.minX + s, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                    CGPoint(x: f.maxX - s, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)]
        case .parallelogramAlt:
            return [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX - s, y: f.minY),
                    CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX + s, y: f.maxY)]
        case .trapezoid:
            return [CGPoint(x: f.minX + s, y: f.minY), CGPoint(x: f.maxX - s, y: f.minY),
                    CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)]
        case .trapezoidAlt:
            return [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                    CGPoint(x: f.maxX - s, y: f.maxY), CGPoint(x: f.minX + s, y: f.maxY)]
        case .asymmetric:
            return [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                    CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY),
                    CGPoint(x: f.minX + s, y: f.midY)]
        default:
            return nil
        }
    }

    /// Where a line crosses a polygon's outline: a horizontal line at `y`
    /// (giving x) when `atY`, else a vertical line at `value` (giving y). The
    /// far crossing (right or bottom) when `far`, else the near one.
    static func outlineCrossing(_ polygon: [CGPoint], at value: CGFloat,
                                atY: Bool, far: Bool) -> CGFloat? {
        var hits: [CGFloat] = []
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let (a0, a1, b0, b1) = atY ? (a.y, a.x, b.y, b.x) : (a.x, a.y, b.x, b.y)
            guard a0 != b0, min(a0, b0) <= value, value <= max(a0, b0) else { continue }
            hits.append(a1 + (value - a0) / (b0 - a0) * (b1 - a1))
        }
        return far ? hits.max() : hits.min()
    }

    /// Lays out a flowchart with the layered (Sugiyama/dagre-style) pipeline:
    /// cycle-safe layer assignment, dummy-node channels for long edges,
    /// barycenter ordering, Brandes–Köpf cross coordinates, orthogonal edge
    /// routing, and collision-scored edge-label placement. Layers stack
    /// top-down, or left-to-right for an LR/RL chart. Pure geometry — the
    /// renderer only draws.
    public static func layout(_ chart: Flowchart, measure: DiagramTextMeasurer,
                              spacing: DiagramSpacing = .regular) -> FlowchartLayout {
        DiagramTextScale.run(spacing, measure) { measure in
            scaledLayout(chart, measure: measure, spacing: spacing)
        }
    }

    /// ``layout(_:measure:spacing:)`` with `measure` already at the text scale.
    private static func scaledLayout(_ chart: Flowchart, measure: DiagramTextMeasurer,
                                     spacing: DiagramSpacing) -> FlowchartLayout {
        // Flat charts (the common case) take the algorithm below directly.
        // Subgraphs route through the recursive cluster wrapper, which lays
        // out each group's interior as its own sub-chart and places it as a
        // sized box in the parent — so this core never has to know about them.
        let raw = chart.subgraphs.isEmpty
            ? layoutFlat(chart, measure: measure, spacing: spacing)
            : layoutClustered(chart, measure: measure, spacing: spacing)
        // Opt-in grid snap, applied at the single dispatch both render paths and
        // the lint IR call — so all three see identical snapped geometry.
        if let unit = spacing.gridSnap, unit > 0 {
            return GridQuantizer.quantize(raw, unit: unit)
        }
        return raw
    }

    static func layoutFlat(_ chart: Flowchart, measure: DiagramTextMeasurer,
                           spacing: DiagramSpacing = .regular,
                           sizeOverrides: [String: CGSize] = [:],
                           blocks: [FlowBlock] = [],
                           clips: [Int: (from: Int?, to: Int?)] = [:],
                           blockLoops: [(block: Int, edge: Flowchart.Edge)] = []) -> FlowchartLayout {
        let flowchartMargin = spacing.resolvedMargin(base: Self.flowchartMargin)
        let flowchartLayerGap = spacing.resolvedLayerGap(base: Self.flowchartLayerGap)
        let flowchartNodeGap = spacing.resolvedNodeGap(base: Self.flowchartNodeGap)
        let horizontal = chart.direction == .leftRight || chart.direction == .rightLeft

        let ids = chart.nodes.map(\.id)
        let allEdges = chart.edges.map { ($0.from, $0.to) }

        // 1. Break cycles, then assign layers on the acyclic forward edges. A
        // longer link (`--->`, length 2) ranks through stand-in nodes, one per
        // extra rank, so its ends sit at least `length` layers apart — up to
        // `maxExtraRanks` stand-ins a chart, past which links rank as length 1.
        let backEdges = backEdgeIndices(ids: ids, edges: allEdges)
        var rankIDs = ids
        var forwardEdges: [(String, String)] = []
        var extraRanks = 0
        for (index, edge) in chart.edges.enumerated() where !backEdges.contains(index) {
            let length = min(edge.length, 1 + maxExtraRanks - extraRanks)
            guard length > 1, edge.from != edge.to else {
                forwardEdges.append((edge.from, edge.to))
                continue
            }
            extraRanks += length - 1
            var tail = edge.from
            for step in 1..<length {
                let standIn = "\u{a7}len\(index).\(step)"
                rankIDs.append(standIn)
                forwardEdges.append((tail, standIn))
                tail = standIn
            }
            forwardEdges.append((tail, edge.to))
        }
        let layerOf = assignLayers(ids: rankIDs, edges: forwardEdges)
        let layerCount = (ids.compactMap { layerOf[$0] }.max() ?? 0) + 1

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
        var dummyEdge: [String: Int] = [:]
        for (index, edge) in chart.edges.enumerated() {
            guard let lu = layerOf[edge.from], let lv = layerOf[edge.to] else { chains.append([]); continue }
            let lo = min(lu, lv), hi = max(lu, lv)
            if hi - lo <= 1 {
                chains.append([edge.from, edge.to])
                // A self-loop links no two nodes, so it must not count as a
                // neighbour in ordering or chain straightening.
                if edge.from != edge.to { segmentEdges.append((edge.from, edge.to)) }
                continue
            }
            var midByLayer: [(layer: Int, id: String)] = []
            for layer in (lo + 1)...(hi - 1) {
                let dummy = "\u{a7}\(index).\(layer)"
                layers[layer].append(dummy)
                sizes[dummy] = CGSize(width: dummyBreadth, height: 1)
                dummies.insert(dummy)
                dummyEdge[dummy] = index
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
        // Unfolded subgraphs (#103): each spans its members' layers, with a
        // border node either side in every one, and orders as a block.
        var plan: BlockPlan?
        if !blocks.isEmpty {
            var p = planBlocks(blocks, layerOf: layerOf)
            for (dummy, index) in dummyEdge {
                let edge = chart.edges[index]
                if let b = p.common(p.blockOf[edge.from], p.blockOf[edge.to]) { p.blockOf[dummy] = b }
            }
            for (id, side) in p.border {
                let b = side.left && horizontal ? clusterHeader(measure) : 0
                sizes[id] = horizontal ? CGSize(width: 1, height: b) : CGSize(width: b, height: 1)
            }
            plan = p
        }
        var ordered = plan.map { blockedBarycenterOrder(layers: layers, edges: segmentEdges, plan: $0) }
            ?? barycenterOrder(layers: layers, edges: segmentEdges)
        let selfLoops = selfLoopPaths(chart, sizes: sizes, horizontal: horizontal, measure: measure)
        // A looped node keeps its loop and caption clear of its row
        // neighbours: a blank stand-in right after it in its layer, on the
        // cross-far side where the loop runs, holds the space out to the
        // caption's outer edge. Nothing is reserved on the near side.
        for (index, loop) in selfLoops.sorted(by: { $0.key < $1.key }) where loop.isOutermost {
            guard let layer = layerOf[loop.node],
                  let at = ordered[layer].firstIndex(of: loop.node) else { continue }
            let room = "\u{a7}loop\(index)"
            let breadth = max(0, loop.clearance - flowchartLabelGap - flowchartNodeGap)
            sizes[room] = horizontal ? CGSize(width: 1, height: breadth) : CGSize(width: breadth, height: 1)
            ordered[layer].insert(room, at: at + 1)
        }
        var crossBreadth: [String: CGFloat] = [:]
        for layer in ordered {
            for id in layer { crossBreadth[id] = horizontal ? (sizes[id]?.height ?? 0) : (sizes[id]?.width ?? 0) }
        }
        // A block's borders are chains, layer to layer, that BK aligns like a
        // long edge's stand-ins, so its sides come out straight.
        var bkSegments = segmentEdges
        var bkDummies = dummies
        if let plan {
            for (b, span) in plan.span.enumerated() {
                guard let span else { continue }
                for left in [true, false] {
                    for l in span.lo...span.hi {
                        bkDummies.insert(plan.borderID(b, l, left: left))
                        if l < span.hi { bkSegments.append((plan.borderID(b, l, left: left), plan.borderID(b, l + 1, left: left))) }
                    }
                }
            }
        }
        var crossCenter = brandesKoepfX(
            layers: ordered, segments: bkSegments, breadth: crossBreadth,
            dummies: bkDummies, minGap: flowchartNodeGap)
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
        // A captioned two-cycle's edges run side by side across their gap,
        // and one may bend near its source to keep them uncrossed
        // (`orderJogsInGaps`): its gap holds the caption past that bend too,
        // an arrowhead further from the one at its end.
        var captionedLinks: Set<[String]> = []
        let decisions = Set(chart.nodes.filter { $0.shape == .diamond }.map(\.id))
        for edge in chart.edges where !edge.invisible && !(edge.label ?? "").isEmpty && edge.from != edge.to
            && edge.hasArrow && !edge.backArrow && !decisions.contains(edge.from) && !decisions.contains(edge.to) {
            captionedLinks.insert([edge.from, edge.to])
        }
        for edge in chart.edges where !edge.invisible {
            guard let text = edge.label, !text.isEmpty,
                  let lu = layerOf[edge.from], let lv = layerOf[edge.to],
                  abs(lu - lv) == 1 else { continue }
            let sz = measure(text, labelFontSize)
            let along = horizontal ? sz.width + 6 : sz.height + 2
            let boundary = min(lu, lv)
            let headEat = edge.hasArrow ? flowchartArrowheadLen : 0
            let tailEat = edge.backArrow ? flowchartArrowheadLen : 0
            let either = captionedLinks.contains([edge.from, edge.to]) && captionedLinks.contains([edge.to, edge.from])
                ? flowchartArrowheadLen : 0
            // One that bends stops an end run short of its arrowhead, not just
            // the arrowhead, so it isn't a hook: its gap holds that too.
            let bends = edge.hasArrow && abs((crossCenter[edge.from] ?? 0) - (crossCenter[edge.to] ?? 0)) > 0.5
                ? flowchartEndRun - flowchartArrowheadLen : 0
            layerGaps[boundary] = max(
                layerGaps[boundary], headEat + tailEat + along + 2 * edgeLabelStub + either + bends)
        }
        // Captioned edges meeting one node across one gap run side by side
        // off that face. Where their captions, stacked across the flow, are
        // more than the face can hold, they sit one after another along their
        // runs instead (the placer staggers them), and the gap holds them all,
        // with a stub between and beyond, and the bend and arrowhead past them.
        var faceCaptions: [String: [CGFloat]] = [:], faceBreadth: [String: CGFloat] = [:]
        var faceGap: [String: Int] = [:]
        for edge in chart.edges where !edge.invisible && edge.from != edge.to {
            guard let text = edge.label, !text.isEmpty,
                  let lu = layerOf[edge.from], let lv = layerOf[edge.to], abs(lu - lv) == 1 else { continue }
            let sz = measure(text, labelFontSize)
            let (along, across) = horizontal ? (sz.width + 6, sz.height + 2) : (sz.height + 2, sz.width + 6)
            for node in [edge.from, edge.to] {
                let key = "\(node)|\(min(lu, lv))"
                faceCaptions[key, default: []].append(along)
                faceBreadth[key, default: 0] += across + 2
                faceGap[key] = min(lu, lv)
            }
        }
        for (key, alongs) in faceCaptions where alongs.count > 1 {
            let node = String(key[..<key.lastIndex(of: "|")!])
            guard let gap = faceGap[key], let breadth = crossBreadth[node], faceBreadth[key]! > breadth else { continue }
            let stub = DiagramLayoutLinter.minCaptionStub
            layerGaps[gap] = max(layerGaps[gap], alongs.reduce(0, +) + CGFloat(alongs.count + 1) * stub
                                 + flowchartEndRun + flowchartArrowheadLen)
        }
        // A self-loop's bars stand off the node's main-axis faces into the
        // neighbouring layer gaps; keep the gap's middle, where other edges
        // jog, clear of them, and every track a jog takes off that middle for
        // its fan-in and fan-out (`routeChains`' jog bias, `fanJogBias`, from
        // the same `jogFanGroups`). A loop in the first or last layer stands
        // off into the margin instead, which then grows to fit it.
        let fans = jogFanGroups(chart, chains: chains)
        var gapJogBias = [CGFloat](repeating: 0, count: max(layerCount, 1))
        for (target, idxs) in fans.into {
            for index in idxs {
                let source = chains[index][0]
                guard let lu = layerOf[source], let lv = layerOf[target], lu != lv else { continue }
                // The fan-out's tracks in the gap the edge leaves by, the
                // fan-in's in the one it enters by.
                let into = jogSpread(idxs.count), out = jogSpread(fans.outOf[source]?.count ?? 1)
                let (first, last) = lu < lv ? (lu, lv - 1) : (lu - 1, lv)
                for (gap, spread) in first == last ? [(first, out + into)] : [(first, out), (last, into)] {
                    gapJogBias[gap] = max(gapJogBias[gap], spread)
                }
            }
        }
        // Every one of those tracks fits in its gap, an end run clear of each
        // face (#108): no jog bends under an arrowhead or against a node. A fan's tracks are spaced by its rank in cross
        // order, which growing a gap leaves alone, so a gap wide enough here
        // never clamps a jog onto a node's face, where fans would share it.
        for gap in gapJogBias.indices where gap < layerGaps.count && gapJogBias[gap] > 0 {
            layerGaps[gap] = max(layerGaps[gap], 2 * (gapJogBias[gap] + flowchartEndRun))
        }
        var leadPad: CGFloat = 0, tailPad: CGFloat = 0
        for loop in selfLoops.values {
            guard let layer = layerOf[loop.node] else { continue }
            func needed(_ gap: Int) -> CGFloat {
                2 * (loop.excursion + flowchartJogTrack + gapJogBias[gap]) + 4
            }
            if layer > 0 { layerGaps[layer - 1] = max(layerGaps[layer - 1], needed(layer - 1)) } else { leadPad = max(leadPad, loop.excursion) }
            if layer < layerCount - 1 { layerGaps[layer] = max(layerGaps[layer], needed(layer)) } else { tailPad = max(tailPad, loop.excursion) }
        }
        // Each block's header and padding take room in the layer gaps
        // before and after it, so its box clears the rows outside it.
        var blockChrome: [(lead: CGFloat, tail: CGFloat)] = []
        let loopRuns = blockLoopRuns(blockLoops, blocks: blocks.count, horizontal: horizontal, measure: measure)
        if let plan {
            blockChrome = blockMainChrome(plan, layers: ordered, sizes: sizes, horizontal: horizontal,
                                          layerGaps: &layerGaps, leadPad: &leadPad, tailPad: &tailPad,
                                          margin: flowchartMargin, measure: measure, minLength: loopRuns.length)
        }
        // Clear each block's rows of everything outside it, wide enough for
        // its label across the top of a top-down box (the layer gaps above are
        // all known, and none depends on cross coordinates).
        if let plan {
            let minWidth = blocks.map { horizontal ? 0 : measure($0.label, nodeFontSize).width + 16 }
            // A captioned edge naming a block, to a node beside the box, leaves
            // it from the side, and is cut at the box: that node stands off by
            // the caption and a stub either side, as a layer gap would.
            var apart: [(String, String, CGFloat)] = []
            for (index, clip) in clips.sorted(by: { $0.key < $1.key }) {
                let edge = chart.edges[index]
                guard let text = edge.label, !text.isEmpty, !edge.invisible else { continue }
                let sz = measure(text, labelFontSize)
                let along = (horizontal ? sz.height + 2 : sz.width + 6) + 2 * edgeLabelStub
                    + (edge.hasArrow ? flowchartArrowheadLen : 0) + (edge.backArrow ? flowchartArrowheadLen : 0)
                for (b, other) in [(clip.from, edge.to), (clip.to, edge.from)] {
                    guard let b, let span = plan.span[b], let l = layerOf[other],
                          span.lo <= l, l <= span.hi, plan.blockOf[other].map({ plan.isAncestor(b, of: $0) }) != true,
                          let row = ordered.first(where: { $0.contains(other) }),
                          let at = row.firstIndex(of: other),
                          let left = row.firstIndex(of: plan.borderID(b, l, left: true)) else { continue }
                    let half = (crossBreadth[other] ?? 0) / 2
                    if at > left {
                        apart.append((plan.borderID(b, l, left: false), other, half + along))
                    } else {
                        apart.append((other, plan.borderID(b, l, left: true), half + along))
                    }
                }
            }
            // A block's own loop runs off its cross-far side over the rows its
            // far run spans: whatever is beyond the box there stands off by the
            // loop's reach and the caption beside it.
            if !blockLoops.isEmpty {
                var bands: [(start: CGFloat, end: CGFloat)] = []
                var offset = Self.flowchartMargin + leadPad
                for (li, layer) in ordered.enumerated() {
                    let size = layer.map { horizontal ? sizes[$0]!.width : sizes[$0]!.height }.max() ?? 0
                    bands.append((offset, offset + size))
                    offset += size + (li < layerGaps.count ? layerGaps[li] : (layerGaps.last ?? 0))
                }
                for loop in loopRuns.runs {
                    let b = loop.block
                    guard let span = plan.span[b], span.hi < bands.count else { continue }
                    let lead = bands[span.lo].start - blockChrome[b].lead
                    for l in span.lo...span.hi
                    where bands[l].end >= lead + loop.near && bands[l].start <= lead + loop.far {
                        guard let row = ordered.first(where: { $0.contains(plan.borderID(b, l, left: false)) }),
                              let at = row.firstIndex(of: plan.borderID(b, l, left: false)), at + 1 < row.count else { continue }
                        let next = row[at + 1]
                        apart.append((plan.borderID(b, l, left: false), next,
                                      loop.reach + loop.beside + flowchartNodeGap + (crossBreadth[next] ?? 0) / 2))
                    }
                }
            }
            clearBlocks(center: &crossCenter, layers: ordered, breadth: crossBreadth,
                        minGap: flowchartNodeGap, plan: plan, minWidth: minWidth, apart: apart)
        }

        let placement = placeFlowchartFrames(
            layers: ordered, sizes: sizes, crossCenter: crossCenter, horizontal: horizontal,
            layerGaps: layerGaps, leadPad: leadPad, tailPad: tailPad)
        var containers: [FlowchartLayout.Container] = []
        var blockFrames: [CGRect?] = Array(repeating: nil, count: blocks.count)
        if let plan {
            for (b, span) in plan.span.enumerated() {
                guard let span,
                      let l = placement.frames[plan.borderID(b, span.lo, left: true)],
                      let r = placement.frames[plan.borderID(b, span.lo, left: false)] else { continue }
                let lead = placement.bands[span.lo].start - blockChrome[b].lead
                let tail = placement.bands[span.hi].end + blockChrome[b].tail
                let frame = horizontal
                    ? CGRect(x: lead, y: l.minY, width: tail - lead, height: r.maxY - l.minY)
                    : CGRect(x: l.minX, y: lead, width: r.maxX - l.minX, height: tail - lead)
                blockFrames[b] = frame
                containers.append(FlowchartLayout.Container(id: blocks[b].id, label: blocks[b].label,
                                                            frame: frame, depth: plan.depth[b]))
            }
        }

        // 5. Route each edge through its chain's waypoints.
        var (placedEdges, crossLimit) = routeChains(
            chart: chart, chains: chains, frames: placement.frames,
            horizontal: horizontal, crossExtent: placement.crossExtent,
            backEdges: backEdges, selfLoops: selfLoops,
            gaps: zip(placement.bands, placement.bands.dropFirst()).map { ($0.end, $1.start) },
            captionRuns: Dictionary(uniqueKeysWithValues: chart.edges.indices.compactMap { index in
                guard let text = chart.edges[index].label, !text.isEmpty else { return nil }
                let sz = measure(text, labelFontSize)
                return (index, (horizontal ? sz.width + 6 : sz.height + 2) + 2 * DiagramLayoutLinter.minCaptionStub)
            })
        )
        // An edge naming an unfolded subgraph ranks with one of its nodes,
        // and ends where it reaches the subgraph's box.
        for (index, clip) in clips.sorted(by: { $0.key < $1.key }) where index < placedEdges.count {
            var points = placedEdges[index].points
            if let b = clip.to, let box = blockFrames[b], let cut = clippedEntering(points, box) { points = cut }
            if let b = clip.from, let box = blockFrames[b],
               let cut = clippedEntering(points.reversed(), box) { points = cut.reversed() }
            let e = placedEdges[index]
            placedEdges[index] = FlowchartLayout.PlacedEdge(
                start: points.first!, end: points.last!, points: points,
                label: e.label, dashed: e.dashed, hasArrow: e.hasArrow, backArrow: e.backArrow,
                head: e.head, thick: e.thick, invisible: e.invisible)
        }

        // An unfolded subgraph's own loop: a C off its box's cross-far side,
        // from its leading corner. Its caption rides its far run, placed with
        // every other caption.
        var loopEdges: [FlowchartLayout.PlacedEdge] = []
        for (loop, (b, edge)) in zip(loopRuns.runs, blockLoops) {
            guard let box = blockFrames[b] else { continue }
            let lead = horizontal ? box.minX : box.minY
            let near = lead + loop.near, far = lead + loop.far
            let side = horizontal ? box.maxY : box.maxX, out = side + loop.reach
            func point(main: CGFloat, cross: CGFloat) -> CGPoint {
                horizontal ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main)
            }
            let points = [point(main: near, cross: side), point(main: near, cross: out),
                          point(main: far, cross: out), point(main: far, cross: side)]
            loopEdges.append(FlowchartLayout.PlacedEdge(
                start: points[0], end: points[3], points: points, label: edge.label, dashed: edge.dashed,
                hasArrow: edge.hasArrow, backArrow: edge.backArrow, head: edge.head, thick: edge.thick,
                invisible: edge.invisible))
        }

        // 6. Place edge labels clear of node boxes and each other. A
        // self-loop's caption rides its far run, the run its space was
        // reserved beside, even where a bar is longer; so does a box's own.
        let labeledEdges = placeEdgeLabels(
            placedEdges + loopEdges, nodeFrames: chart.nodes.compactMap { placement.frames[$0.id] }, measure: measure,
            labelRuns: chart.edges.indices.map { selfLoops[$0] == nil ? nil : SelfLoopPath.farRunSegment }
                + loopEdges.map { _ in 1 }
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
        for box in containers {
            size.width = max(size.width, box.frame.maxX + flowchartMargin)
            size.height = max(size.height, box.frame.maxY + flowchartMargin)
        }
        for edge in loopEdges {
            for p in edge.points {
                size.width = max(size.width, p.x + flowchartMargin)
                size.height = max(size.height, p.y + flowchartMargin)
            }
        }
        return FlowchartLayout(size: size, nodes: placedNodes, edges: labeledEdges, containers: containers)
    }

    /// Places each edge label centered on the LONGEST straight (axis-aligned)
    /// run of its route — never on a vertex/bend — then collision-avoids: a
    /// candidate that overlaps a node frame, another label, an edge bend, or an
    /// edge crossing, or that leaves less than `edgeLabelStub` of visible
    /// connector on either side of the caption, is penalized so the label
    /// slides along the run, nudges perpendicular, or falls back to the next
    /// longest run until it sits on a clean, uncluttered stretch. Deterministic:
    /// runs are ranked by length with the model-order segment index breaking
    /// ties, and edges are placed in model order, so no hashed iteration reaches
    /// the geometry (issue #1).
    private static func placeEdgeLabels(
        _ edges: [FlowchartLayout.PlacedEdge],
        nodeFrames: [CGRect],
        measure: DiagramTextMeasurer,
        labelRuns: [Int?] = []
    ) -> [FlowchartLayout.PlacedEdge] {
        let labelSizes = edges.map { edge -> CGSize? in
            // An invisible link draws no label either.
            guard !edge.invisible, let label = edge.label, !label.isEmpty else { return nil }
            return measure(label, labelFontSize)
        }
        // The head end eats the drawn arrowhead; a bidirectional edge's tail
        // eats a second one. Subtracting these makes the placer center on the
        // arrow-FREE run instead of the full segment (so the caption stops
        // hugging the arrowhead).
        let headInsets = edges.map { $0.hasArrow ? flowchartArrowheadLen : 0 }
        let tailInsets = edges.map { $0.backArrow ? flowchartArrowheadLen : 0 }
        // An invisible link is no obstacle: no bend, crossing or tip to avoid.
        let anchors = placeRunLabels(routes: edges.map { $0.invisible ? [] : $0.points },
                                     labelSizes: labelSizes, nodeFrames: nodeFrames,
                                     headInsets: headInsets, tailInsets: tailInsets,
                                     labelRuns: labelRuns)
        return zip(edges, anchors).map { edge, anchor in
            anchor.map { placed(edge, at: $0) } ?? edge
        }
    }

    /// Rebuilds a placed edge with a chosen label anchor.
    private static func placed(_ edge: FlowchartLayout.PlacedEdge, at point: CGPoint) -> FlowchartLayout.PlacedEdge {
        FlowchartLayout.PlacedEdge(
            start: edge.start, end: edge.end, points: edge.points,
            label: edge.label, dashed: edge.dashed, hasArrow: edge.hasArrow,
            backArrow: edge.backArrow, head: edge.head, thick: edge.thick,
            invisible: edge.invisible, labelPoint: point)
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
    /// the midpoint as it can while keeping `edgeLabelStub` of connector on
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
    /// `labelRuns[i]` (default nil) limits route i's caption to that one
    /// segment, for a route whose space was reserved beside a given run.
    static func placeRunLabels(
        routes: [[CGPoint]],
        labelSizes: [CGSize?],
        nodeFrames: [CGRect],
        headInsets: [CGFloat] = [],
        tailInsets: [CGFloat] = [],
        labelRuns: [Int?] = []
    ) -> [CGPoint?] {
        // Nothing to place: no obstacle needs reading.
        guard routes.indices.contains(where: { $0 < labelSizes.count && labelSizes[$0] != nil && routes[$0].count >= 2 }) else {
            return [CGPoint?](repeating: nil, count: routes.count)
        }
        let obstacles = nodeFrames.map { $0.insetBy(dx: -3, dy: -3) }
        // Fixtures every caption must avoid: the interior bends of every route
        // (a corner) and the points where two routes cross (a junction).
        var bends: [CGPoint] = []
        for pts in routes where pts.count > 2 { bends.append(contentsOf: pts[1..<(pts.count - 1)]) }
        let crossings = routeCrossingPoints(routes)
        // Every term of a candidate's score is zero for an obstacle that isn't
        // near it, and adding zero leaves a sum exactly as it was, so each
        // candidate reads only what a grid finds near it, in the same order as
        // before: the placement is bit for bit the all-pairs one, in near-linear
        // time.
        let obstacleGrid = PlacementGrid(obstacles)
        let bendGrid = PlacementGrid(points: bends)
        let crossingGrid = PlacementGrid(points: crossings)
        // Arrowhead tips: the head end of every route (last point). Treated as a
        // small obstacle REGION, not just a point, so a label keeps clear of the
        // arrowhead rather than hugging it. A route's own tips are excluded when
        // scoring it — its own stub already reserves space at the run ends.
        let arrowTips: [(route: Int, p: CGPoint)] = routes.indices.compactMap {
            routes[$0].count >= 2 ? ($0, routes[$0].last!) : nil
        }
        let tipGrid = PlacementGrid(arrowTips.map { CGRect(origin: $0.p, size: .zero) })
        let gap = flowchartLabelGap

        // Distance from a point to the nearest edge of a rect (0 inside/on it).
        func pointRectDistance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX)
            let dy = max(r.minY - p.y, 0, p.y - r.maxY)
            return hypot(dx, dy)
        }

        var anchors = [CGPoint?](repeating: nil, count: routes.count)
        var labelRects: [CGRect] = []
        var labelGrid = PlacementGrid([])
        func placeLabel(_ rect: CGRect) {
            labelGrid.insert(labelRects.count, rect)
            labelRects.append(rect)
        }

        for i in routes.indices {
            guard let sz = labelSizes[i], routes[i].count >= 2 else { continue }
            let pts = routes[i]
            let w = sz.width + 6, h = sz.height + 2
            let hIn = i < headInsets.count ? headInsets[i] : 0
            let tIn = i < tailInsets.count ? tailInsets[i] : 0

            // Straight runs of this route (segments; the polyline is already
            // collinear-simplified, so each segment is a maximal run). lo/hi are
            // the ARROW-FREE bounds: the terminal runs are shrunk by the head /
            // tail arrowhead so the caption centers on the arrow-free stretch.
            struct Run { let horizontal: Bool; let lo: CGFloat; let hi: CGFloat; let fixed: CGFloat; let index: Int }
            var runs: [Run] = []
            let onlyRun = i < labelRuns.count ? labelRuns[i] : nil
            for k in 0..<(pts.count - 1) where onlyRun == nil || onlyRun == k {
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
                placeLabel(CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h))
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
                let slack = max(0, (run.hi - run.lo) / 2 - along / 2 - edgeLabelStub)
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
                // A shift offered twice scores the same twice, and only a
                // strictly lower score wins, so a repeat can't change the pick.
                var offered: Set<CGFloat> = []
                alongShifts = alongShifts.filter { offered.insert($0).inserted }
                let perpNudges: [CGFloat] = [0, perp / 2 + gap / 2, -(perp / 2 + gap / 2)]
                for da in alongShifts {
                    for dp in perpNudges {
                        let cAlong = mid + da
                        let cx = run.horizontal ? cAlong : run.fixed + dp
                        let cy = run.horizontal ? run.fixed + dp : cAlong
                        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
                        // The score's tail: what this candidate pays however
                        // clear it is. Every term before it is at least 0, and
                        // adding the same terms in the same order is monotone,
                        // so the tail summed from 0 bounds the score from
                        // below. A candidate whose bound already reaches the
                        // best can't win (only a strictly lower score does),
                        // so it isn't scored: the pick is the same.
                        let stub = min((cAlong - along / 2) - run.lo, run.hi - (cAlong + along / 2))
                        let offMargin = rect.minX < flowchartMargin || rect.minY < flowchartMargin
                        func tail(_ score: CGFloat) -> CGFloat {
                            var score = score
                            if stub < edgeLabelStub { score += (edgeLabelStub - stub) * 6 }
                            score += abs(da) * 1.4           // stay at the MIDPOINT
                            score += abs(dp) * 1.5           // prefer sitting ON the line
                            score += CGFloat(rank) * 2       // prefer the longer run
                            if offMargin { score += 1_000 }
                            return score
                        }
                        if haveBest, tail(0) >= bestScore { continue }
                        var score: CGFloat = 0
                        for k in obstacleGrid.near(rect) { score += overlapArea(rect, obstacles[k]) * 4 }
                        // A caption adds nothing past `gap` on either axis.
                        for k in labelGrid.near(rect.insetBy(dx: -gap, dy: -gap)) {
                            let l = labelRects[k]
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
                        // Each adds the same 120, so only how many lie in the probe
                        // matters (added one at a time, as before).
                        for _ in 0..<bendGrid.count(in: probe, where: { probe.contains(bends[$0]) }) { score += 120 }
                        for _ in 0..<crossingGrid.count(in: probe, where: { probe.contains(crossings[$0]) }) { score += 120 }
                        // Arrowhead clearance: a foreign arrowhead tip within the
                        // comfortable gap of the caption frame is an obstacle.
                        // Every foreign tip counts (only this route's own head is
                        // exempt, via `tip.route != i`). A foreign arrowhead that
                        // happens to coincide with this route's own endpoint used
                        // to be skipped, but the linter's `label-on-fixture` rule
                        // does NOT exempt it — so skipping it here let the placer
                        // pick an anchor that then failed lint. Score all of them.
                        for k in tipGrid.near(rect.insetBy(dx: -gap, dy: -gap)) where arrowTips[k].route != i {
                            let tip = arrowTips[k]
                            let d = pointRectDistance(tip.p, rect)
                            if d < gap { score += (gap - d) * 6 }
                        }
                        // Stub on each side of the caption on this run, then
                        // the rest of the tail.
                        score = tail(score)
                        if !haveBest || score < bestScore {
                            bestScore = score; best = CGPoint(x: cx, y: cy); haveBest = true
                        }
                    }
                }
            }
            placeLabel(CGRect(x: best.x - w / 2, y: best.y - h / 2, width: w, height: h))
            anchors[i] = best
        }
        return anchors
    }

    /// The points where two DIFFERENT routes' segments properly cross — the
    /// junctions a label must not sit on. A proper crossing lies inside both
    /// segments' bounding boxes, so only segments whose boxes share a grid
    /// cell are tested; and two exactly horizontal (or two exactly vertical)
    /// segments are parallel, which `segmentCrossPoint` never counts, so
    /// those pairs aren't tested either. The same points, each pair once,
    /// without testing every pair: routes fanning out of one node share a
    /// horizontal run, which every pair of them overlaps.
    static func routeCrossingPoints(_ routes: [[CGPoint]]) -> [CGPoint] {
        enum Kind { case horizontal, vertical, slanted }
        var segments: [(route: Int, a: CGPoint, b: CGPoint, kind: Kind)] = []
        for i in routes.indices where routes[i].count >= 2 {
            for k in 0..<(routes[i].count - 1) {
                let a = routes[i][k], b = routes[i][k + 1]
                // A point has no direction, so it crosses nothing.
                guard a != b else { continue }
                segments.append((i, a, b, a.y == b.y ? .horizontal : a.x == b.x ? .vertical : .slanted))
            }
        }
        func box(_ s: (route: Int, a: CGPoint, b: CGPoint, kind: Kind)) -> CGRect {
            CGRect(x: min(s.a.x, s.b.x), y: min(s.a.y, s.b.y), width: abs(s.a.x - s.b.x), height: abs(s.a.y - s.b.y))
        }
        func grid(_ kind: Kind) -> (grid: PlacementGrid, members: [Int]) {
            let members = segments.indices.filter { segments[$0].kind == kind }
            return (PlacementGrid(members.map { box(segments[$0]) }), members)
        }
        let vertical = grid(.vertical), slanted = grid(.slanted)
        var pts: [CGPoint] = []
        /// Tests `s` against the segments of `others` near it (the lower
        /// index first, as each pair was always tested; `onlyLater` keeps a
        /// pair within one kind from being tested twice).
        func test(_ s: Int, against others: (grid: PlacementGrid, members: [Int]), onlyLater: Bool = false) {
            for m in others.grid.near(box(segments[s])) {
                let t = others.members[m]
                guard segments[t].route != segments[s].route, !onlyLater || t > s else { continue }
                let (lo, hi) = s < t ? (segments[s], segments[t]) : (segments[t], segments[s])
                if let p = segmentCrossPoint(lo.a, lo.b, hi.a, hi.b) { pts.append(p) }
            }
        }
        for s in segments.indices {
            switch segments[s].kind {
            case .horizontal: test(s, against: vertical); test(s, against: slanted)
            case .vertical: test(s, against: slanted)
            case .slanted: test(s, against: slanted, onlyLater: true)
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
            case .hexagon, .parallelogram, .parallelogramAlt, .trapezoid, .trapezoidAlt:
                // Pointed or slanted ends eat horizontal room — widen so the
                // label clears.
                size.width += size.height
            case .asymmetric:
                size.width += size.height / 2   // the notch on the left
            case .subroutine:
                size.width += 16   // room for the twin inner rails
            case .circle:
                let d = max(size.width, size.height)
                size = CGSize(width: d, height: d)
            case .doubleCircle:
                let d = max(size.width, size.height) + 2 * doubleCircleGap
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
        layerGaps: [CGFloat],
        leadPad: CGFloat = 0,
        tailPad: CGFloat = 0
    ) -> (frames: [String: CGRect], mainContentEnd: CGFloat, crossExtent: CGFloat,
          bands: [(start: CGFloat, end: CGFloat)]) {
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
        var bands: [(start: CGFloat, end: CGFloat)] = []
        var mainOffset = margin + leadPad
        for (li, layer) in layers.enumerated() {
            let mainSize = layer.map { horizontal ? sizes[$0]!.width : sizes[$0]!.height }.max() ?? 0
            bands.append((mainOffset, mainOffset + mainSize))
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

        return (frames, mainOffset + tailPad + margin, crossExtent, bands)
    }

    /// The edges `routeChains` spreads over jog tracks, grouped by the node
    /// each enters (`into`) and the node each leaves (`outOf`): every drawn
    /// link between two different nodes. A group of n spreads its jogs over
    /// n tracks centred on the gap's middle, `jogSpread(n)` either way.
    static func jogFanGroups(
        _ chart: Flowchart, chains: [[String]]
    ) -> (into: [String: [Int]], outOf: [String: [Int]]) {
        var into: [String: [Int]] = [:], outOf: [String: [Int]] = [:]
        for (index, edge) in chart.edges.enumerated() where !edge.invisible && index < chains.count {
            let chain = chains[index]
            guard chain.count >= 2, chain[0] != chain[chain.count - 1] else { continue }
            into[chain[chain.count - 1], default: []].append(index)
            outOf[chain[0], default: []].append(index)
        }
        return (into, outOf)
    }

    /// How far each edge's jogs move off its layer gaps' middle, so the
    /// edges of one fan (those leaving one node, or entering one) take
    /// distinct tracks `flowchartJogTrack` apart and don't cross (#110). A
    /// fan of n has n tracks centred on the gap's middle. Its edges on one
    /// side of its hub take them from the one nearest the hub, in order of
    /// how far out they reach, the farthest first, so each one's run along
    /// the main axis stays clear of the others' jogs. The two sides share
    /// the tracks, as their jogs span cross ranges either side of the hub,
    /// and so do edges leaving the hub's two faces, which jog in different
    /// gaps. Jogs stay off the gap's middle, leaving a captioned edge one
    /// long run. Edges that reach as far, such as parallel edges, go in the
    /// order of their ports on the hub, farthest out first, so an edge's
    /// places in the fan it leaves (`out`) and the one it enters (`into`)
    /// agree. An edge between adjacent layers jogs on the sum of the two in
    /// one gap, which can reverse a fan's order there; `orderJogsInGaps`
    /// puts that right (#112). `cross` and `main` give a chain node's centre
    /// on each axis, and
    /// `port` where an edge's end meets its node's face, if known.
    static func fanJogBias(
        _ chart: Flowchart, chains: [[String]],
        cross: (String) -> CGFloat?, main: (String) -> CGFloat?,
        port: (_ edge: Int, _ isSource: Bool) -> CGFloat? = { _, _ in nil }
    ) -> (out: [CGFloat], into: [CGFloat]) {
        struct Side: Hashable { var hub: String; var into: Bool; var forward: Bool; var side: Int }
        var sides: [Side: [(index: Int, reach: CGFloat, outward: CGFloat)]] = [:]
        let fans = jogFanGroups(chart, chains: chains)
        for (into, groups) in [(false, fans.outOf), (true, fans.into)] {
            for (hub, idxs) in groups {
                for index in idxs {
                    let chain = chains[index]
                    let far = into ? chain[chain.count - 2] : chain[1]
                    guard let hc = cross(hub), let fc = cross(far), let hm = main(hub), let fm = main(far),
                          cross(chain[0]) != nil, cross(chain[chain.count - 1]) != nil else { continue }
                    let reach = fc - hc
                    let side = reach > 0.5 ? 1 : (reach < -0.5 ? -1 : 0)
                    let outward = CGFloat(side == 0 ? 1 : side) * ((port(index, !into) ?? hc) - hc)
                    sides[Side(hub: hub, into: into, forward: into ? hm > fm : fm > hm, side: side),
                          default: []].append((index, abs(reach), outward))
                }
            }
        }
        // Edges through one face of the hub jog in one gap, and spread over
        // as many tracks as there are of them.
        var faceCount: [Side: Int] = [:]
        for (key, members) in sides {
            var face = key; face.side = 0
            faceCount[face, default: 0] += members.count
        }
        var out = [CGFloat](repeating: 0, count: chart.edges.count), into = out
        for (key, members) in sides {
            var face = key; face.side = 0
            let spread = jogSpread(faceCount[face] ?? 1)
            let ordered = members.sorted {
                $0.reach != $1.reach ? $0.reach > $1.reach
                    : $0.outward != $1.outward ? $0.outward > $1.outward : $0.index < $1.index
            }
            // Toward the hub is up the main axis for a forward edge leaving
            // it, down for one entering it, and the reverse for a back edge.
            let toward: CGFloat = key.into == key.forward ? 1 : -1
            for (rank, member) in ordered.enumerated() {
                let track = toward * (spread - CGFloat(rank) * flowchartJogTrack)
                if key.into { into[member.index] = track } else { out[member.index] = track }
            }
        }
        return (out, into)
    }

    /// How far a fan of `n` edges moves its outermost jog off a gap's middle.
    static func jogSpread(_ n: Int) -> CGFloat { CGFloat(max(n, 1) - 1) / 2 * flowchartJogTrack }

    /// Geometry of one self-loop (`A --> A`). The loop wraps around the node's
    /// cross-far side — the right in a top-down chart, the bottom in a
    /// left-right one: it leaves the exit face near that side, stands off by
    /// `excursion`, runs past the node at `reach` beyond its far face, and
    /// comes back into the entry face. That far run spans the node plus both
    /// standoffs, so it is long enough to carry a caption beside it with a
    /// full stub each side, which a loop on the node's side face never is.
    /// Several loops on one node nest outward (`nest` 0 is the innermost),
    /// each clear of the caption inside it.
    struct SelfLoopPath {
        var node: String
        var nest: Int
        /// Cross-axis distance from the node's far face to the loop's far run.
        var reach: CGFloat
        /// Main-axis distance the loop's bars stand off the node's faces.
        var excursion: CGFloat
        /// Cross-axis space beyond the far face this loop, its caption and the
        /// loops inside it occupy, including the gap to whatever comes next.
        var clearance: CGFloat
        var isOutermost: Bool
        /// The far run's segment in the loop's route (`selfLoopRoute`: exit,
        /// past the exit face, far run, before the entry face, entry).
        static let farRunSegment = 2
    }

    /// How far a loop's far run sits beyond the node, and its bars beyond the
    /// node's faces, when it carries no caption.
    private static let selfLoopReach: CGFloat = 24
    private static let selfLoopStandoff: CGFloat = 12

    /// The path of every self-loop in `chart`, keyed by edge index. Captions
    /// are sized the way `placeRunLabels` boxes them, so the far run fits the
    /// caption with a stub each side and `clearance` covers it.
    static func selfLoopPaths(
        _ chart: Flowchart, sizes: [String: CGSize], horizontal: Bool,
        measure: DiagramTextMeasurer
    ) -> [Int: SelfLoopPath] {
        var paths: [Int: SelfLoopPath] = [:]
        var lastOnNode: [String: Int] = [:]
        // An invisible self-loop draws nothing, so it reserves nothing.
        for (index, edge) in chart.edges.enumerated() where edge.from == edge.to && !edge.invisible {
            guard let size = sizes[edge.from] else { continue }
            var along: CGFloat = 0, across: CGFloat = 0
            if let text = edge.label, !text.isEmpty {
                let sz = measure(text, labelFontSize)
                along = horizontal ? sz.width + 6 : sz.height + 2
                across = horizontal ? sz.height + 2 : sz.width + 6
            }
            let mainSize = horizontal ? size.width : size.height
            var excursion = max(selfLoopStandoff, (along + 2 * edgeLabelStub - mainSize) / 2)
            var inner: CGFloat = 0
            var nest = 0
            if let previous = lastOnNode[edge.from], var outer = paths[previous] {
                inner = outer.clearance
                excursion = max(excursion, outer.excursion + flowchartJogTrack)
                nest = outer.nest + 1
                outer.isOutermost = false
                paths[previous] = outer
            }
            let reach = inner + selfLoopReach
            // The caption rides beside the far run, half a gap off the line
            // (`placeRunLabels`' perpendicular nudge), then keeps a full gap
            // to the next thing out.
            let caption = across > 0 ? flowchartLabelGap / 2 + across : 0
            paths[index] = SelfLoopPath(
                node: edge.from, nest: nest, reach: reach, excursion: excursion,
                clearance: reach + caption + flowchartLabelGap, isOutermost: true)
            lastOnNode[edge.from] = index
        }
        return paths
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
        backEdges: Set<Int> = [],
        selfLoops: [Int: SelfLoopPath] = [:],
        gaps: [(lo: CGFloat, hi: CGFloat)] = [],
        captionRuns: [Int: CGFloat] = [:]
    ) -> (edges: [FlowchartLayout.PlacedEdge], crossLimit: CGFloat) {
        let shapeOf = Dictionary(uniqueKeysWithValues: chart.nodes.map { ($0.id, $0.shape) })
        var loopCount: [String: Int] = [:]
        var loopExcursion: [String: CGFloat] = [:]
        for loop in selfLoops.values {
            loopCount[loop.node, default: 0] += 1
            loopExcursion[loop.node] = max(loopExcursion[loop.node] ?? 0, loop.excursion)
        }

        // Whether a decision's branch toward `next` heads for its cross-far
        // side, beyond ~15% of its half-breadth (`diamondPort`'s side test).
        func headsFarSide(_ f: CGRect, toward next: CGPoint) -> Bool {
            horizontal ? next.y - f.midY > f.height * 0.15 : next.x - f.midX > f.width * 0.15
        }
        // A looped decision's branches toward its loops' side each get a slot
        // on the face they leave (`diamondPort`), in the order they head, so
        // no two share a point.
        var farSlot: [Int: (slot: Int, of: Int)] = [:]
        var farGroups: [String: [(edge: Int, cross: CGFloat)]] = [:]
        for (index, edge) in chart.edges.enumerated() where !edge.invisible && index < chains.count {
            let chain = chains[index]
            guard chain.count >= 2, chain[0] != chain[chain.count - 1], loopCount[chain[0]] != nil,
                  shapeOf[chain[0]] == .diamond,
                  let f = frames[chain[0]], let n = frames[chain[1]] else { continue }
            let next = CGPoint(x: n.midX, y: n.midY)
            guard headsFarSide(f, toward: next) else { continue }
            let forward = horizontal ? next.x >= f.midX : next.y >= f.midY
            farGroups["\(chain[0])|\(forward)", default: []].append((index, horizontal ? next.y : next.x))
        }
        for group in farGroups.values {
            let sorted = group.sorted { ($0.cross, $0.edge) < ($1.cross, $1.edge) }
            for (slot, member) in sorted.enumerated() { farSlot[member.edge] = (slot, sorted.count) }
        }

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
                case .circle, .doubleCircle, .stateStart, .stateEnd:
                    let dx = (f.width / 2) * sqrt(max(0, 1 - pow((y - f.midY) / hh, 2)))
                    x = rightOrBottom ? f.midX + dx : f.midX - dx
                case .hexagon:
                    // Left/right ends are pointed: pull an off-center port in
                    // along the sloped side (same inset as `hexagonPath`) so it
                    // lands on the visible outline, not a phantom box edge.
                    let hexInset = min(f.width * 0.22, f.height / 2)
                    let frac = min(abs(y - f.midY) / hh, 1)
                    x = rightOrBottom ? f.maxX - hexInset * frac : f.minX + hexInset * frac
                default:
                    // Slanted sides and the flag's notch: onto the drawn outline.
                    if let outline = polygonOutline(shape, in: f),
                       let onOutline = outlineCrossing(outline, at: y, atY: true, far: rightOrBottom) {
                        x = onOutline
                    }
                }
                return CGPoint(x: x, y: y)
            } else {
                let inset = min(f.width * 0.22, f.width / 2)
                let x = min(max(cross, f.minX + inset), f.maxX - inset)
                let hw = max(f.width / 2, 0.001)
                var y = rightOrBottom ? f.maxY : f.minY
                switch shape {
                case .circle, .doubleCircle, .stateStart, .stateEnd:
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
        // routing resumes; otherwise it leaves the south/north vertex. A
        // decision with self-loops (`farLoops` of them) has its cross-far
        // vertex inside them, so a branch heading that way leaves the face it
        // runs from (exit side forward, entry side back) between the loops and
        // the main-axis vertex (see `selfLoopRoute`), at its `farSlot` there,
        // clear of the loops, a straight branch and its sibling branches.
        func diamondPort(
            _ f: CGRect, toward next: CGPoint, isSource: Bool, farLoops: Int = 0,
            farSlot: (slot: Int, of: Int) = (0, 1)
        ) -> (vertex: CGPoint, stub: CGPoint?) {
            let farT = 0.5 / CGFloat(max(farLoops, 1)) * CGFloat(farSlot.slot + 1) / CGFloat(farSlot.of + 1)
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
                } else if farLoops > 0, headsFarSide(f, toward: next) {
                    let x = next.x >= f.midX ? f.maxX - farT * f.width / 2 : f.minX + farT * f.width / 2
                    return (CGPoint(x: x, y: f.midY + farT * f.height / 2), nil)
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
                } else if farLoops > 0, headsFarSide(f, toward: next) {
                    let y = next.y >= f.midY ? f.maxY - farT * f.height / 2 : f.minY + farT * f.height / 2
                    return (CGPoint(x: f.midX + farT * f.width / 2, y: y), nil)
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
        func sourceExitCross(
            srcDiamond: Bool, from f: CGRect, toward next: CGPoint, farLoops: Int = 0,
            farSlot: (slot: Int, of: Int) = (0, 1)
        ) -> CGFloat {
            if srcDiamond {
                let (v, stub) = diamondPort(f, toward: next, isSource: true, farLoops: farLoops,
                                            farSlot: farSlot)
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
            var selfLoop: SelfLoopPath?
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
            if let loop = selfLoops[index], chain.count == 2, chain[0] == chain[1] {
                // A self-loop leaves the exit face and re-enters the entry face
                // at their cross-far ends. Wanting past every real port parks
                // it there and slides the real ports aside; an inner loop sits
                // nearer the far end than the loops around it, so they never
                // cross.
                g.selfLoop = loop
                g.exitBottom = true
                g.enterBottom = false
                geos[index] = g
                if !g.srcDiamond {
                    let wanted = CGFloat(1_000_000 - loop.nest)
                    buckets[faceKey(chain[0], bottom: true), default: []].append((index, true, wanted))
                    buckets[faceKey(chain[0], bottom: false), default: []].append((index, false, wanted))
                }
                continue
            }
            geos[index] = g
            // An invisible link (`~~~`) routes on its natural channel; it takes
            // no face slot, so it never pushes a drawn edge's port aside.
            let drawn = !chart.edges[index].invisible
            if drawn, !g.srcDiamond {
                buckets[faceKey(chain[0], bottom: g.exitBottom), default: []]
                    .append((index, true, horizontal ? g.firstNext.y : g.firstNext.x))
            }
            if drawn, !g.dstDiamond {
                // The target port wants to sit where the edge actually descends,
                // not under the source's centre. For a routed (dummy) edge that
                // is the last dummy's channel; for an adjacent edge it's where
                // the source exits — so the two ends line up into a straight run
                // or a single clean bend instead of an S back to the source x.
                let wanted: CGFloat
                if g.dummyCenters.isEmpty {
                    wanted = sourceExitCross(srcDiamond: g.srcDiamond, from: ff, toward: g.firstNext,
                                             farLoops: loopCount[chain[0], default: 0],
                                             farSlot: farSlot[index] ?? (0, 1))
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
                // Sliding can push the first ports below `lo`, where `attach`
                // clamps them back up, nearer their neighbours than `minSep`, or
                // onto them: two edges into one point. Raise just those, keeping
                // the gap: `minSep` lets every port fit between `lo` and `hi`,
                // so the block still ends by `hi`.
                if let first = pos.first, first < lo {
                    pos[0] = lo
                    for i in 1..<pos.count where pos[i] < pos[i - 1] + minSep { pos[i] = pos[i - 1] + minSep }
                }
            }
            for (i, p) in sorted.enumerated() { portCross[portKey(p.edge, p.isSource)] = pos[i] }
        }

        // Give the edges of each fan distinct jog tracks, so their bend
        // corners neither nest into one another nor share a line
        // (`edges-doubled`), and no two of them cross (`fanJogBias`).
        let (jogOut, jogIn) = fanJogBias(
            chart, chains: chains,
            cross: { id in frames[id].map { horizontal ? $0.midY : $0.midX } },
            main: { id in frames[id].map { horizontal ? $0.midX : $0.midY } },
            port: { portCross[portKey($0, $1)] })

        // A self-loop's polyline: out of the exit face, round the node's
        // cross-far side at `reach`, back into the entry face. A decision has
        // no face ports, so its loop leaves and re-enters on its two cross-far
        // sides: the innermost loop at their middles, each loop round it
        // nearer the main-axis vertices, so nested loops never share a bar.
        func selfLoopRoute(_ index: Int, _ g: EdgeGeo, _ loop: SelfLoopPath) -> [CGPoint] {
            let f = g.fromFrame
            func point(cross: CGFloat, main: CGFloat) -> CGPoint {
                horizontal ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main)
            }
            func cross(_ p: CGPoint) -> CGFloat { horizontal ? p.y : p.x }
            let (mainLo, mainHi) = horizontal ? (f.minX, f.maxX) : (f.minY, f.maxY)
            let (crossMid, crossHi) = horizontal ? (f.midY, f.maxY) : (f.midX, f.maxX)
            let mainMid = (mainLo + mainHi) / 2
            let exit: CGPoint, entry: CGPoint
            if g.srcDiamond {
                let t = 0.5 / CGFloat(1 + loop.nest)
                let c = crossMid + t * (crossHi - crossMid)
                exit = point(cross: c, main: mainHi - t * (mainHi - mainMid))
                entry = point(cross: c, main: mainLo + t * (mainMid - mainLo))
            } else {
                let fallback = horizontal
                    ? f.maxY - min(f.height * 0.22, f.height / 2)
                    : f.maxX - min(f.width * 0.22, f.width / 2)
                exit = attach(g.chain[0], cross: portCross[portKey(index, true)] ?? fallback,
                              rightOrBottom: true, isSource: true)
                entry = attach(g.chain[0], cross: portCross[portKey(index, false)] ?? fallback,
                               rightOrBottom: false, isSource: false)
            }
            let far = crossHi + loop.reach
            let past = mainHi + loop.excursion, before = mainLo - loop.excursion
            // Segment `SelfLoopPath.farRunSegment` is the far run.
            return [
                exit,
                point(cross: cross(exit), main: past),
                point(cross: far, main: past),
                point(cross: far, main: before),
                point(cross: cross(entry), main: before),
                entry,
            ]
        }

        var routes = [[CGPoint]](repeating: [], count: chart.edges.count)
        for index in chart.edges.indices {
            let g = geos[index]
            // A self-loop routes after every pass below.
            guard g.valid, g.selfLoop == nil else { continue }

            // Head (leaves the source) and tail (enters the target). A decision
            // uses vertex ports; every other shape uses its distributed face port.
            let head: [CGPoint]
            if g.srcDiamond {
                let (v, stub) = diamondPort(g.fromFrame, toward: g.firstNext, isSource: true,
                                            farLoops: loopCount[g.chain[0], default: 0],
                                            farSlot: farSlot[index] ?? (0, 1))
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

            // A fan's tracks matter where it meets its hub: an edge jogs on
            // its fan-out's track in the gap it leaves by, on its fan-in's in
            // the gap it enters by, and mid-gap between its long-edge dummies.
            let first = head.count - 1, last = first + g.dummyCenters.count
            let (out, into) = (jogOut[index], jogIn[index])
            routes[index] = routePolyline(head + g.dummyCenters + tail, horizontal: horizontal, jogBias: out + into,
                                          stepBias: last == first ? nil : { step in
                step == first ? out : step == last ? into : (first < step && step < last ? 0 : out + into)
            })
        }

        // A labeled adjacent-layer edge whose route makes a single jog splits the
        // grown layer gap into two shorter straight runs at the bend. The caption
        // rides the longer half, so even though the gap was reserved to host
        // `arrowheadLen + labelExtent + 2*stub`, HALF of it can leave under the
        // minimum stub (`label-crowds-edge`). Slide the lone bend toward the
        // arrowhead end, leaving an end run past it (an arrowhead and the
        // shortest step, so it isn't a hook), so the arrow-free half spans
        // nearly the whole reserved run and the caption breathes.
        // Only unlabeled-neutral shapes with a plain one-corner route qualify;
        // diamonds (vertex ports) and multi-corner/dummy routes are left alone.
        var captionBends: [Int: (natural: CGFloat, source: CGFloat?)] = [:]
        for index in chart.edges.indices {
            let e = chart.edges[index]
            let g = geos[index]
            guard g.valid, g.dummyCenters.isEmpty, !g.srcDiamond, !g.dstDiamond,
                  e.hasArrow, !e.backArrow,
                  let text = e.label, !text.isEmpty else { continue }
            var pts = routes[index]
            guard pts.count == 4 else { continue }        // exactly one corner
            // A looped target's bars stand off its entry face, so there the
            // bend stops a jog track short of them instead.
            let stop = max(flowchartEndRun,
                           loopExcursion[g.chain[g.chain.count - 1]].map { $0 + flowchartJogTrack } ?? 0)
            // Where the bend was, on its fan's track: it may go back there.
            let natural = horizontal ? pts[1].x : pts[1].y
            if horizontal {
                let x0 = pts[0].x, x3 = pts[3].x
                guard abs(pts[1].y - pts[2].y) > 0.5,     // it really jogs
                      abs(x3 - x0) > stop + 1 else { continue }
                let jx = x3 > x0 ? x3 - stop : x3 + stop
                pts[1].x = jx; pts[2].x = jx
            } else {
                let y0 = pts[0].y, y3 = pts[3].y
                guard abs(pts[1].x - pts[2].x) > 0.5,
                      abs(y3 - y0) > stop + 1 else { continue }
                let jy = y3 > y0 ? y3 - stop : y3 + stop
                pts[1].y = jy; pts[2].y = jy
            }
            routes[index] = pts
            // It may as well stop as short of its source, where the caption
            // still fits on the run past it, before the arrowhead.
            let sourceStop = max(flowchartEndRun, loopExcursion[g.chain[0]].map { $0 + flowchartJogTrack } ?? 0)
            let span = horizontal ? abs(pts[3].x - pts[0].x) : abs(pts[3].y - pts[0].y)
            let fits = span - sourceStop - flowchartArrowheadLen >= (captionRuns[index] ?? .infinity) - 0.5
            captionBends[index] = (natural, fits ? sourceStop : nil)
        }

        // The jogs in each layer gap keep their tracks, but take them in the
        // order that crosses least (#112).
        orderJogsInGaps(&routes, gaps: gaps, horizontal: horizontal, captionBends: captionBends,
                        captioned: Set(captionRuns.keys), track: flowchartJogTrack, near: flowchartMinJog,
                        ignored: Set(chart.edges.indices.filter { chart.edges[$0].invisible || geos[$0].selfLoop != nil }))

        // Separate coincident main-axis runs: two different edges whose runs
        // share a track (an incoming edge's descent and a back edge's channel
        // land on one node column) read as a single doubled line. Nudge the
        // movable run — one whose ends are interior bends, not anchored to a
        // box — aside to restore the minimum separation.
        // Invisible links sit out: nothing drawn can read as doubled with them.
        let hidden = chart.edges.indices.filter { chart.edges[$0].invisible }
        var drawnRoutes = routes
        for index in hidden { drawnRoutes[index] = [] }
        separateRuns(&drawnRoutes, horizontal: horizontal, minSep: flowchartPortSep,
                     obstacles: chart.nodes.compactMap { frames[$0.id] })
        for index in hidden { drawnRoutes[index] = routes[index] }
        routes = drawnRoutes

        // Straighten needless zags: a waypoint (a diamond vertex vs. its dummy
        // channel, a stub vs. a face port) can step a run sideways by only a
        // cell before it resumes straight. Collapse that tiny jog so the run is
        // one straight stretch, never introducing a step where the ends could be
        // joined straight.
        let decisions = chart.nodes.filter { $0.shape == .diamond }.compactMap { frames[$0.id] }
        straightenJogs(&routes, horizontal: horizontal, maxJog: flowchartMinJog, endRun: flowchartEndRun,
                       decisions: decisions)

        // A back edge that still threads UP THROUGH the node stack (a multi-bend
        // zigzag re-entering the occupied column, with its label crossing the
        // forward edges) reads far cleaner as a C: exit the source's side face,
        // run the return in a gutter clear of every node, and enter the target's
        // same face. Applied only when the gutter route is node-clear AND has
        // strictly fewer bends AND no more crossings — so a back edge that
        // already routes cleanly on the boundary (few bends) is left alone and
        // no fixture regresses. The gutter also stays clear of every loop and
        // the caption beside it.
        let loops = chart.edges.indices.filter { geos[$0].selfLoop != nil }
        let loopAreas = loops.compactMap { index -> CGRect? in
            guard let loop = geos[index].selfLoop, loop.isOutermost else { return nil }
            let f = geos[index].fromFrame
            let depth = loop.clearance - flowchartLabelGap
            return horizontal
                ? CGRect(x: f.minX - loop.excursion, y: f.maxY, width: f.width + 2 * loop.excursion, height: depth)
                : CGRect(x: f.maxX, y: f.minY - loop.excursion, width: depth, height: f.height + 2 * loop.excursion)
        }
        rerouteBackEdgesThroughGutter(
            &routes, backEdges: backEdges, chart: chart, frames: frames,
            horizontal: horizontal, obstacles: loopAreas)

        // Self-loops route last: their geometry is fixed by the space reserved
        // for them, and nudging, straightening or gutter-routing a loop would
        // pull it back onto its node.
        for index in loops {
            if let loop = geos[index].selfLoop { routes[index] = selfLoopRoute(index, geos[index], loop) }
        }

        // Last, no two edges on one line: whatever still draws doubled moves
        // aside a track at a time, self-loops and nodes standing fast.
        separateDoubledRuns(&routes, fixed: Set(loops), ignored: Set(hidden),
                            obstacles: chart.nodes.compactMap { frames[$0.id] }, track: flowchartJogTrack,
                            endRun: flowchartEndRun, decisions: decisions)

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
                    backArrow: edge.backArrow, head: edge.head, thick: edge.thick,
                    invisible: edge.invisible))
        }
        return (placedEdges, crossLimit)
    }

    /// Connects waypoints with an orthogonal polyline. For a top-down chart the
    /// vertical runs sit at each waypoint's x (the reserved dummy channels) and
    /// the horizontal jogs happen between consecutive waypoints — i.e. in the
    /// gaps between layers, never across a node's row. `jogBias` shifts each jog
    /// off the gap midpoint (clamped to stay in the gap) so concurrent edges
    /// crossing the same gap can take distinct tracks and their bend corners
    /// don't nest; `stepBias`, when given, sets it for each step between
    /// waypoints instead. Collinear runs are merged so straight edges stay
    /// two-point.
    static func routePolyline(_ waypoints: [CGPoint], horizontal: Bool, jogBias: CGFloat = 0,
                              stepBias: ((Int) -> CGFloat)? = nil) -> [CGPoint] {
        guard waypoints.count >= 2 else { return waypoints }
        var pts: [CGPoint] = [waypoints[0]]
        for i in 0..<(waypoints.count - 1) {
            let a = waypoints[i], b = waypoints[i + 1]
            let jogBias = stepBias?(i) ?? jogBias
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
    /// A nudge never takes a route into one of `obstacles` (the nodes) it was
    /// clear of: then the other run moves, if it can, or neither does.
    static func separateRuns(_ routes: inout [[CGPoint]], horizontal: Bool, minSep: CGFloat,
                             obstacles: [CGRect] = []) {
        let tol: CGFloat = 4
        let inset = obstacles.map { $0.insetBy(dx: 1, dy: 1) }
        // The obstacles the run at `i` of `pts` and its two neighbours cross.
        func blocked(_ pts: [CGPoint], _ i: Int) -> Int {
            var count = 0
            for j in max(i - 1, 0)...min(i + 1, pts.count - 2) {
                let a = pts[j], b = pts[j + 1]
                let seg = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                count += inset.filter { $0.intersects(seg) }.count
            }
            return count
        }
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
                    for t in [a, b] where runs[t].movable {
                        let other = (t == a ? rb : ra)
                        let s = runs[t]
                        let dir: CGFloat = s.c >= other.c ? 1 : -1          // push away
                        let shift = dir * minSep - (s.c - other.c)
                        var pts = routes[s.e]
                        pts[s.i] = offsetCross(pts[s.i], by: shift, horizontal: horizontal)
                        pts[s.i + 1] = offsetCross(pts[s.i + 1], by: shift, horizontal: horizontal)
                        if !inset.isEmpty, blocked(pts, s.i) > blocked(routes[s.e], s.i) { continue }
                        routes[s.e] = pts
                        runs[t].c += shift
                        moved = true
                        break
                    }
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
        horizontal: Bool,
        obstacles: [CGRect] = []
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
        // `obstacles` (a self-loop and its caption) bound the gutters and must
        // be cleared like nodes.
        let realFrames = chart.nodes.compactMap { frames[$0.id] }
        let realIDs = Set(chart.nodes.map(\.id))
        guard let gutterEast = (realFrames + obstacles).map(crossHi).max().map({ $0 + flowchartPortSep }),
              let gutterWest = (realFrames + obstacles).map(crossLo).min().map({ $0 - flowchartPortSep }) else { return }

        // Straight (orthogonal) segment (a,b) travels >6pt inside rect r's
        // interior? On the axis the segment TRAVELS along, the clipped overlap
        // is the distance it runs inside the box; on the PERPENDICULAR axis the
        // segment collapses to a single fixed coordinate, so its clipped overlap
        // is exactly 0 whenever that coordinate sits within the interior. The old
        // test required BOTH overlaps to exceed 6pt — unsatisfiable for an
        // axis-aligned segment (one axis is always 0) — so `nodeClear` silently
        // accepted gutter routes that pierced sibling nodes. Correct rule: the
        // wire penetrates when it touches the interior on both axes (perpendicular
        // overlap ≥ 0: the fixed coord is inside) AND travels more than 6pt
        // through it (the travel-axis overlap).
        func passesThrough(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> Bool {
            let inner = r.insetBy(dx: 2, dy: 2)
            guard inner.width > 0, inner.height > 0 else { return false }
            let ox = min(max(a.x, b.x), inner.maxX) - max(min(a.x, b.x), inner.minX)
            let oy = min(max(a.y, b.y), inner.maxY) - max(min(a.y, b.y), inner.minY)
            return ox >= 0 && oy >= 0 && max(ox, oy) > 6
        }
        func nodeClear(_ route: [CGPoint], skip: Set<String>) -> Bool {
            for (id, f) in frames where realIDs.contains(id) && !skip.contains(id) {
                for k in 0..<(route.count - 1) where passesThrough(route[k], route[k + 1], f) {
                    return false
                }
            }
            for f in obstacles {
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
        // Two DIFFERENT back edges can pick the same gutter channel, whose middle
        // runs are then collinear and overlap — they draw as one doubled
        // connector. `segmentCrossPoint` returns nil for collinear pairs (they
        // don't "cross"), and `separateRuns` ran before this pass, so neither the
        // crossing count nor the port separation catches it. Detect positive-
        // length collinear overlap of two orthogonal segments directly.
        func collinearOverlap(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
            if abs(a.y - b.y) < 0.5, abs(c.y - d.y) < 0.5, abs(a.y - c.y) < 0.5 {   // both horizontal, same y
                let lo = max(min(a.x, b.x), min(c.x, d.x)), hi = min(max(a.x, b.x), max(c.x, d.x))
                return hi - lo > 1
            }
            if abs(a.x - b.x) < 0.5, abs(c.x - d.x) < 0.5, abs(a.x - c.x) < 0.5 {   // both vertical, same x
                let lo = max(min(a.y, b.y), min(c.y, d.y)), hi = min(max(a.y, b.y), max(c.y, d.y))
                return hi - lo > 1
            }
            return false
        }
        func doublesAnotherRoute(_ route: [CGPoint], against ignore: Int) -> Bool {
            for (j, other) in routes.enumerated() where j != ignore && other.count >= 2 {
                for a in 0..<(route.count - 1) {
                    for b in 0..<(other.count - 1) where collinearOverlap(route[a], route[a + 1], other[b], other[b + 1]) {
                        return true
                    }
                }
            }
            return false
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
                // Reject a gutter that would double an already-placed route
                // (including an earlier back edge rerouted into the same channel).
                guard !doublesAnotherRoute(cand, against: index) else { continue }
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
    static func straightenJogs(_ routes: inout [[CGPoint]], horizontal: Bool, maxJog: CGFloat, endRun: CGFloat = 0,
                               decisions: [CGRect] = []) {
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
                    // Nor where that shortens a run off a node below an end
                    // run: the end would read as a hook (but a decision's
                    // branches fork at its vertex, and may at once).
                    func hooks(_ tip: CGPoint, _ old: CGPoint, _ new: CGPoint) -> Bool {
                        guard !decisions.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(tip) }) else { return false }
                        let was = hypot(old.x - tip.x, old.y - tip.y), now = hypot(new.x - tip.x, new.y - tip.y)
                        return now < was && now < endRun
                    }
                    if moveAfter, k + 2 == pts.count - 2,
                       hooks(pts[pts.count - 1], d, setCross(d, cross(b))) { continue }
                    if !moveAfter, k - 1 == 1, hooks(pts[0], a, setCross(a, cross(c))) { continue }
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

    /// Whether `text` holds a line break `brLines` would split on — the one
    /// test both the raster draw and the `RenderScene` lowering use, so they
    /// agree on what breaks (any-case `<br…>`, a literal `\n`, a newline).
    public static func hasLineBreak(_ text: String) -> Bool {
        text.range(of: "<br", options: .caseInsensitive) != nil || text.contains("\\n")
            || text.contains(where: \.isNewline)
    }

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

    /// How far below its head frame an actor or typed glyph's name is centered:
    /// 7 at the default size, grown with its 12pt text. Both renderers place
    /// the name by it and the lint scene extends the head to cover it.
    package static func sequenceNameDrop(_ measure: DiagramTextMeasurer) -> CGFloat {
        grown(7, fontSize: nodeFontSize, measure)
    }

    /// A sequence message's 10.5pt label lines — the last centered `rise`
    /// above the arrow, the rest stacked `line` apart above it, the arrow
    /// `arrowInset` up from its row's bottom — and a note's line pitch: 10,
    /// 12, 14 and 13 at the default size, grown with the text. The layout,
    /// both renderers and the lint scene place the text by them. The message
    /// pitch is a little under a line at the default size, so it's also kept
    /// within a point of the measured line, or larger text would overlap.
    package static func sequenceTextMetrics(_ measure: DiagramTextMeasurer)
        -> (rise: CGFloat, line: CGFloat, arrowInset: CGFloat, noteLine: CGFloat) {
        let line = max(grown(12, fontSize: labelFontSize, measure), measure("Mg", labelFontSize).height - 1)
        return (grown(10, fontSize: labelFontSize, measure), line,
                grown(14, fontSize: labelFontSize, measure), grown(13, fontSize: labelFontSize, measure))
    }

    /// The strip at the top of a sequence `box` band that holds its 9pt label:
    /// the band starts 6 above the margin, its label is centered in the strip,
    /// and boxed heads start below it (18 at the default size, so heads sit at
    /// margin + 12 and the label at the band's top + 9). Layout, both renderers
    /// and the lint scene place the label by it.
    package static func sequenceBoxStrip(_ measure: DiagramTextMeasurer) -> CGFloat {
        grown(18, fontSize: 9, measure)
    }

    /// Height of a fragment's kind tab (`loop`, `alt`, …), whose 9pt kind and
    /// [guard] labels are centered on it: 15 at the default size.
    package static func sequenceFragmentTab(_ measure: DiagramTextMeasurer) -> CGFloat {
        grown(15, fontSize: 9, measure)
    }

    public static func layout(_ diagram: SequenceDiagram, measure: DiagramTextMeasurer) -> SequenceLayout {
        let margin: CGFloat = 12
        let headPaddingX: CGFloat = 14
        let headHeight: CGFloat = grown(30, fontSize: nodeFontSize, measure)
        let rowHeight: CGFloat = grown(34, fontSize: labelFontSize, measure)
        // The room between lifelines holds message labels, so the minimum
        // column, the gap between columns and a label's clearance grow with
        // the text (all as before at the default size).
        let minColumn: CGFloat = grown(110, fontSize: labelFontSize, measure)
        let columnGap: CGFloat = grown(24, fontSize: labelFontSize, measure)

        // Column widths driven by head labels and message texts.
        var columnWidth: [CGFloat] = diagram.participants.map { participant in
            max(measure(participant.label, nodeFontSize).width + headPaddingX * 2, minColumn)
        }
        var indexOf: [String: Int] = [:]
        for (i, participant) in diagram.participants.enumerated() { indexOf[participant.id] = i }
        for message in diagram.messages {
            guard let a = indexOf[message.from], let b = indexOf[message.to], abs(a - b) == 1 else { continue }
            let widest = brLines(message.text).map { measure($0, labelFontSize).width }.max() ?? 0
            let needed = widest + columnGap
            let lo = min(a, b)
            columnWidth[lo] = max(columnWidth[lo], needed)
        }

        var heads: [SequenceLayout.Head] = []
        var x = margin
        let boxed = Set(diagram.boxes.flatMap(\.memberIDs))
        for (i, participant) in diagram.participants.enumerated() {
            let width = columnWidth[i]
            // Boxed participants sit below their band's label strip, so the
            // label has clear headroom above their head boxes.
            let headY = boxed.contains(participant.id) ? margin - 6 + sequenceBoxStrip(measure) : margin
            heads.append(SequenceLayout.Head(
                label: participant.label,
                frame: CGRect(x: x, y: headY, width: width, height: headHeight),
                isActor: participant.isActor,
                kind: participant.kind.rawValue
            ))
            x += width + columnGap
        }

        // Room under the heads for an actor's name below its figure, grown with
        // the text; boxed heads sit lower by however much their band's label
        // strip grew past its default 18 (so, at the default size, exactly
        // margin + headHeight + 18 as before).
        let boxDrop = boxed.isEmpty ? 0 : sequenceBoxStrip(measure) - 18
        let arrowsTop = margin + headHeight + grown(18, fontSize: labelFontSize, measure) + boxDrop
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
        let openRowHeight: CGFloat = grown(24, fontSize: 9.5, measure)
        let dividerRowHeight: CGFloat = grown(22, fontSize: 9.5, measure)
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
                let metrics = sequenceTextMetrics(measure)
                let extraLines = CGFloat(max(brLines(message.text).count - 1, 0)) * metrics.line
                // One arrow height for the arrow and the activation bars it
                // opens or closes, so a bar always meets its arrow.
                let arrowY = y + extraLines + rowHeight - metrics.arrowInset
                arrows.append(SequenceLayout.Arrow(
                    fromX: heads[a].lifelineX, toX: toX, y: arrowY,
                    text: message.text, dashed: message.dashed,
                    isSelfMessage: isSelf, head: message.head, number: message.number))
                widen(min(heads[a].lifelineX, toX), max(heads[a].lifelineX, toX))
                if message.activatesTarget { openBar(message.to, at: arrowY) }
                if message.deactivatesSender { closeBar(message.from, at: arrowY) }
                y += rowHeight + extraLines
            case .note(let index):
                let noteItem = diagram.notes[index]
                let ids = noteItem.ids.compactMap { indexOf[$0] }
                guard !ids.isEmpty else { y += noteRowHeight; continue }
                let lines = brLines(noteItem.text)
                let textWidth = lines.map { measure($0, labelFontSize).width }.max() ?? 0
                let boxHeight = max(noteRowHeight - 10, CGFloat(lines.count) * sequenceTextMetrics(measure).noteLine + 9)
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
    /// A pie legend row: 20 at the default size, grown with its 10.5pt text.
    /// The layout sizes the legend with it and both renderers step by it.
    package static func pieLegendRow(_ measure: DiagramTextMeasurer) -> CGFloat {
        grown(20, fontSize: labelFontSize, measure)
    }

    public static func layout(_ pie: PieChart, measure: DiagramTextMeasurer) -> PieLayout {
        let margin: CGFloat = 14
        let radius: CGFloat = 76
        let titleHeight: CGFloat = pie.title == nil ? 0 : Self.titleHeight(26, measure)

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
        let legendHeight = CGFloat(pie.slices.count) * pieLegendRow(measure)

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
        // The title draws semibold, a little wider than measured; the margin
        // beside it grows with it.
        let titleMargin = grown(margin, fontSize: titleFontSize, measure)
        let leftPad = max(margin, titleWidth / 2 - radius + titleMargin)
        let centerX = leftPad + radius
        let legendX = centerX + radius + 28

        let contentRight = legendX + legendWidth + margin
        let titleRight = centerX + titleWidth / 2 + titleMargin
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

/// Boxes (or points, as empty boxes) by index on a uniform grid, for the
/// caption placer: `near` gives every item whose box shares a cell with a
/// query box, in index order. That's a superset of the items the box
/// touches, so a caller that still tests each one exactly loses nothing. A
/// box too large or not finite to grid goes on every query's list instead.
struct PlacementGrid {
    private struct Cell: Hashable { let x: Int; let y: Int }
    /// The cell size for boxes; points, which cluster along routes, use a
    /// finer one (`init(points:)`).
    private static let boxCell: CGFloat = 64
    private static let pointCell: CGFloat = 8
    private let size: CGFloat
    /// Whether every item is a point, so each lies in exactly one cell.
    private let pointsOnly: Bool
    /// The most cells a box may cover before it's treated as everywhere.
    private static let maxCells = 4096
    private var cells: [Cell: [Int]] = [:]
    private var everywhere: [Int] = []

    init(_ boxes: [CGRect]) {
        size = Self.boxCell
        pointsOnly = false
        for (index, box) in boxes.enumerated() { insert(index, box) }
    }

    /// Points, each in exactly one cell, so `count(in:where:)` can count
    /// them without collecting or sorting.
    init(points: [CGPoint]) {
        size = Self.pointCell
        pointsOnly = true
        for (index, point) in points.enumerated() { insert(index, CGRect(origin: point, size: .zero)) }
    }

    /// How many items in the cells `box` covers satisfy `match` (every item,
    /// if `box` can't be gridded). Points only: each is counted once.
    func count(in box: CGRect, where match: (Int) -> Bool) -> Int {
        precondition(pointsOnly, "count(in:where:) counts points, which lie in one cell each")
        guard let span = span(box) else {
            return cells.values.reduce(0) { $0 + $1.filter(match).count } + everywhere.filter(match).count
        }
        var n = everywhere.filter(match).count
        for x in span.x { for y in span.y { for k in cells[Cell(x: x, y: y)] ?? [] where match(k) { n += 1 } } }
        return n
    }

    /// The cells `box` covers, or nil if it's too large or not finite.
    private func span(_ box: CGRect) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
        let bounds = [box.minX, box.maxX, box.minY, box.maxY].map { $0 / size }
        guard bounds.allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else { return nil }
        let x = Int(bounds[0].rounded(.down))...Int(bounds[1].rounded(.down))
        let y = Int(bounds[2].rounded(.down))...Int(bounds[3].rounded(.down))
        return x.count * y.count <= Self.maxCells ? (x, y) : nil
    }

    mutating func insert(_ index: Int, _ box: CGRect) {
        guard let span = span(box) else { everywhere.append(index); return }
        for x in span.x { for y in span.y { cells[Cell(x: x, y: y), default: []].append(index) } }
    }

    /// Every item whose box shares a cell with `box` (all of them, if `box`
    /// can't be gridded), ascending, each once.
    func near(_ box: CGRect) -> [Int] {
        guard let span = span(box) else {
            return (cells.values.flatMap { $0 } + everywhere).sorted().uniqued()
        }
        var found = everywhere
        for x in span.x { for y in span.y { found += cells[Cell(x: x, y: y)] ?? [] } }
        return found.sorted().uniqued()
    }
}

private extension Array where Element == Int {
    /// A sorted array without its repeats.
    func uniqued() -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(count)
        for v in self where out.last != v { out.append(v) }
        return out
    }
}
