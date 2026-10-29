import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Keeping two edges from drawing as one.
///
/// Jogs are spread over tracks within a fan (the edges into one node, or out
/// of one), and `separateRuns` spreads main-axis runs that share a track. But
/// two unrelated edges can still land on one line: two fans jogging in the
/// same gap, or the two edges of a two-cycle whose ports don't line up. Read
/// as one doubled connector, they are the `edges-doubled` the linter rejects.
///
/// This pass finds exactly what that rule finds, two segments of different
/// edges on one line (within 1pt) overlapping by more than 8pt, and moves one
/// of them aside, a jog track at a time, until it is clear (or, where no
/// whole track clears it, half a track: two edges that cross in an X between
/// aligned ports overlap by their jogs' distance on both columns, so only
/// jogs nearer than the tolerance clear them). Only an interior
/// segment moves, so no edge comes off its node, and a move is taken only if
/// its two neighbours keep their direction, nothing moved runs through a
/// node, and no new pair is doubled. A chart with no doubled pair is left
/// exactly as it was.
extension DiagramLayoutEngine {

    /// Overlap along one line beyond which two runs read as one (the
    /// linter's `edges-doubled` tolerance).
    static let doubledRunTolerance: CGFloat = 8

    static func separateDoubledRuns(
        _ routes: inout [[CGPoint]], fixed: Set<Int>, ignored: Set<Int>,
        obstacles: [CGRect], track: CGFloat, endRun: CGFloat = 0, decisions: [CGRect] = []
    ) {
        struct Segment { let edge: Int, index: Int }
        struct Line: Hashable { let horizontal: Bool, at: Int }
        func horizontalRun(_ a: CGPoint, _ b: CGPoint) -> Bool? {
            if abs(a.y - b.y) < 0.5, abs(a.x - b.x) >= 0.5 { return true }
            if abs(a.x - b.x) < 0.5, abs(a.y - b.y) >= 0.5 { return false }
            return nil
        }
        func overlap(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat {
            if abs(a.y - b.y) < 0.5, abs(c.y - d.y) < 0.5, abs(a.y - c.y) < 1 {
                return min(max(a.x, b.x), max(c.x, d.x)) - max(min(a.x, b.x), min(c.x, d.x))
            }
            if abs(a.x - b.x) < 0.5, abs(c.x - d.x) < 0.5, abs(a.x - c.x) < 1 {
                return min(max(a.y, b.y), max(c.y, d.y)) - max(min(a.y, b.y), min(c.y, d.y))
            }
            return 0
        }
        // Segments by orientation and the whole point of their fixed
        // coordinate: a doubled partner lies in the same bucket or the next.
        // Built once, and kept current as segments move.
        func bucket(_ a: CGPoint, _ b: CGPoint) -> Line? {
            guard let h = horizontalRun(a, b) else { return nil }
            return Line(horizontal: h, at: Int((h ? a.y : a.x).rounded(.down)))
        }
        var table: [Line: [Segment]] = [:]
        var filed: [Int: [Int: Line]] = [:]
        func file(_ e: Int, _ k: Int) {
            if let old = filed[e]?[k] { table[old]?.removeAll { $0.edge == e && $0.index == k } }
            filed[e]?[k] = nil
            guard let key = bucket(routes[e][k], routes[e][k + 1]) else { return }
            table[key, default: []].append(Segment(edge: e, index: k))
            filed[e, default: [:]][k] = key
        }
        for (e, pts) in routes.enumerated() where !ignored.contains(e) && pts.count >= 2 {
            for k in 0..<(pts.count - 1) { file(e, k) }
        }
        // A route that gained a point: every segment from the gain on is filed
        // afresh, and the old last one dropped.
        func refile(_ e: Int, from k: Int, oldCount: Int) {
            for j in k..<(oldCount - 1) {
                if let old = filed[e]?[j] { table[old]?.removeAll { $0.edge == e && $0.index == j } }
                filed[e]?[j] = nil
            }
            for j in k..<(routes[e].count - 1) { file(e, j) }
        }
        // The other edges' segments doubled with segment `s` from `a` to `b`.
        func partners(of s: Segment, at a: CGPoint, _ b: CGPoint) -> [Segment] {
            guard let h = horizontalRun(a, b) else { return [] }
            let c = Int((h ? a.y : a.x).rounded(.down))
            var out: [Segment] = []
            for line in (c - 1)...(c + 1) {
                for t in table[Line(horizontal: h, at: line)] ?? [] where t.edge != s.edge
                    && overlap(a, b, routes[t.edge][t.index], routes[t.edge][t.index + 1]) > doubledRunTolerance {
                    out.append(t)
                }
            }
            return out
        }
        let insetObstacles = obstacles.map { $0.insetBy(dx: 1, dy: 1) }
        func crossesObstacle(_ a: CGPoint, _ b: CGPoint) -> Bool {
            let seg = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            return insetObstacles.contains { $0.intersects(seg) }
        }
        // The overlaps (beyond half a point) the segments around `k` of `route`
        // would have with other edges.
        func overlaps(_ e: Int, _ k: Int, _ route: [CGPoint]) -> [CGFloat] {
            var out: [CGFloat] = []
            for j in max(k - 1, 0)...min(k + 1, route.count - 2) {
                let a = route[j], b = route[j + 1]
                guard let h = horizontalRun(a, b) else { continue }
                let c = Int((h ? a.y : a.x).rounded(.down))
                for line in (c - 1)...(c + 1) {
                    for t in table[Line(horizontal: h, at: line)] ?? [] where t.edge != e {
                        let o = overlap(a, b, routes[t.edge][t.index], routes[t.edge][t.index + 1])
                        if o > 0.5 { out.append(o) }
                    }
                }
            }
            return out
        }
        func along(_ p: CGPoint, _ horizontal: Bool) -> CGFloat { horizontal ? p.y : p.x }
        // Whether the run from `end` to `old`, its far end moved to `moved`,
        // keeps its direction and some length (a move further the same way
        // only shortens it more).
        func keeps(_ end: CGPoint, _ old: CGPoint, _ moved: CGPoint, _ horizontal: Bool) -> Bool {
            let before = along(old, horizontal) - along(end, horizontal)
            let after = along(moved, horizontal) - along(end, horizontal)
            return abs(after) >= 2 && (before > 0) == (after > 0)
        }
        // A move's outcome: graded (the route, the moved segment's index in
        // it), or why not.
        enum Move { case grade(Int, [CGPoint], Int), refused, tooFar, immovable }
        // An end segment that runs along its node's face (a jog clamped onto
        // it) can move off the face if a stub, square to the face and away
        // from the node, takes its place.
        func offFace(_ s: Segment, by delta: CGFloat) -> Move? {
            let pts = routes[s.edge], n = pts.count
            let start = s.index == 0, end = s.index + 2 == n
            guard !fixed.contains(s.edge), n >= 3, start || end,
                  let h = horizontalRun(pts[s.index], pts[s.index + 1]) else { return nil }
            let tip = start ? pts[0] : pts[n - 1]
            func shifted(_ p: CGPoint) -> CGPoint { h ? CGPoint(x: p.x, y: p.y + delta) : CGPoint(x: p.x + delta, y: p.y) }
            guard let face = obstacles.first(where: { f in
                h ? (abs(tip.y - f.minY) < 0.5 || abs(tip.y - f.maxY) < 0.5) && tip.x >= f.minX - 0.5 && tip.x <= f.maxX + 0.5
                  : (abs(tip.x - f.minX) < 0.5 || abs(tip.x - f.maxX) < 0.5) && tip.y >= f.minY - 0.5 && tip.y <= f.maxY + 0.5
            }) else { return nil }
            let out = shifted(tip)
            // The stub leaves the node, and the run beyond keeps its way.
            guard !face.insetBy(dx: 0.5, dy: 0.5).contains(out) else { return .tooFar }
            if start {
                guard keeps(pts[2], pts[1], shifted(pts[1]), h) else { return .tooFar }
                return .grade(0, [pts[0], out, shifted(pts[1])] + pts[2...], 1)
            }
            guard keeps(pts[n - 3], pts[n - 2], shifted(pts[n - 2]), h) else { return .tooFar }
            return .grade(0, Array(pts[..<(n - 2)]) + [shifted(pts[n - 2]), out, pts[n - 1]], n - 2)
        }
        // How segment `s` moved by `delta` across its line would do, without
        // moving it: grade 0 if nothing it changes shares a line with another
        // edge at all, 1 if only within the tolerance, 2 if fewer pairs are
        // doubled than the `doubledNow` before (where three runs share a line,
        // one move can't clear them all, but each such move leaves fewer, so
        // it ends). Only a grade below `than` is worth testing against nodes.
        func evaluate(_ s: Segment, by delta: CGFloat, better than: Int, doubledNow: Int) -> Move {
            var pts = routes[s.edge]
            var k = s.index
            if let face = offFace(s, by: delta) {
                guard case .grade(_, let route, let moved) = face else { return face }
                pts = route; k = moved
            } else {
                guard !fixed.contains(s.edge), k > 0, k + 2 < pts.count,
                      let h = horizontalRun(pts[k], pts[k + 1]),
                      horizontalRun(pts[k - 1], pts[k]) == !h,
                      horizontalRun(pts[k + 1], pts[k + 2]) == !h else { return .immovable }
                func shifted(_ p: CGPoint) -> CGPoint { h ? CGPoint(x: p.x, y: p.y + delta) : CGPoint(x: p.x + delta, y: p.y) }
                let a = shifted(pts[k]), b = shifted(pts[k + 1])
                guard keeps(pts[k - 1], pts[k], a, h), keeps(pts[k + 2], pts[k + 1], b, h) else { return .tooFar }
                // Nor may it shorten a run off a node below an end run: the
                // end would read as a hook (`edge-end-hooked`). A decision's
                // vertex is exempt: its branches fork there, and may at once.
                func hooks(_ tip: CGPoint, _ old: CGPoint, _ new: CGPoint) -> Bool {
                    guard !decisions.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(tip) }) else { return false }
                    let was = hypot(old.x - tip.x, old.y - tip.y), now = hypot(new.x - tip.x, new.y - tip.y)
                    return now < was && now < endRun
                }
                if k - 1 == 0, hooks(pts[0], pts[1], a) { return .tooFar }
                if k + 2 == pts.count - 1, hooks(pts[k + 2], pts[k + 1], b) { return .tooFar }
                pts[k] = a; pts[k + 1] = b
            }
            let found = overlaps(s.edge, k, pts)
            let doubled = found.filter { $0 > doubledRunTolerance }.count
            let grade: Int
            if found.isEmpty { grade = 0 }
            else if doubled == 0 { grade = 1 }
            else if doubled < doubledNow { grade = 2 }
            else { return .refused }
            // Nodes last: the costliest test, and only for a move worth taking.
            guard grade < than else { return .refused }
            for j in (k - 1)...(k + 1) where crossesObstacle(pts[j], pts[j + 1]) { return .refused }
            return .grade(grade, pts, k)
        }

        let offsets = (1...16).flatMap { [CGFloat($0) * track, -CGFloat($0) * track] }
        let halves = (0..<16).flatMap { [(CGFloat($0) + 0.5) * track, -(CGFloat($0) + 0.5) * track] }
        // The best move for any of `candidates`, in order: the first of the
        // lowest grade, by whole tracks before half ones; nil if none helps.
        func bestMove(_ candidates: [Segment]) -> (edge: Int, route: [CGPoint], moved: Int)? {
            var best: (grade: Int, edge: Int, route: [CGPoint], moved: Int)?
            for offsets in [offsets, halves] where best?.grade != 0 {
                for c in candidates {
                    let route = routes[c.edge]
                    let doubledNow = overlaps(c.edge, c.index, route).filter { $0 > doubledRunTolerance }.count
                    var blocked: Set<Bool> = []          // signs gone too far
                    for delta in offsets where !blocked.contains(delta > 0) {
                        switch evaluate(c, by: delta, better: best?.grade ?? 3, doubledNow: doubledNow) {
                        case .grade(let g, let route, let moved):
                            best = (g, c.edge, route, moved)
                            if g == 0 { return (c.edge, route, moved) }
                        case .immovable: blocked = [true, false]
                        case .tooFar: blocked.insert(delta > 0)
                        case .refused: break
                        }
                    }
                }
            }
            return best.map { ($0.edge, $0.route, $0.moved) }
        }
        func doubled(_ s: Segment) -> [Segment] {
            let pts = routes[s.edge]
            return partners(of: s, at: pts[s.index], pts[s.index + 1])
                .sorted { ($0.edge, $0.index) < ($1.edge, $1.index) }
        }
        // Every doubled pair, in route order; each is checked again when its
        // turn comes, since an earlier move may have cleared it.
        var work: [(Segment, Segment)] = []
        for (e, pts) in routes.enumerated() where !ignored.contains(e) && pts.count >= 2 {
            for k in 0..<(pts.count - 1) {
                let s = Segment(edge: e, index: k)
                for t in doubled(s) where t.edge > e { work.append((s, t)) }
            }
        }
        var head = 0
        var budget = 4 * routes.reduce(0) { $0 + max($1.count - 1, 0) }
        while head < work.count, budget > 0 {
            let (s, t) = work[head]
            head += 1
            budget -= 1
            let pts = routes[s.edge], other = routes[t.edge]
            guard overlap(pts[s.index], pts[s.index + 1], other[t.index], other[t.index + 1])
                    > doubledRunTolerance else { continue }
            // The later edge's segment moves first; failing that, the earlier.
            // A segment that can't move (it meets a node) can still be
            // shortened clear of the other: move the jog beside it instead.
            var candidates: [Segment] = [t, s]
            for c in [t, s] {
                for j in [c.index - 1, c.index + 1] where j >= 0 && j + 1 < routes[c.edge].count {
                    candidates.append(Segment(edge: c.edge, index: j))
                }
            }
            // A move that clears every line wins over one that only gets
            // under the tolerance, and that over one that only leaves fewer.
            var moved: Segment?
            if let best = bestMove(candidates) {
                let oldCount = routes[best.edge].count
                routes[best.edge] = best.route
                if best.route.count == oldCount {
                    for j in (best.moved - 1)...(best.moved + 1) { file(best.edge, j) }
                } else {
                    refile(best.edge, from: 0, oldCount: oldCount)
                }
                moved = Segment(edge: best.edge, index: best.moved)
            }
            // What a move that only left fewer pairs still doubles waits its turn.
            if let m = moved {
                for j in (m.index - 1)...(m.index + 1) {
                    let c = Segment(edge: m.edge, index: j)
                    for p in doubled(c) { work.append(p.edge > c.edge ? (c, p) : (p, c)) }
                }
            }
        }
    }
}

extension DiagramLayoutEngine {

    /// Reorders the jogs in each layer gap so they cross as little as they
    /// can (#112). A jog is the cross-axis step of a route that comes into
    /// the gap from one side and leaves by the other: in a top-down chart, a
    /// run down from above, a step across at the jog's height, a run down
    /// below. Two jogs in one gap cross only where one's run passes through
    /// the other's step, so which of the two is higher decides it: with P
    /// above Q, Q's run down from above crosses P's step if it lies within
    /// it, and P's run on down crosses Q's step if that lies within Q's.
    ///
    /// Fans choose each gap's tracks; this keeps exactly those tracks, so the
    /// gap's room still holds, and only changes which jog takes which,
    /// moving one jog at a time to wherever in the order it crosses least,
    /// while any move does. A captioned edge's single bend stops an end run
    /// short of its target, so its caption has one long run; where that
    /// crosses, it may stop as short of its source, where the caption still
    /// fits, or go back to its own fan track (`captionBends`).
    /// No move brings a run within `near` of another edge's, where the two
    /// would draw as one or be straightened onto each other.
    static func orderJogsInGaps(
        _ routes: inout [[CGPoint]], gaps: [(lo: CGFloat, hi: CGFloat)],
        horizontal: Bool, captionBends: [Int: (natural: CGFloat, source: CGFloat?)] = [:],
        captioned: Set<Int> = [], track: CGFloat, near: CGFloat = 8, ignored: Set<Int>
    ) {
        guard !gaps.isEmpty else { return }
        func cross(_ p: CGPoint) -> CGFloat { horizontal ? p.y : p.x }
        func main(_ p: CGPoint) -> CGFloat { horizontal ? p.x : p.y }
        struct Jog {
            var edge: Int, at: Int, main: CGFloat, lo: CGFloat, hi: CGFloat, top: CGFloat, bottom: CGFloat
            /// Where its runs start above the gap and end below it.
            var upper: CGFloat, lower: CGFloat
            /// For a captioned bend, the other places it may take: short of
            /// its source, keeping its caption, then its fan track.
            var options: [CGFloat] = []
            var isBend = false
            /// Stays on its track: a captioned jog that isn't such a bend,
            /// whose caption was placed for it, or one sharing an end with
            /// another, whose runs into that end would draw as one.
            var pinned = false
        }
        var byGap: [Int: [Jog]] = [:]
        for (e, pts) in routes.enumerated() where !ignored.contains(e) && pts.count >= 4 {
            for k in 1..<(pts.count - 2) {
                let a = pts[k], b = pts[k + 1]
                guard abs(main(a) - main(b)) < 0.5, abs(cross(a) - cross(b)) > 0.5 else { continue }
                let before = pts[k - 1], after = pts[k + 2]
                guard abs(cross(before) - cross(a)) < 0.5, abs(cross(after) - cross(b)) < 0.5 else { continue }
                let m = main(a)
                guard let g = gaps.firstIndex(where: { $0.lo - 0.5 <= m && m <= $0.hi + 0.5 }) else { continue }
                // Into the gap from one side and out by the other, past both ends.
                let down = main(before) < main(after)
                let (upper, lower) = down ? (before, after) : (after, before)
                guard main(upper) <= gaps[g].lo + 0.5, main(lower) >= gaps[g].hi - 0.5 else { continue }
                let (top, bottom) = down ? (cross(a), cross(b)) : (cross(b), cross(a))
                var jog = Jog(edge: e, at: k, main: m, lo: min(cross(a), cross(b)), hi: max(cross(a), cross(b)),
                              top: top, bottom: bottom, upper: main(upper), lower: main(lower))
                if let bend = captionBends[e], pts.count == 4 {
                    jog.isBend = true
                    // The source is the route's first point.
                    let source = bend.source.map { main(pts[0]) + (main(pts[3]) > main(pts[0]) ? $0 : -$0) }
                    for t in [source, bend.natural].compactMap({ $0 })
                    where abs(t - m) > 0.5 && gaps[g].lo - 0.5 <= t && t <= gaps[g].hi + 0.5 { jog.options.append(t) }
                } else if captioned.contains(e) {
                    jog.pinned = true
                }
                byGap[g, default: []].append(jog)
            }
        }
        for g in byGap.keys.sorted() {
            var jogs = byGap[g]!
            let n = jogs.count
            guard n > 1 else { continue }
            func within(_ c: CGFloat, _ j: Jog) -> Bool { j.lo + 0.5 < c && c < j.hi - 0.5 }
            // Touching counts: two jogs that meet end to end can't share a track.
            func overlaps(_ p: Jog, _ q: Jog) -> Bool { min(p.hi, q.hi) - max(p.lo, q.lo) > -0.5 }
            for p in 0..<n {
                for q in 0..<n where p != q && jogs[p].edge != jogs[q].edge
                    && (abs(jogs[p].top - jogs[q].top) < 0.5 || abs(jogs[p].bottom - jogs[q].bottom) < 0.5) {
                    jogs[p].pinned = true; jogs[p].options = []
                }
            }
            // cost[p][q]: crossings between p and q with p above q.
            var cost = [[Int]](repeating: [Int](repeating: 0, count: n), count: n)
            var any = false
            for p in 0..<n {
                for q in 0..<n where p != q && jogs[p].edge != jogs[q].edge {
                    cost[p][q] = (within(jogs[q].top, jogs[p]) ? 1 : 0) + (within(jogs[p].bottom, jogs[q]) ? 1 : 0)
                    if cost[p][q] > 0 { any = true }
                }
            }
            guard any else { continue }
            func crossings(_ order: [Int]) -> Int {
                var total = 0
                for (i, p) in order.enumerated() { for q in order[(i + 1)...] { total += cost[p][q] } }
                return total
            }
            let byMain = Array(0..<n).sorted {
                (jogs[$0].main, jogs[$0].edge, jogs[$0].at) < (jogs[$1].main, jogs[$1].edge, jogs[$1].at)
            }
            let before = crossings(byMain)
            // Bends and pinned jogs sit where they are put; the rest move to
            // wherever in the order they cross least.
            func arrange(_ order: [Int], fixed: (Int) -> Bool) -> [Int] {
                var order = order
                var improved = true, rounds = 0
                while improved && rounds < 4 {
                    improved = false; rounds += 1
                    for x in order where !fixed(x) {
                        let rest = order.filter { $0 != x }
                        // Crossings with x at each place among the rest:
                        // those before it are above it.
                        var here = rest.reduce(0) { $0 + cost[x][$1] }
                        var best = here, bestAt = 0
                        for (i, o) in rest.enumerated() {
                            here += cost[o][x] - cost[x][o]
                            if here < best { best = here; bestAt = i + 1 }
                        }
                        let now = order.firstIndex(of: x)!
                        let current = rest.prefix(now).reduce(0) { $0 + cost[$1][x] }
                            + rest.dropFirst(now).reduce(0) { $0 + cost[x][$1] }
                        if best < current {
                            var next = rest; next.insert(x, at: bestAt); order = next
                            improved = true
                        }
                    }
                }
                return order
            }
            // The free jogs' tracks, each used at most once by jogs that overlap.
            let free = byMain.filter { !jogs[$0].isBend && !jogs[$0].pinned }
            var tracks: [CGFloat] = []
            for t in free.map({ jogs[$0].main }) where tracks.last.map({ t - $0 > 0.5 }) ?? true { tracks.append(t) }
            // Down an order, each free jog keeps its track if that is still
            // below every earlier one it overlaps, else takes the next free
            // one (or, failing that, every one the first free one). A bend or
            // pinned jog sits where it is put, past every earlier jog it
            // overlaps, by half a track from an earlier bend. Nil when the
            // order can't be held.
            func assign(_ order: [Int], at: [Int: CGFloat], keeping: Bool) -> [Int: CGFloat]? {
                var assigned: [Int: CGFloat] = [:]
                for (i, j) in order.enumerated() {
                    let earlier = order[..<i].filter { overlaps(jogs[$0], jogs[j]) }
                    let floor = earlier.compactMap { assigned[$0] }.max()
                    if let t = at[j] {
                        guard floor.map({ t > $0 + 0.5 }) ?? true,
                              earlier.allSatisfy({ !jogs[$0].isBend || t - assigned[$0]! >= track / 2 }) else { return nil }
                        assigned[j] = t
                    } else if keeping, floor.map({ jogs[j].main > $0 + 0.5 }) ?? true {
                        assigned[j] = jogs[j].main
                    } else {
                        guard let t = tracks.first(where: { t in floor.map { t > $0 + 0.5 } ?? true }) else { return nil }
                        assigned[j] = t
                    }
                }
                return assigned
            }
            // Runs of other edges within `near` of a jog's two runs, along
            // more than the doubled tolerance.
            let current = routes
            func beside(_ j: Int, at t: CGFloat) -> Int {
                let jog = jogs[j]
                var count = 0
                for (c, from, to) in [(jog.top, jog.upper, t), (jog.bottom, t, jog.lower)] {
                    let (lo, hi) = (min(from, to), max(from, to))
                    for (e, pts) in current.enumerated() where e != jog.edge && !ignored.contains(e) && pts.count >= 2 {
                        for (a, b) in zip(pts, pts.dropFirst()) where abs(cross(a) - cross(b)) < 0.5
                            && abs(cross(a) - c) < near
                            && min(hi, max(main(a), main(b))) - max(lo, min(main(a), main(b))) > doubledRunTolerance {
                            count += 1
                        }
                    }
                }
                return count
            }
            func crowds(_ assigned: [Int: CGFloat]) -> Bool {
                assigned.contains { j, t in abs(t - jogs[j].main) > 0.01 && beside(j, at: t) > beside(j, at: jogs[j].main) }
            }
            // Each bend where it is or at one of its other places, every way
            // while there are few: the fewest crossings wins, then the fewest
            // captions cut short (a bend back on its fan track), then the
            // fewest bends moved, of the ways the gap can hold.
            let bends = byMain.filter { !jogs[$0].options.isEmpty }
            // While the ways stay few; a bend past that stays where it is.
            var choices: [[Int]] = [[]]
            var tried: [Int] = []
            for j in bends where choices.count * (jogs[j].options.count + 1) <= 64 {
                choices = choices.flatMap { c in (0...jogs[j].options.count).map { c + [$0] } }
                tried.append(j)
            }
            var ways: [(order: [Int], at: [Int: CGFloat], crossings: Int, cut: Int, moved: Int)] = []
            for choice in choices {
                var at: [Int: CGFloat] = [:]
                for j in byMain where jogs[j].isBend || jogs[j].pinned { at[j] = jogs[j].main }
                var cut = 0
                for (j, pick) in zip(tried, choice) where pick > 0 {
                    at[j] = jogs[j].options[pick - 1]
                    if abs(at[j]! - captionBends[jogs[j].edge]!.natural) < 0.5 { cut += 1 }
                }
                let start = byMain.sorted { (at[$0] ?? jogs[$0].main, $0) < (at[$1] ?? jogs[$1].main, $1) }
                let order = arrange(start, fixed: { at[$0] != nil })
                ways.append((order, at, crossings(order), cut, choice.filter { $0 > 0 }.count))
            }
            ways.sort { ($0.crossings, $0.cut, $0.moved) < ($1.crossings, $1.cut, $1.moved) }
            guard let (_, assigned) = ways.lazy.filter({ $0.crossings < before }).compactMap({ way in
                [true, false].lazy.compactMap { assign(way.order, at: way.at, keeping: $0) }
                    .first { !crowds($0) }.map { (way, $0) }
            }).first else { continue }
            for (j, t) in assigned where abs(t - jogs[j].main) > 0.01 {
                let jog = jogs[j]
                for k in [jog.at, jog.at + 1] {
                    routes[jog.edge][k] = horizontal ? CGPoint(x: t, y: routes[jog.edge][k].y)
                                                     : CGPoint(x: routes[jog.edge][k].x, y: t)
                }
            }
        }
    }
}
