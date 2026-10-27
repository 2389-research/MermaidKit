#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The caption placer as it stood before it read obstacles through a spatial
/// grid: every candidate scored against every node, caption, bend, crossing
/// and arrowhead. Kept as the reference the fast placer must match bit for
/// bit (see CaptionPlacementEquivalenceTests).
enum ReferenceCaptionPlacer {
    typealias DiagramLayoutEngine = MermaidLayout.DiagramLayoutEngine
    static let flowchartLabelGap = DiagramLayoutEngine.flowchartLabelGap
    static let edgeLabelStub = DiagramLayoutEngine.edgeLabelStub
    static let flowchartMargin = DiagramLayoutEngine.flowchartMargin

    static func placeRunLabelsReference(
        routes: [[CGPoint]],
        labelSizes: [CGSize?],
        nodeFrames: [CGRect],
        headInsets: [CGFloat] = [],
        tailInsets: [CGFloat] = [],
        labelRuns: [Int?] = []
    ) -> [CGPoint?] {
        let obstacles = nodeFrames.map { $0.insetBy(dx: -3, dy: -3) }
        // Fixtures every caption must avoid: the interior bends of every route
        // (a corner) and the points where two routes cross (a junction).
        var bends: [CGPoint] = []
        for pts in routes where pts.count > 2 { bends.append(contentsOf: pts[1..<(pts.count - 1)]) }
        let crossings = referenceCrossingPoints(routes)
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
                let perpNudges: [CGFloat] = [0, perp / 2 + gap / 2, -(perp / 2 + gap / 2)]
                for da in alongShifts {
                    for dp in perpNudges {
                        let cAlong = mid + da
                        let cx = run.horizontal ? cAlong : run.fixed + dp
                        let cy = run.horizontal ? run.fixed + dp : cAlong
                        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
                        var score: CGFloat = 0
                        for o in obstacles { score += referenceOverlapArea(rect, o) * 4 }
                        for l in labelRects {
                            score += referenceOverlapArea(rect, l) * 3
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
                        // Every foreign tip counts (only this route's own head is
                        // exempt, via `tip.route != i`). A foreign arrowhead that
                        // happens to coincide with this route's own endpoint used
                        // to be skipped, but the linter's `label-on-fixture` rule
                        // does NOT exempt it — so skipping it here let the placer
                        // pick an anchor that then failed lint. Score all of them.
                        for tip in arrowTips where tip.route != i {
                            let d = pointRectDistance(tip.p, rect)
                            if d < gap { score += (gap - d) * 6 }
                        }
                        // Stub on each side of the caption on this run.
                        let stub = min((cAlong - along / 2) - run.lo, run.hi - (cAlong + along / 2))
                        if stub < edgeLabelStub { score += (edgeLabelStub - stub) * 6 }
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

    static func referenceCrossingPoints(_ routes: [[CGPoint]]) -> [CGPoint] {
        var pts: [CGPoint] = []
        for i in routes.indices where routes[i].count >= 2 {
            for j in routes.indices where j > i && routes[j].count >= 2 {
                let pi = routes[i], pj = routes[j]
                for a in 0..<(pi.count - 1) {
                    for b in 0..<(pj.count - 1) {
                        if let p = DiagramLayoutEngine.segmentCrossPoint(pi[a], pi[a + 1], pj[b], pj[b + 1]) { pts.append(p) }
                    }
                }
            }
        }
        return pts
    }

    static func referenceOverlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ix = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let iy = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        return ix * iy
    }
}
