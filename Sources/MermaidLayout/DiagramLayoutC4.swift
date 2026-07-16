import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for a C4 diagram: elements as uniform-width labelled boxes placed
/// in a simple relationship-layered grid, with orthogonally-routed labelled
/// arrows between them that thread the empty channels between rows (and a side
/// gutter lane for multi-row hops) so no arrow crosses an unrelated box. People
/// carry a small drawn "head" (the renderer adds it above the box top). Pure
/// geometry — the renderer only draws.
public struct C4Layout: Sendable {
    /// One C4 element box.
    public struct Box: Sendable {
        public let frame: CGRect
        /// e.g. «Person», «External System», «Container».
        public let stereotype: String
        /// Bold title, word-wrapped to the box width.
        public let titleLines: [String]
        /// Technology tag + description, word-wrapped.
        public let detailLines: [String]
        public let isPerson: Bool
        public let external: Bool
        public let colorIndex: Int
    }

    /// A labelled relationship arrow.
    public struct Edge: Sendable {
        /// Orthogonal routed polyline, endpoint to endpoint (>= 2 points). The
        /// route threads the empty channels between rows (and, for edges that
        /// span more than one row, a clear lane in the side gutter) so it never
        /// crosses a non-endpoint box.
        public let points: [CGPoint]
        public let label: String?
        /// Where the label is drawn — a point on the route that lies in a clear
        /// channel band, so it doesn't sit on a box.
        public let labelPoint: CGPoint
        /// First route point, kept for callers that want the endpoints.
        public var from: CGPoint { points.first ?? .zero }
        /// Last route point (the arrowhead end).
        public var to: CGPoint { points.last ?? .zero }
    }

    public let size: CGSize
    public let title: String?
    public let boxes: [Box]
    public let edges: [Edge]
}

extension DiagramLayoutEngine {

    /// Lays out a C4 diagram: elements as uniform-width boxes in
    /// relationship-layered, horizontally centered rows; arrows thread the
    /// empty channels between rows (multi-row hops via side-gutter lanes) and
    /// same-channel labels fan out vertically. Pure geometry — the renderer
    /// only draws.
    public static func layout(_ diagram: C4Diagram, measure: DiagramTextMeasurer) -> C4Layout {
        let margin: CGFloat = 16
        let titleHeight: CGFloat = diagram.title == nil ? 0 : 24
        let boxWidth: CGFloat = 176
        let pad: CGFloat = 10
        let textWidth = boxWidth - pad * 2
        let stereoH: CGFloat = 13
        let titleGap: CGFloat = 3
        let titleLineH: CGFloat = 16
        let detailLineH: CGFloat = 13
        let hGap: CGFloat = 26
        let vGap: CGFloat = 62          // room for arrows, stacked labels, a person's head
        let maxCols = 6

        // Greedy word-wrap capped at `maxLines`; the last kept line absorbs the
        // remainder so nothing is silently dropped.
        func wrap(_ text: String, fontSize: Double, maxLines: Int) -> [String] {
            guard maxLines > 0 else { return [] }
            let words = text.split(separator: " ").map(String.init)
            guard !words.isEmpty else { return [] }
            var lines: [String] = []
            var current = ""
            for word in words {
                let candidate = current.isEmpty ? word : current + " " + word
                if current.isEmpty || measure(candidate, fontSize).width <= textWidth {
                    current = candidate
                } else {
                    lines.append(current)
                    current = word
                    if lines.count == maxLines - 1 { break }
                }
            }
            if !current.isEmpty { lines.append(current) }
            return Array(lines.prefix(maxLines))
        }

        func stereotype(_ e: C4Diagram.Element) -> String {
            let base: String
            switch e.kind {
            case .person: base = "Person"
            case .system: base = "System"
            case .container: base = "Container"
            case .component: base = "Component"
            }
            return "\u{00AB}\(e.external ? "External " : "")\(base)\u{00BB}"
        }

        func colorIndex(_ e: C4Diagram.Element) -> Int {
            switch e.kind {
            case .person: return 0
            case .system: return 1
            case .container: return 2
            case .component: return 3
            }
        }

        // Per-element content + measured height.
        struct Content {
            let stereotype: String
            let titleLines: [String]
            let detailLines: [String]
            let isPerson: Bool
            let external: Bool
            let colorIndex: Int
            let height: CGFloat
        }

        let contents: [Content] = diagram.elements.map { e in
            let titleLines = wrap(e.label, fontSize: nodeFontSize, maxLines: 2)
            var details: [String] = []
            if let tech = e.technology, !tech.isEmpty { details.append("[\(tech)]") }
            if let d = e.descr, !d.isEmpty {
                details += wrap(d, fontSize: labelFontSize, maxLines: max(0, 3 - details.count))
            }
            let titleCount = max(titleLines.count, 1)
            let height = pad + stereoH + titleGap + CGFloat(titleCount) * titleLineH
                + (details.isEmpty ? 0 : 4 + CGFloat(details.count) * detailLineH) + pad
            return Content(
                stereotype: stereotype(e),
                titleLines: titleLines.isEmpty ? [e.label] : titleLines,
                detailLines: details,
                isPerson: e.kind == .person,
                external: e.external,
                colorIndex: colorIndex(e),
                height: height
            )
        }

        let aliasIndex = Dictionary(diagram.elements.enumerated().map { ($1.alias, $0) },
                                    uniquingKeysWith: { a, _ in a })
        let n = diagram.elements.count

        // Relationship layering: longest-path from sources, capped so cycles
        // can't run the layer count away.
        var adjacency: [(Int, Int)] = []
        for r in diagram.relations {
            guard let f = aliasIndex[r.from], let t = aliasIndex[r.to], f != t else { continue }
            adjacency.append((f, t))
        }
        var layer = [Int](repeating: 0, count: n)
        for _ in 0..<max(n, 1) {
            var changed = false
            for (f, t) in adjacency where layer[t] < layer[f] + 1 && layer[f] + 1 <= n {
                layer[t] = layer[f] + 1
                changed = true
            }
            if !changed { break }
        }

        // Group element indices by layer (appearance order within a layer),
        // then split oversized layers into chunks so no visual row overflows.
        let maxLayer = layer.max() ?? 0
        var visualRows: [[Int]] = []
        for l in 0...maxLayer {
            let inLayer = (0..<n).filter { layer[$0] == l }
            guard !inLayer.isEmpty else { continue }
            var i = 0
            while i < inLayer.count {
                visualRows.append(Array(inLayer[i..<min(i + maxCols, inLayer.count)]))
                i += maxCols
            }
        }
        if visualRows.isEmpty { visualRows = [Array(0..<n)] }

        let widestCols = visualRows.map(\.count).max() ?? 1
        let canvasWidth = max(220,
            margin * 2 + CGFloat(widestCols) * boxWidth + CGFloat(widestCols - 1) * hGap)

        // Place boxes row by row, each row centered horizontally, top-aligned
        // within the row's tallest box. Record each element's visual row so the
        // edge router knows which channels to thread.
        var frames = [CGRect](repeating: .zero, count: n)
        var rowOf = [Int](repeating: 0, count: n)
        var y = margin + titleHeight + 12       // +12: headroom for people in row 0
        for (rowIndex, row) in visualRows.enumerated() {
            let rowHeight = row.map { contents[$0].height }.max() ?? 0
            let rowWidth = CGFloat(row.count) * boxWidth + CGFloat(row.count - 1) * hGap
            var x = (canvasWidth - rowWidth) / 2
            for idx in row {
                frames[idx] = CGRect(x: x, y: y, width: boxWidth, height: contents[idx].height)
                rowOf[idx] = rowIndex
                x += boxWidth + hGap
            }
            y += rowHeight + vGap
        }
        let canvasHeight = y - vGap + margin

        // A validated route (see below) for every relation whose endpoints
        // exist and differ, computed against the *pre-shift* frames.
        struct Plan {
            let f: Int, t: Int
            let rf: Int, rt: Int
            let label: String?
        }
        var plans: [Plan] = []
        for r in diagram.relations {
            guard let f = aliasIndex[r.from], let t = aliasIndex[r.to], f != t else { continue }
            let text = r.technology.map { r.label.isEmpty ? "[\($0)]" : "\(r.label) [\($0)]" } ?? r.label
            plans.append(Plan(f: f, t: t, rf: rowOf[f], rt: rowOf[t],
                              label: text.isEmpty ? nil : text))
        }

        // Multi-row edges hop through a vertical lane in a side gutter. Assign
        // each such edge to the left or right gutter (whichever its endpoints
        // sit nearer) and give it a distinct lane index there, so lanes never
        // collapse onto each other.
        let laneSpacing: CGFloat = 16
        let centerPre = canvasWidth / 2
        var laneIsLeft = [Bool](repeating: true, count: plans.count)
        var laneIdx = [Int](repeating: 0, count: plans.count)
        var leftLanes = 0, rightLanes = 0
        for (i, p) in plans.enumerated() where abs(p.rf - p.rt) >= 2 {
            let mid = (frames[p.f].midX + frames[p.t].midX) / 2
            let isLeft = mid < centerPre
            laneIsLeft[i] = isLeft
            if isLeft { laneIdx[i] = leftLanes; leftLanes += 1 }
            else { laneIdx[i] = rightLanes; rightLanes += 1 }
        }
        let leftReserve: CGFloat = leftLanes > 0 ? laneSpacing * CGFloat(leftLanes) + 12 : 0
        let rightReserve: CGFloat = rightLanes > 0 ? laneSpacing * CGFloat(rightLanes) + 12 : 0

        // Slide everything right to open the left gutter, then widen for both.
        if leftReserve > 0 {
            for i in 0..<n { frames[i].origin.x += leftReserve }
        }
        let finalWidth = canvasWidth + leftReserve + rightReserve

        // Per-row vertical extents (y is unaffected by the horizontal shift).
        var rowTop = [CGFloat](repeating: 0, count: visualRows.count)
        var rowBottom = [CGFloat](repeating: 0, count: visualRows.count)
        for (r, row) in visualRows.enumerated() {
            rowTop[r] = row.map { frames[$0].minY }.min() ?? 0
            rowBottom[r] = row.map { frames[$0].maxY }.max() ?? 0
        }
        // Midline of the empty channel just below row `r` (== just above r+1).
        func channelBelow(_ r: Int) -> CGFloat {
            r + 1 < visualRows.count ? (rowBottom[r] + rowTop[r + 1]) / 2
                                     : rowBottom[r] + vGap / 2
        }
        func channelAbove(_ r: Int) -> CGFloat {
            r - 1 >= 0 ? (rowBottom[r - 1] + rowTop[r]) / 2
                       : rowTop[r] - vGap / 2
        }
        func laneX(isLeft: Bool, _ idx: Int) -> CGFloat {
            isLeft ? 10 + laneSpacing * CGFloat(idx)
                   : finalWidth - 10 - laneSpacing * CGFloat(idx)
        }

        let boxes: [C4Layout.Box] = (0..<n).map { i in
            let c = contents[i]
            return C4Layout.Box(
                frame: frames[i],
                stereotype: c.stereotype,
                titleLines: c.titleLines,
                detailLines: c.detailLines,
                isPerson: c.isPerson,
                external: c.external,
                colorIndex: c.colorIndex
            )
        }

        // Orthogonal edge routing. Every horizontal run lives in an empty
        // channel between rows (or a side lane), every vertical run stays in a
        // box's own column or a clear gutter lane — so a route only ever touches
        // its two endpoint boxes.
        struct Route { let points: [CGPoint]; let label: String?; var labelPoint: CGPoint }
        var routes: [Route] = []
        for (i, p) in plans.enumerated() {
            let sf = frames[p.f], tf = frames[p.t]
            let points: [CGPoint]
            let labelPoint: CGPoint

            if p.rf == p.rt {
                // Same row: dip into the channel below (or above, on the last row).
                if p.rf + 1 < visualRows.count {
                    let ch = channelBelow(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.maxY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.maxY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                } else {
                    let ch = channelAbove(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.minY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.minY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                }
            } else if abs(p.rf - p.rt) == 1 {
                // Adjacent rows: a single channel step between them.
                if p.rt > p.rf {
                    let ch = channelBelow(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.maxY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.minY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                } else {
                    let ch = channelAbove(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.minY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.maxY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                }
            } else {
                // Multi-row: out to a side-gutter lane, down/up the lane, back in.
                let lx = laneX(isLeft: laneIsLeft[i], laneIdx[i])
                if p.rt > p.rf {
                    let chS = channelBelow(p.rf), chT = channelAbove(p.rt)
                    points = [CGPoint(x: sf.midX, y: sf.maxY),
                              CGPoint(x: sf.midX, y: chS),
                              CGPoint(x: lx, y: chS),
                              CGPoint(x: lx, y: chT),
                              CGPoint(x: tf.midX, y: chT),
                              CGPoint(x: tf.midX, y: tf.minY)]
                    labelPoint = CGPoint(x: (lx + tf.midX) / 2, y: chT)
                } else {
                    let chS = channelAbove(p.rf), chT = channelBelow(p.rt)
                    points = [CGPoint(x: sf.midX, y: sf.minY),
                              CGPoint(x: sf.midX, y: chS),
                              CGPoint(x: lx, y: chS),
                              CGPoint(x: lx, y: chT),
                              CGPoint(x: tf.midX, y: chT),
                              CGPoint(x: tf.midX, y: tf.maxY)]
                    labelPoint = CGPoint(x: (lx + tf.midX) / 2, y: chT)
                }
            }
            routes.append(Route(points: points, label: p.label, labelPoint: labelPoint))
        }

        // Spread labels that land in the same channel band vertically, so a
        // dense fan-in/out doesn't stack them on top of one another. The band
        // (vGap tall) has room to fan a few labels without touching a box.
        var bands: [Int: [Int]] = [:]
        for (i, r) in routes.enumerated() where r.label != nil {
            bands[Int(r.labelPoint.y.rounded()), default: []].append(i)
        }
        for (_, idxs) in bands where idxs.count > 1 {
            let ordered = idxs.sorted { routes[$0].labelPoint.x < routes[$1].labelPoint.x }
            let baseY = routes[ordered[0]].labelPoint.y
            let step: CGFloat = 15
            // Keep the whole stack inside the channel (± ~half a gap off boxes).
            let limit = vGap / 2 - 8
            let span = min(CGFloat(ordered.count - 1) * step, 2 * limit)
            let actualStep = ordered.count > 1 ? span / CGFloat(ordered.count - 1) : 0
            for (k, idx) in ordered.enumerated() {
                routes[idx].labelPoint.y = baseY - span / 2 + CGFloat(k) * actualStep
            }
        }

        let edges: [C4Layout.Edge] = routes.map {
            C4Layout.Edge(points: $0.points, label: $0.label, labelPoint: $0.labelPoint)
        }

        let width = min(max(finalWidth, 1), 3999)
        let height = min(max(canvasHeight, 1), 3999)
        return C4Layout(size: CGSize(width: width, height: height),
                        title: diagram.title, boxes: boxes, edges: edges)
    }
}
