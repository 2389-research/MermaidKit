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
        // attached to (the nearest original frame). A point not near any node is
        // free routing geometry and just snaps to the grid.
        let orig = layout.nodes.map(\.frame)
        let snapped = nodes.map(\.frame)
        func reanchor(_ p: CGPoint) -> CGPoint {
            var best = -1
            var bestDist = CGFloat.greatestFiniteMagnitude
            for (i, f) in orig.enumerated() {
                let d = distanceToRect(p, f)
                if d < bestDist { bestDist = d; best = i }
            }
            guard best >= 0, bestDist <= 8 else { return snapPoint(p) }
            return projectToPerimeter(p, snapped[best])
        }

        let edges = layout.edges.map { e -> FlowchartLayout.PlacedEdge in
            let start = reanchor(e.start), end = reanchor(e.end)
            var pts = e.points.map(snapPoint)
            if !pts.isEmpty { pts[0] = start; pts[pts.count - 1] = end }
            return FlowchartLayout.PlacedEdge(
                start: start, end: end, points: pts, label: e.label, dashed: e.dashed,
                hasArrow: e.hasArrow, backArrow: e.backArrow, labelPoint: e.labelPoint.map(snapPoint))
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
