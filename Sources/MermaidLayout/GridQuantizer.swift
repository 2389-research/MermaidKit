import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Snaps a laid-out box diagram onto a pixel grid — the transform the
/// grid-alignment metric (``DiagramLayoutLinter/gridAlignment(_:unit:)``) was built
/// to guard. Opt-in via ``DiagramSpacing/gridSnap`` and applied inside the layout
/// dispatch, so both render paths (CoreGraphics + `RenderScene`) and the lint IR
/// inherit *identical* snapped geometry — the draw-vs-scene conformance ratchet
/// stays green for free.
///
/// Node/container frames snap so every coordinate lands on the grid: the origin
/// rounds **down** and the far corner rounds **up**, so a box only ever grows
/// (never clipping its measured label) and its width/height are grid multiples.
/// Edge endpoints are then **re-anchored** onto the snapped node borders — a grown
/// box moves its right/bottom edge independently of the endpoint, so snapping the
/// point alone would detach the arrow — and interior waypoints snap to the nearest
/// grid line, which preserves the orthogonal routing (a segment's shared
/// coordinate snaps identically at both ends).
///
/// Flowchart today; the other box families (block, C4, architecture, ER, class,
/// state) extend the same pattern.
enum GridQuantizer {

    static func quantize(_ layout: FlowchartLayout, unit u: CGFloat) -> FlowchartLayout {
        guard u > 0 else { return layout }

        func down(_ v: CGFloat) -> CGFloat { (v / u).rounded(.down) * u }
        func up(_ v: CGFloat) -> CGFloat { (v / u).rounded(.up) * u }
        func near(_ v: CGFloat) -> CGFloat { (v / u).rounded() * u }
        func snapPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: near(p.x), y: near(p.y)) }

        // A box grows to the enclosing grid cell: origin down, far corner up — so
        // width/height are grid multiples and the content never gets clipped.
        func snapRect(_ r: CGRect) -> CGRect {
            let x0 = down(r.minX), y0 = down(r.minY)
            let x1 = Swift.max(up(r.maxX), x0 + u), y1 = Swift.max(up(r.maxY), y0 + u)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }

        let nodes = layout.nodes.map {
            FlowchartLayout.PlacedNode(id: $0.id, label: $0.label, shape: $0.shape, frame: snapRect($0.frame))
        }
        let containers = layout.containers.map {
            FlowchartLayout.Container(id: $0.id, label: $0.label, frame: snapRect($0.frame), depth: $0.depth)
        }

        // Re-anchor an edge endpoint onto the snapped border of the node it
        // attached to (the nearest original frame), or of the group box it
        // ends on (an edge naming a subgraph), when that border is nearer than
        // any node. A point near neither is free routing geometry and just
        // snaps to the grid.
        let orig = layout.nodes.map(\.frame)
        let snapped = nodes.map(\.frame)
        func reanchor(_ p: CGPoint) -> CGPoint {
            var best = -1
            var bestDist = CGFloat.greatestFiniteMagnitude
            for (i, f) in orig.enumerated() {
                let d = distanceToRect(p, f)
                if d < bestDist { bestDist = d; best = i }
            }
            var box = -1
            var boxDist = CGFloat.greatestFiniteMagnitude
            for (i, c) in layout.containers.enumerated() {
                let d = distanceToPerimeter(p, c.frame)
                if d < boxDist { boxDist = d; box = i }
            }
            if box >= 0, boxDist < bestDist, boxDist <= 8 { return projectToPerimeter(p, containers[box].frame) }
            guard best >= 0, bestDist <= 8 else { return snapPoint(p) }
            return projectToPerimeter(p, snapped[best])
        }

        // Snapping a bend, and growing the box it leaves, can shorten the run
        // off a node; where that leaves it under an end run (and under what
        // it was), the bend steps a cell further out, the jog with it, so no
        // end turns into a hook (`edge-end-hooked`).
        func keepEndRuns(_ pts: inout [CGPoint], was original: [CGPoint]) {
            let n = pts.count
            guard n >= 4, original.count == n else { return }
            for (tip, bend, next) in [(0, 1, 2), (n - 1, n - 2, n - 3)] {
                let along = abs(original[tip].x - original[bend].x) < 0.5 // the run is vertical
                func run(_ p: [CGPoint]) -> CGFloat { along ? abs(p[bend].y - p[tip].y) : abs(p[bend].x - p[tip].x) }
                let want = Swift.min(run(original), DiagramLayoutEngine.flowchartEndRun)
                let out: CGFloat = along ? (pts[bend].y >= pts[tip].y ? u : -u) : (pts[bend].x >= pts[tip].x ? u : -u)
                var steps = 0
                while run(pts) < want - 0.01, steps < 4 {
                    if along { pts[bend].y += out; pts[next].y += out } else { pts[bend].x += out; pts[next].x += out }
                    steps += 1
                }
            }
        }

        let edges = layout.edges.map { e -> FlowchartLayout.PlacedEdge in
            let start = reanchor(e.start), end = reanchor(e.end)
            var pts = e.points.map(snapPoint)
            if !pts.isEmpty { pts[0] = start; pts[pts.count - 1] = end }
            keepEndRuns(&pts, was: e.points)
            return FlowchartLayout.PlacedEdge(
                start: start, end: end, points: pts, label: e.label, dashed: e.dashed,
                hasArrow: e.hasArrow, backArrow: e.backArrow, head: e.head, thick: e.thick,
                invisible: e.invisible, labelPoint: e.labelPoint.map(snapPoint))
        }

        // The canvas grows to hold any box that snapped past the old bounds.
        let maxX = (nodes.map(\.frame.maxX) + containers.map(\.frame.maxX)).max() ?? layout.size.width
        let maxY = (nodes.map(\.frame.maxY) + containers.map(\.frame.maxY)).max() ?? layout.size.height
        let size = CGSize(width: up(Swift.max(layout.size.width, maxX)),
                          height: up(Swift.max(layout.size.height, maxY)))
        return FlowchartLayout(size: size, nodes: nodes, edges: edges, containers: containers)
    }

    /// Euclidean distance from `p` to the nearest point of `r` (0 when inside).
    private static func distanceToRect(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let cx = Swift.min(Swift.max(p.x, r.minX), r.maxX)
        let cy = Swift.min(Swift.max(p.y, r.minY), r.maxY)
        return hypot(p.x - cx, p.y - cy)
    }

    /// Distance from `p` to `r`'s border, from outside or inside.
    private static func distanceToPerimeter(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let outside = distanceToRect(p, r)
        guard outside == 0 else { return outside }
        return Swift.min(Swift.min(p.x - r.minX, r.maxX - p.x), Swift.min(p.y - r.minY, r.maxY - p.y))
    }

    /// The point on `r`'s perimeter nearest to `p` (clamp into the rect, then push
    /// to the closest of the four edges).
    private static func projectToPerimeter(_ p: CGPoint, _ r: CGRect) -> CGPoint {
        let cx = Swift.min(Swift.max(p.x, r.minX), r.maxX)
        let cy = Swift.min(Swift.max(p.y, r.minY), r.maxY)
        let dLeft = cx - r.minX, dRight = r.maxX - cx
        let dTop = cy - r.minY, dBottom = r.maxY - cy
        let m = Swift.min(Swift.min(dLeft, dRight), Swift.min(dTop, dBottom))
        if m == dLeft { return CGPoint(x: r.minX, y: cy) }
        if m == dRight { return CGPoint(x: r.maxX, y: cy) }
        if m == dTop { return CGPoint(x: cx, y: r.minY) }
        return CGPoint(x: cx, y: r.maxY)
    }
}
