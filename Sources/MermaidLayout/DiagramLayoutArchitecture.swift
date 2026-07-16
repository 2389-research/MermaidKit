import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for an architecture diagram: service boxes packed into a grid
/// inside each tinted group container, top-level services in a borderless
/// cluster, and orthogonal wires routed between named sides. Pure geometry.
public struct ArchitectureLayout: Sendable {

    /// A service box (or a small junction dot when `isJunction`).
    public struct ServiceBox: Sendable {
        public let frame: CGRect
        public let label: String
        public let icon: String
        public let isJunction: Bool
        /// Palette slot of the owning group (for a subtle tint).
        public let colorIndex: Int
    }

    /// A tinted group container drawn behind its member services.
    public struct GroupBox: Sendable {
        public let frame: CGRect
        /// Header baseline anchor (left edge, vertical center of the title row).
        public let titleOrigin: CGPoint
        public let label: String
        public let icon: String
        public let colorIndex: Int
    }

    /// A wire between two services.
    public struct Edge: Sendable {
        /// Orthogonal polyline, border anchor to border anchor.
        public let points: [CGPoint]
        /// Draw an arrowhead at the last point.
        public let arrow: Bool
    }

    public let size: CGSize
    public let groups: [GroupBox]
    public let services: [ServiceBox]
    public let edges: [Edge]
}

extension DiagramLayoutEngine {

    /// Lays out an architecture diagram: group containers row-wrapped across
    /// the canvas with member services grid-packed inside each (ungrouped
    /// services form a borderless cluster), and wires routed by an
    /// obstacle-avoiding orthogonal A* so no segment crosses a non-endpoint
    /// box. Pure geometry — the renderer only draws.
    public static func layout(_ diagram: ArchitectureDiagram, measure: DiagramTextMeasurer,
                              spacing: DiagramSpacing = .regular) -> ArchitectureLayout {
        let margin = spacing.resolvedMargin(base: 16)
        let groupGap = spacing.resolvedNodeGap(base: 30)
        let groupPad: CGFloat = 16 * spacing.scale
        let headerHeight: CGFloat = 22
        let serviceGap = spacing.resolvedNodeGap(base: 30)
        let boxH: CGFloat = 54
        let junctionSize: CGFloat = 16
        let maxRowWidth: CGFloat = 780

        // Per-service box width (junctions are fixed dots).
        func boxWidth(_ svc: ArchitectureDiagram.Service) -> CGFloat {
            if svc.isJunction { return junctionSize }
            let w = measure(svc.label, nodeFontSize).width + 22
            return min(max(w, 68), 168)
        }

        // Grid-place a list of services at a content origin; returns their
        // frames plus the content bounding size.
        func gridPlace(_ svcs: [ArchitectureDiagram.Service], originX: CGFloat, originY: CGFloat)
            -> (frames: [String: CGRect], width: CGFloat, height: CGFloat) {
            guard !svcs.isEmpty else { return ([:], 0, 0) }
            let count = svcs.count
            let cols = max(1, Int(ceil(Double(count).squareRoot())))
            let slotW = svcs.map(boxWidth).max() ?? junctionSize
            let slotH = boxH
            var frames: [String: CGRect] = [:]
            var maxCol = 0
            var rowsUsed = 0
            for (i, svc) in svcs.enumerated() {
                let col = i % cols
                let row = i / cols
                maxCol = max(maxCol, col)
                rowsUsed = max(rowsUsed, row)
                let bw = boxWidth(svc)
                let bh = svc.isJunction ? junctionSize : boxH
                let slotX = originX + CGFloat(col) * (slotW + serviceGap)
                let slotY = originY + CGFloat(row) * (slotH + serviceGap)
                frames[svc.id] = CGRect(
                    x: slotX + (slotW - bw) / 2,
                    y: slotY + (slotH - bh) / 2,
                    width: bw, height: bh)
            }
            let width = CGFloat(maxCol + 1) * slotW + CGFloat(maxCol) * serviceGap
            let height = CGFloat(rowsUsed + 1) * slotH + CGFloat(rowsUsed) * serviceGap
            return (frames, width, height)
        }

        var serviceFrames: [String: CGRect] = [:]
        var serviceBoxes: [ArchitectureDiagram.Service: Int] = [:] // service -> colorIndex
        var groupBoxes: [ArchitectureLayout.GroupBox] = []

        var cursorX = margin
        var cursorY = margin
        var rowMaxH: CGFloat = 0
        var maxX = margin
        let rootColorIndex = diagram.groups.count

        func wrapIfNeeded(_ width: CGFloat) {
            if cursorX + width > maxRowWidth + margin && cursorX > margin {
                cursorX = margin
                cursorY += rowMaxH + groupGap
                rowMaxH = 0
            }
        }

        // Declared groups (each with a tinted container).
        for (gi, group) in diagram.groups.enumerated() {
            let members = diagram.services.filter { $0.group == group.id }
            let probe = gridPlace(members, originX: 0, originY: 0)
            let contentW = max(probe.width, measure(group.label, labelFontSize).width + 20)
            let containerW = contentW + groupPad * 2
            let containerH = headerHeight + groupPad + probe.height + groupPad

            wrapIfNeeded(containerW)

            let contentOriginX = cursorX + groupPad
            let contentOriginY = cursorY + headerHeight + groupPad
            let placed = gridPlace(members, originX: contentOriginX, originY: contentOriginY)
            for (id, frame) in placed.frames { serviceFrames[id] = frame }
            for svc in members { serviceBoxes[svc] = gi }

            groupBoxes.append(ArchitectureLayout.GroupBox(
                frame: CGRect(x: cursorX, y: cursorY, width: containerW, height: containerH),
                titleOrigin: CGPoint(x: cursorX + groupPad, y: cursorY + headerHeight / 2 + 3),
                label: group.label,
                icon: group.icon,
                colorIndex: gi))

            cursorX += containerW + groupGap
            rowMaxH = max(rowMaxH, containerH)
            maxX = max(maxX, cursorX - groupGap)
        }

        // Top-level services (no group) as a borderless cluster.
        let rootMembers = diagram.services.filter { svc in
            svc.group == nil || !diagram.groups.contains(where: { $0.id == svc.group })
        }
        if !rootMembers.isEmpty {
            let probe = gridPlace(rootMembers, originX: 0, originY: 0)
            wrapIfNeeded(probe.width)
            let placed = gridPlace(rootMembers, originX: cursorX, originY: cursorY + headerHeight)
            for (id, frame) in placed.frames { serviceFrames[id] = frame }
            for svc in rootMembers { serviceBoxes[svc] = rootColorIndex }
            cursorX += probe.width + groupGap
            rowMaxH = max(rowMaxH, probe.height + headerHeight)
            maxX = max(maxX, cursorX - groupGap)
        }

        let contentBottom = cursorY + rowMaxH

        // Assemble service boxes in declaration order (stable draw order).
        var services: [ArchitectureLayout.ServiceBox] = []
        for svc in diagram.services {
            guard let frame = serviceFrames[svc.id] else { continue }
            services.append(ArchitectureLayout.ServiceBox(
                frame: frame,
                label: svc.label,
                icon: svc.icon,
                isJunction: svc.isJunction,
                colorIndex: serviceBoxes[svc] ?? rootColorIndex))
        }

        // Edges: route orthogonally between named border sides.
        func anchor(_ f: CGRect, _ side: ArchitectureDiagram.Side) -> CGPoint {
            switch side {
            case .left:   return CGPoint(x: f.minX, y: f.midY)
            case .right:  return CGPoint(x: f.maxX, y: f.midY)
            case .top:    return CGPoint(x: f.midX, y: f.minY)
            case .bottom: return CGPoint(x: f.midX, y: f.maxY)
            }
        }
        func out(_ p: CGPoint, _ side: ArchitectureDiagram.Side, _ d: CGFloat) -> CGPoint {
            switch side {
            case .left:   return CGPoint(x: p.x - d, y: p.y)
            case .right:  return CGPoint(x: p.x + d, y: p.y)
            case .top:    return CGPoint(x: p.x, y: p.y - d)
            case .bottom: return CGPoint(x: p.x, y: p.y + d)
            }
        }
        func isHorizontal(_ side: ArchitectureDiagram.Side) -> Bool {
            side == .left || side == .right
        }

        // --- Obstacle-avoiding orthogonal edge routing --------------------
        // Every non-container box (services + junctions) is an obstacle. Each
        // wire leaves its source border by a short stub, then threads the
        // channels between boxes via a lattice A* so no segment cuts through a
        // box that isn't one of its own endpoints.
        let clearance: CGFloat = 9
        let stub: CGFloat = 10

        let allObstacles: [(id: String, rect: CGRect)] =
            serviceFrames.map { ($0.key, $0.value) }

        // Does an axis-aligned segment pass through a rect's interior?
        func segHitsRect(_ p: CGPoint, _ q: CGPoint, _ r: CGRect) -> Bool {
            let eps: CGFloat = 0.001
            if abs(p.x - q.x) < eps { // vertical
                let x = p.x
                guard x > r.minX + eps, x < r.maxX - eps else { return false }
                let lo = min(p.y, q.y), hi = max(p.y, q.y)
                return hi > r.minY + eps && lo < r.maxY - eps
            } else { // horizontal
                let y = p.y
                guard y > r.minY + eps, y < r.maxY - eps else { return false }
                let lo = min(p.x, q.x), hi = max(p.x, q.x)
                return hi > r.minX + eps && lo < r.maxX - eps
            }
        }

        // A* over a lattice whose grid lines are the obstacle borders (already
        // inflated by `clearance`) plus the two route endpoints. A move between
        // adjacent lattice points is allowed only when its segment misses every
        // obstacle. Turns are penalised so routes stay simple.
        func routeGrid(_ start: CGPoint, _ goal: CGPoint, _ obstacles: [CGRect]) -> [CGPoint]? {
            var xsSet: Set<CGFloat> = [start.x, goal.x]
            var ysSet: Set<CGFloat> = [start.y, goal.y]
            for r in obstacles {
                xsSet.insert(r.minX); xsSet.insert(r.maxX)
                ysSet.insert(r.minY); ysSet.insert(r.maxY)
            }
            let xs = xsSet.sorted(), ys = ysSet.sorted()
            let nx = xs.count
            guard let sx = xs.firstIndex(of: start.x), let sy = ys.firstIndex(of: start.y),
                  let gx = xs.firstIndex(of: goal.x), let gy = ys.firstIndex(of: goal.y) else { return nil }
            func nodeIndex(_ ix: Int, _ iy: Int) -> Int { iy * nx + ix }
            func point(_ n: Int) -> CGPoint { CGPoint(x: xs[n % nx], y: ys[n / nx]) }
            let startNode = nodeIndex(sx, sy), goalNode = nodeIndex(gx, gy)
            func heuristic(_ n: Int) -> CGFloat {
                abs(xs[n % nx] - goal.x) + abs(ys[n / nx] - goal.y)
            }
            let turnPenalty: CGFloat = 14
            // State = node * 3 + dir, dir: 0 none, 1 horizontal, 2 vertical.
            var gScore: [Int: CGFloat] = [startNode * 3: 0]
            var cameFrom: [Int: Int] = [:]
            var open = AStarHeap()
            open.push(f: heuristic(startNode), key: startNode * 3)
            var goalKey: Int?
            while let cur = open.popMin() {
                let node = cur / 3, dir = cur % 3
                if node == goalNode { goalKey = cur; break }
                let g = gScore[cur] ?? .greatestFiniteMagnitude
                let ix = node % nx, iy = node / nx
                let steps = [(ix - 1, iy, 1), (ix + 1, iy, 1), (ix, iy - 1, 2), (ix, iy + 1, 2)]
                for (jx, jy, ndir) in steps {
                    guard jx >= 0, jx < nx, jy >= 0, jy < ys.count else { continue }
                    let p = CGPoint(x: xs[ix], y: ys[iy])
                    let q = CGPoint(x: xs[jx], y: ys[jy])
                    if obstacles.contains(where: { segHitsRect(p, q, $0) }) { continue }
                    let n2 = nodeIndex(jx, jy)
                    let cost = abs(q.x - p.x) + abs(q.y - p.y)
                        + (dir != 0 && dir != ndir ? turnPenalty : 0)
                    let key2 = n2 * 3 + ndir
                    if g + cost < (gScore[key2] ?? .greatestFiniteMagnitude) {
                        gScore[key2] = g + cost
                        cameFrom[key2] = cur
                        open.push(f: g + cost + heuristic(n2), key: key2)
                    }
                }
            }
            guard let endKey = goalKey else { return nil }
            var path: [CGPoint] = []
            var k: Int? = endKey
            while let kk = k { path.append(point(kk / 3)); k = cameFrom[kk] }
            return path.reversed()
        }


        // Pick the border side of `f` that faces `other`, so a wire leaves
        // toward its target instead of away from it (the grid layout doesn't
        // honour the declared side for placement, so `waf:R` can point away
        // from a gateway that landed below it — routing then has to cross the
        // box). Prefer the axis with the larger separation.
        func facingSide(_ f: CGRect, toward other: CGRect) -> ArchitectureDiagram.Side {
            let dx = other.midX - f.midX, dy = other.midY - f.midY
            if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
            return dy >= 0 ? .bottom : .top
        }

        var edges: [ArchitectureLayout.Edge] = []
        for edge in diagram.edges {
            guard let fromFrame = serviceFrames[edge.from], let toFrame = serviceFrames[edge.to] else { continue }
            // Fixed-side ports (ELK's FIXED_SIDE): an author-declared side is
            // honored — the A* router treats every box, endpoints included, as
            // an obstacle, so even an away-facing port routes AROUND its own
            // box rather than through it. Only undeclared sides fall back to
            // whichever border faces the other endpoint.
            let fromSide = edge.fromSide ?? facingSide(fromFrame, toward: toFrame)
            let toSide = edge.toSide ?? facingSide(toFrame, toward: fromFrame)
            let a = anchor(fromFrame, fromSide)
            let b = anchor(toFrame, toSide)
            let aOut = out(a, fromSide, stub)
            let bOut = out(b, toSide, stub)

            // Every box is an obstacle — INCLUDING this edge's own endpoints, so
            // the route can never cut back through its source or target box. The
            // stubs (a→aOut, bOut→b) sit just outside each border, so connecting
            // stays clean.
            let obstacles = allObstacles.map { $0.rect.insetBy(dx: -clearance, dy: -clearance) }

            var points: [CGPoint]
            if let mid = routeGrid(aOut, bOut, obstacles), mid.count >= 2 {
                points = [a] + mid + [b]
            } else {
                // Fallback single elbow (should be rare).
                let corner = isHorizontal(fromSide)
                    ? CGPoint(x: bOut.x, y: aOut.y)
                    : CGPoint(x: aOut.x, y: bOut.y)
                points = [a, aOut, corner, bOut, b]
            }
            edges.append(ArchitectureLayout.Edge(points: simplifyCollinear(points), arrow: edge.arrow))
        }

        let width = min(max(maxX + margin, 140), 3900)
        let height = min(max(contentBottom + margin, 100), 3900)
        return ArchitectureLayout(
            size: CGSize(width: width, height: height),
            groups: groupBoxes,
            services: services,
            edges: edges)
    }
}

/// A binary min-heap for the router's A* open set — the previous linear-scan
/// pop made each extraction O(n) and dominated dense-diagram routing time.
private struct AStarHeap {
    private var items: [(f: CGFloat, key: Int)] = []

    mutating func push(f: CGFloat, key: Int) {
        items.append((f, key))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].f < items[parent].f else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func popMin() -> Int? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let left = 2 * i + 1, right = 2 * i + 2
                var smallest = i
                if left < items.count, items[left].f < items[smallest].f { smallest = left }
                if right < items.count, items[right].f < items[smallest].f { smallest = right }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
        return first.key
    }
}
