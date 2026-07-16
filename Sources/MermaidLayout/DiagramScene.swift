import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A platform-free, LLM/computer-readable description of what a laid-out
/// diagram *is* — its boxes, its edge routes, and its free-standing labels —
/// independent of how it's painted. Every diagram type lowers to a
/// `DiagramScene`; the `DiagramLayoutLinter` then reasons over the geometry to
/// find layout problems (edges behind nodes, overlaps, clipping) exactly,
/// where staring at a rendered PNG is unreliable.
public struct DiagramScene: Sendable, Codable {
    /// One laid-out box — a node, head, bar, card, dot, or container band.
    public struct Node: Sendable, Codable {
        /// Stable identifier used in lint reports: the node's label text, or a
        /// synthesized fallback when there is none.
        public let id: String
        /// The box's frame in canvas coordinates.
        public let frame: CGRect
        /// A group / subgraph / composite container legitimately *contains*
        /// other nodes, so it is exempt from overlap and occlusion checks.
        public let isContainer: Bool
        /// Creates a node; `isContainer` defaults to false (a plain checked box).
        public init(id: String, frame: CGRect, isContainer: Bool = false) {
            self.id = id
            self.frame = frame
            self.isContainer = isContainer
        }
    }

    /// One routed connector between nodes.
    public struct Edge: Sendable, Codable {
        /// The routed polyline, endpoint to endpoint.
        public let polyline: [CGPoint]
        /// The edge's caption, if any (its placed chip is lowered separately
        /// as a free-standing `Label`; this copy names the edge in reports).
        public let label: String?
        /// Creates an edge from its route and optional caption.
        public init(polyline: [CGPoint], label: String? = nil) {
            self.polyline = polyline
            self.label = label
        }
    }

    /// A *free-standing* label only — an edge label, axis label, legend entry,
    /// section title. A node's own centred label is implicit in its Node and
    /// must NOT be listed here (it can never "collide" with its own box).
    public struct Label: Sendable, Codable {
        /// The label's text.
        public let text: String
        /// The label's frame in canvas coordinates.
        public let frame: CGRect
        /// Index into `edges` of the edge this label annotates, when it is an
        /// edge label placed ON its own route (a transition label at the
        /// polyline midpoint). That one edge is exempt from the
        /// edge-cuts-label check; every other edge still is not allowed to
        /// slice through the text. Nil for genuinely free-standing labels.
        public let anchorEdge: Int?
        /// True when the renderer paints an opaque canvas chip behind this
        /// label. A foreign edge passing under a backed label is interrupted
        /// by the chip and the text stays readable — so the linter downgrades
        /// the finding from the `edge-cuts-label` ERROR to the
        /// `edge-under-label` WARNING (still sloppy, no longer invisible).
        public let backed: Bool
        /// Creates a label; pass `anchorEdge` when it annotates an edge and
        /// `backed` when it is drawn on an opaque chip.
        public init(text: String, frame: CGRect, anchorEdge: Int? = nil, backed: Bool = false) {
            self.text = text
            self.frame = frame
            self.anchorEdge = anchorEdge
            self.backed = backed
        }
    }

    /// The diagram type ("flowchart", "pie", …); heads lint reports.
    public let name: String
    /// The canvas size; content extending past it is flagged off-canvas.
    public let size: CGSize
    /// All boxes, containers included.
    public let nodes: [Node]
    /// All routed connectors.
    public let edges: [Edge]
    /// All free-standing labels (never a node's own centred label).
    public let labels: [Label]
    /// The front-matter `title:` — a caption hosts may render above the
    /// diagram. Metadata only: no node or label carries it, and the
    /// geometry checks ignore it.
    public let title: String?
    /// The `accTitle:` statement — the diagram's accessible name.
    public let accessibilityTitle: String?
    /// The `accDescr:` statement — the diagram's accessible description.
    public let accessibilityDescription: String?

    /// Creates a scene; `edges`/`labels` default empty for connector-less
    /// types, and the metadata fields default absent.
    public init(name: String, size: CGSize, nodes: [Node],
                edges: [Edge] = [], labels: [Label] = [],
                title: String? = nil,
                accessibilityTitle: String? = nil,
                accessibilityDescription: String? = nil) {
        self.name = name
        self.size = size
        self.nodes = nodes
        self.edges = edges
        self.labels = labels
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// One layout defect found by `DiagramLayoutLinter`.
public struct LayoutViolation: Sendable, Equatable {
    /// `error` = unambiguous geometric defect; `warning` = quality smell.
    public enum Severity: String, Sendable { case error, warning }
    /// How bad it is (see `Severity`).
    public let severity: Severity
    /// Machine-readable check name, e.g. "edge-occludes-node".
    public let kind: String
    /// Human-readable specifics: which nodes/edges/labels, and by how much.
    public let detail: String
    /// Creates a violation.
    public init(_ severity: Severity, _ kind: String, _ detail: String) {
        self.severity = severity
        self.kind = kind
        self.detail = detail
    }
}

/// Checks a `DiagramScene` against invariants of good layout. Errors are
/// unambiguous geometric defects (a line through a box, overlapping boxes,
/// clipped content); warnings are quality smells (colliding labels, crossings,
/// cramped spacing).
extension DiagramScene {
    /// Real text metrics for scene label frames — the injected measurer at
    /// the ~10.5pt label size the renderers use. Replaces the old
    /// `count x 6` estimate, whose error let margin-of-error collisions
    /// slip past every label check.
    static func measuredLabelSize(_ measure: DiagramTextMeasurer, _ text: String) -> CGSize {
        measure(text, 10.5)
    }
}

public enum DiagramLayoutLinter {

    /// Runs every check and returns the deduplicated violations, in check order.
    ///
    /// Errors:
    /// - `edge-occludes-node`: a wire's length inside a non-container box's
    ///   interior (inset 3pt, so border touches don't count) exceeds half the
    ///   box's short side, with an 18pt floor so wires meeting tiny nodes
    ///   (git-commit dots) at centre aren't flagged.
    /// - `edge-endpoint-detached`: in a node-graph scene (flowchart/state) an
    ///   edge's start or end floats off every node border, or the polyline
    ///   collapsed to a degenerate zero-length stub. Scoped by scene name —
    ///   other families' edges attach to lifelines/spines/plot geometry.
    /// - `edges-doubled` (flowchart/state): two distinct edges share a collinear
    ///   orthogonal run overlapping by more than a stub, so they draw as one
    ///   doubled connector (e.g. two back edges adopting the same gutter).
    /// - `nodes-overlap`: two non-container boxes intersect by more than 2pt
    ///   in both axes; full containment is excluded.
    /// - `off-canvas`: a node or label extends outside the canvas (±1pt).
    /// - `mark-escapes-plot`: when the largest container covers >35% of the
    ///   canvas (a chart plot), an edge vertex lies more than 2pt outside it.
    /// - `edge-cuts-label`: an edge travels >6pt inside a BARE label's text
    ///   frame. A label's own `anchorEdge` is exempt (edge labels sit on
    ///   their route by design). `backed` labels downgrade to the
    ///   `edge-under-label` WARNING instead — the chip keeps text readable,
    ///   but a line vanishing under a chip is still placement worth fixing.
    /// - `label-on-fixture` (flowchart/state only): an edge-label frame lands ON
    ///   a fixture — an interior bend of any edge, a crossing/junction of two
    ///   edges, another edge-label frame, a node box, or within the clearance of
    ///   a foreign edge's arrowhead tip. A caption belongs on a clean straight
    ///   stretch with room around it, not a corner, an intersection, or crammed
    ///   against an arrowhead.
    /// - `label-crowds-edge` (flowchart/state only): the straight run an edge
    ///   label sits on is barely longer than the text, leaving under `minStub`
    ///   (10pt) of visible connector on a side — the line all but vanishes.
    ///
    /// Warnings:
    /// - `labels-overlap`: two labels share more than 4pt² of area.
    /// - `label-over-node`: a label covers a non-container box by more than
    ///   half the label's own area.
    /// - `edge-crossings`: pairwise crossings exceed max(2, edges/3).
    ///
    /// `isContainer` nodes are exempt from occlusion and overlap (they
    /// legitimately hold other nodes) but still bound the plot for check 5.
    public static func lint(_ scene: DiagramScene) -> [LayoutViolation] {
        var out: [LayoutViolation] = []
        let occlusionInset: CGFloat = 3
        let overlapTolerance: CGFloat = 2

        // 1. Edge–node occlusion, measured by how far a wire travels INSIDE a
        //    box, not by mere intersection. This matters because an edge
        //    legitimately touches its own endpoint box at the border — but a
        //    route that enters a box and runs across its interior (even its own
        //    endpoint box: a wire anchored on the wrong side that crosses the
        //    box to escape) is a real defect. Exempting endpoints wholesale (as
        //    the old check did) is exactly the blind spot that let an edge run
        //    straight through the "Web Application Firewall" box unflagged. So:
        //    sum the edge's length inside each box's interior and flag when it
        //    exceeds a fraction of the box — a border touch is ~0, a crossing is
        //    most of the width. Containers (groups/plots) are exempt.
        for (ei, edge) in scene.edges.enumerated() {
            let segs = Array(zip(edge.polyline, edge.polyline.dropFirst()))
            for node in scene.nodes where !node.isContainer {
                let inner = node.frame.insetBy(dx: occlusionInset, dy: occlusionInset)
                guard inner.width > 0, inner.height > 0 else { continue }
                let insideLength = segs.reduce(CGFloat(0)) { $0 + segmentInsideLength($1.0, $1.1, inner) }
                // Flag a real traversal, not a connection stub: over half the
                // box's short side AND at least an absolute floor, so a wire
                // meeting a small node (a git-commit dot) at its centre isn't
                // mistaken for a crossing.
                if insideLength > max(0.5 * min(inner.width, inner.height), 18) {
                    out.append(.init(.error, "edge-occludes-node",
                        "edge #\(ei)\(edge.label.map { " (\"\($0)\")" } ?? "") passes through node \"\(node.id)\" (\(Int(insideLength))pt inside)"))
                }
            }
        }

        // 1b. Edge endpoints must attach to a node (node-graph families only).
        //     In flowchart/state every edge connects two boxes, so a polyline
        //     whose first/last point floats off every node border — or which
        //     collapsed to a zero-length/degenerate stub — is a real defect: the
        //     reported cycle back-edge that rendered as a dangling wire / stray
        //     line (issue #1). Scoped by scene name because other families'
        //     edges legitimately land on non-node geometry (sequence arrows on
        //     lifelines, ishikawa bones on the spine, gitgraph/wardley/treeview
        //     on plot geometry), where this check would false-positive.
        if scene.name == "flowchart" || scene.name == "state" {
            // Both plain nodes AND container borders count as attachment: an
            // edge legitimately terminates on a subgraph / composite-state box
            // (the layout resolves such endpoints to the group's border).
            let attachBoxes = scene.nodes
            for (ei, edge) in scene.edges.enumerated() {
                guard let first = edge.polyline.first, let last = edge.polyline.last else {
                    out.append(.init(.error, "edge-endpoint-detached",
                        "edge #\(ei)\(edge.label.map { " (\"\($0)\")" } ?? "") has no polyline"))
                    continue
                }
                // Degenerate: a collapsed route (coincident/near-zero extent)
                // draws as a dot or a spurious stub, never a real connector.
                let extent = edge.polyline.dropFirst().reduce(CGFloat(0)) { acc, p in
                    max(acc, hypot(p.x - first.x, p.y - first.y))
                }
                if extent < 1 {
                    out.append(.init(.error, "edge-endpoint-detached",
                        "edge #\(ei)\(edge.label.map { " (\"\($0)\")" } ?? "") is degenerate (zero-length stub)"))
                    continue
                }
                for (which, p) in [("start", first), ("end", last)]
                where !attachBoxes.contains(where: { $0.frame.insetBy(dx: -6, dy: -6).contains(p) }) {
                    out.append(.init(.error, "edge-endpoint-detached",
                        "edge #\(ei)\(edge.label.map { " (\"\($0)\")" } ?? "") \(which) detached from every node"))
                }
            }
        }

        // 1c. Doubled connectors (flowchart/state only). Two DISTINCT edges
        //     whose orthogonal segments are collinear (same fixed coordinate)
        //     and overlap along that line by more than a stub render as a single
        //     doubled wire — the reader can't tell two edges apart. This is the
        //     degenerate geometry the back-edge gutter reroute must never emit
        //     (two back edges adopting the same gutter channel); the router
        //     rejects it, and this rule is the ratchet that fails the build if a
        //     future change lets one slip through. Scoped to flowchart/state, the
        //     only families with orthogonal routed connectors.
        if scene.name == "flowchart" || scene.name == "state" {
            let doubleTol: CGFloat = 8      // overlap beyond this reads as doubled
            func overlapRun(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat {
                if abs(a.y - b.y) < 0.5, abs(c.y - d.y) < 0.5, abs(a.y - c.y) < 1 {   // horizontal, same y
                    return min(max(a.x, b.x), max(c.x, d.x)) - max(min(a.x, b.x), min(c.x, d.x))
                }
                if abs(a.x - b.x) < 0.5, abs(c.x - d.x) < 0.5, abs(a.x - c.x) < 1 {   // vertical, same x
                    return min(max(a.y, b.y), max(c.y, d.y)) - max(min(a.y, b.y), min(c.y, d.y))
                }
                return 0
            }
            for i in scene.edges.indices where scene.edges[i].polyline.count >= 2 {
                for j in scene.edges.indices where j > i && scene.edges[j].polyline.count >= 2 {
                    let pi = scene.edges[i].polyline, pj = scene.edges[j].polyline
                    var doubled = false
                    for a in 0..<(pi.count - 1) where !doubled {
                        for b in 0..<(pj.count - 1)
                        where overlapRun(pi[a], pi[a + 1], pj[b], pj[b + 1]) > doubleTol {
                            doubled = true; break
                        }
                    }
                    if doubled {
                        out.append(.init(.error, "edges-doubled",
                            "edges #\(i) and #\(j) run doubled on a shared line (overlapping connectors)"))
                    }
                }
            }
        }

        // 2. Node–node overlap (excluding intentional containment).
        let boxes = scene.nodes.filter { !$0.isContainer }
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                let a = boxes[i].frame, b = boxes[j].frame
                let ov = a.intersection(b)
                if !ov.isNull, ov.width > overlapTolerance, ov.height > overlapTolerance,
                   !a.contains(b), !b.contains(a) {
                    out.append(.init(.error, "nodes-overlap",
                        "\"\(boxes[i].id)\" and \"\(boxes[j].id)\" overlap by \(Int(ov.width))×\(Int(ov.height))pt"))
                }
            }
        }

        // 3. Off-canvas content.
        let canvas = CGRect(origin: .zero, size: scene.size).insetBy(dx: -1, dy: -1)
        for node in scene.nodes where !canvas.contains(node.frame) {
            out.append(.init(.error, "off-canvas", "node \"\(node.id)\" extends outside the canvas"))
        }
        for label in scene.labels where !canvas.contains(label.frame) {
            out.append(.init(.error, "off-canvas", "label \"\(label.text)\" extends outside the canvas"))
        }

        // 4. Label collisions (warnings): label vs label, and label vs a node.
        for i in scene.labels.indices {
            for j in scene.labels.indices where j > i {
                if overlapArea(scene.labels[i].frame, scene.labels[j].frame) > 4 {
                    out.append(.init(.warning, "labels-overlap",
                        "labels \"\(scene.labels[i].text)\" and \"\(scene.labels[j].text)\" overlap"))
                }
            }
            for node in boxes {
                let a = scene.labels[i].frame
                if overlapArea(a, node.frame) > 0.5 * a.width * a.height {
                    out.append(.init(.warning, "label-over-node",
                        "label \"\(scene.labels[i].text)\" sits on node \"\(node.id)\""))
                }
            }
        }

        // 4b. An edge slicing through label text (error). Free-standing text
        //     a line runs through is unreadable — this is the class of defect
        //     a human catches instantly ("the branch line goes through 'label
        //     reservation'") that was invisible here until labels learned to
        //     name their own edge: an edge label legitimately sits ON its own
        //     route (`anchorEdge`), so only OTHER edges count against it.
        //     Same inside-length measure as edge-occludes-node, scaled to
        //     label size: flag when a wire travels more than 6pt inside the
        //     slightly-inset text frame.
        for (li, label) in scene.labels.enumerated() {
            let inner = label.frame.insetBy(dx: 2, dy: 2)
            guard inner.width > 0, inner.height > 0 else { continue }
            for (ei, edge) in scene.edges.enumerated() where ei != label.anchorEdge {
                let segs = Array(zip(edge.polyline, edge.polyline.dropFirst()))
                let insideLength = segs.reduce(CGFloat(0)) { $0 + segmentInsideLength($1.0, $1.1, inner) }
                guard insideLength > 6 else { continue }
                if label.backed {
                    // The chip keeps the text readable, so this isn't a hard
                    // failure — but a line disappearing under a chip is still
                    // sloppy placement worth surfacing. (This used to be a
                    // full exemption, which silently blessed a wardley layout
                    // that stamped labels straight onto its links.)
                    out.append(.init(.warning, "edge-under-label",
                        "edge #\(ei) passes under backed label \"\(scene.labels[li].text)\" (\(Int(insideLength))pt)"))
                } else {
                    out.append(.init(.error, "edge-cuts-label",
                        "edge #\(ei) cuts through label \"\(scene.labels[li].text)\" (\(Int(insideLength))pt inside)"))
                }
            }
        }

        // 4c/4d. Edge-label placement quality (flowchart/state only — the gate
        //     below — where every edge label annotates a routed connector between
        //     two boxes; other node-graph families like class/ER don't emit these).
        //     A caption must sit centered on a clean, straight stretch of its
        //     route with a visible connector stub on each side. Two defects,
        //     each an unambiguous geometric fact:
        //
        //     - `label-on-fixture`: the caption frame lands ON a fixture — an
        //       interior bend (a corner) of any edge, a crossing/junction of two
        //       edges, another edge-label frame, or a node box. A label on a
        //       turn or an intersection reads as noise, not a caption.
        //     - `label-crowds-edge`: the straight run the caption sits on is
        //       barely longer than the text, leaving under `minStub` of visible
        //       connector on a side — the line all but vanishes behind the word.
        if scene.name == "flowchart" || scene.name == "state" {
            let minStub: CGFloat = 10
            // A caption must also breathe around an ARROWHEAD — a foreign edge's
            // head end (its last polyline point). A label crammed against an
            // arrowhead reads as noise even when it clears the shaft, so the same
            // comfortable clearance the placer keeps is a hard rule here.
            let arrowClearance: CGFloat = 10
            let edgeLabels = scene.labels.enumerated().filter { $0.element.anchorEdge != nil }

            // Interior bends of every edge (endpoints are node anchors, not
            // fixtures), and the crossing points of every pair of edges.
            var bends: [(edge: Int, p: CGPoint)] = []
            for (ei, edge) in scene.edges.enumerated() where edge.polyline.count > 2 {
                for p in edge.polyline[1..<(edge.polyline.count - 1)] { bends.append((ei, p)) }
            }
            var crossings: [CGPoint] = []
            for i in scene.edges.indices where scene.edges[i].polyline.count >= 2 {
                for j in scene.edges.indices where j > i && scene.edges[j].polyline.count >= 2 {
                    let pi = scene.edges[i].polyline, pj = scene.edges[j].polyline
                    for a in 0..<(pi.count - 1) {
                        for b in 0..<(pj.count - 1) {
                            if let p = segmentCrossPoint(pi[a], pi[a + 1], pj[b], pj[b + 1]) {
                                crossings.append(p)
                            }
                        }
                    }
                }
            }

            for (li, label) in edgeLabels {
                let probe = label.frame.insetBy(dx: -1, dy: -1)
                // On a bend of any edge (a corner).
                for bend in bends where probe.contains(bend.p) {
                    out.append(.init(.error, "label-on-fixture",
                        "label \"\(label.text)\" sits on a bend of edge #\(bend.edge) at (\(Int(bend.p.x)),\(Int(bend.p.y)))"))
                }
                // On a crossing/junction of two edges.
                for x in crossings where probe.contains(x) {
                    out.append(.init(.error, "label-on-fixture",
                        "label \"\(label.text)\" sits on an edge crossing at (\(Int(x.x)),\(Int(x.y)))"))
                }
                // On another edge-label frame.
                for (lj, other) in edgeLabels
                where lj > li && overlapArea(label.frame, other.frame) > 8 {
                    out.append(.init(.error, "label-on-fixture",
                        "labels \"\(label.text)\" and \"\(other.text)\" overlap on their routes"))
                }
                // On a node box (covering a third of the caption or more).
                for node in boxes where overlapArea(label.frame, node.frame.insetBy(dx: 2, dy: 2))
                    > 0.34 * label.frame.width * label.frame.height {
                    out.append(.init(.error, "label-on-fixture",
                        "label \"\(label.text)\" sits on node \"\(node.id)\""))
                }
                // Within the clearance of a FOREIGN arrowhead tip. The label's
                // own route's head is exempt — its stub already reserves the run
                // end — so only other edges' heads count.
                for (ei, edge) in scene.edges.enumerated() where ei != label.anchorEdge {
                    guard let tip = edge.polyline.last else { continue }
                    let dx = max(label.frame.minX - tip.x, 0, tip.x - label.frame.maxX)
                    let dy = max(label.frame.minY - tip.y, 0, tip.y - label.frame.maxY)
                    if hypot(dx, dy) < arrowClearance {
                        out.append(.init(.error, "label-on-fixture",
                            "label \"\(label.text)\" crowds the arrowhead of edge #\(ei) at (\(Int(tip.x)),\(Int(tip.y)))"))
                    }
                }
            }

            // Crowding: measure the stub left on each side of the caption on the
            // ARROW-FREE run it sits on (the nearest segment of its own route,
            // minus the arrowhead the head end eats). Measuring against the full
            // segment let a caption sit `minStub` clear of the segment end yet
            // still hug the arrowhead; excluding the arrowhead length first
            // catches exactly that. Scoped to the flowchart placer, which
            // centers on the arrow-free run (`placeRunLabels` head inset); the
            // state placer still uses the full run, so its measure matches.
            let headEat: CGFloat = scene.name == "flowchart"
                ? DiagramLayoutEngine.flowchartArrowheadLen : 0
            for (_, label) in edgeLabels {
                guard let ae = label.anchorEdge, scene.edges.indices.contains(ae) else { continue }
                let poly = scene.edges[ae].polyline
                guard poly.count >= 2 else { continue }
                let c = CGPoint(x: label.frame.midX, y: label.frame.midY)
                var nearest: (a: CGPoint, b: CGPoint, d: CGFloat)?
                for (a, b) in zip(poly, poly.dropFirst()) {
                    let d = pointSegmentDistance(c, a, b)
                    if nearest == nil || d < nearest!.d { nearest = (a, b, d) }
                }
                guard let seg = nearest else { continue }
                let horiz = abs(seg.a.x - seg.b.x) >= abs(seg.a.y - seg.b.y)
                var lo = horiz ? min(seg.a.x, seg.b.x) : min(seg.a.y, seg.b.y)
                var hi = horiz ? max(seg.a.x, seg.b.x) : max(seg.a.y, seg.b.y)
                // When this is the head segment (ends at the arrowhead tip),
                // shrink that side so the stub is measured against the visible,
                // arrow-free connector.
                if headEat > 0, let head = poly.last,
                   hypot(seg.b.x - head.x, seg.b.y - head.y) < 0.5 {
                    let bAlong = horiz ? seg.b.x : seg.b.y
                    if abs(bAlong - hi) < 0.5 { hi -= headEat } else { lo += headEat }
                }
                let along = horiz ? label.frame.width : label.frame.height
                let cc = horiz ? c.x : c.y
                let stub = min((cc - along / 2) - lo, hi - (cc + along / 2))
                if stub < minStub {
                    out.append(.init(.error, "label-crowds-edge",
                        "label \"\(label.text)\" leaves a \(Int(max(stub, 0)))pt stub (min \(Int(minStub))) on edge #\(ae)"))
                }
            }
        }

        // 5. Marks escaping the plot: when a sole DOMINANT container bounds
        //    the data region (a chart plot covering most of the canvas), no
        //    edge may leave it — catches a line/series running off the chart.
        //    "Dominant" = covering >35% of the canvas: small containers (bar
        //    marks, which are containers only to opt out of occlusion) don't
        //    count, and multiple dominant containers are lanes/composites
        //    that edges legitimately cross, so the check skips those.
        let boxes5 = scene.nodes.filter { !$0.isContainer }
        let dominantContainers = scene.nodes.filter { container in
            guard container.isContainer,
                  container.frame.width * container.frame.height
                    > 0.35 * scene.size.width * scene.size.height else { return false }
            // A PLOT holds all the data marks. Groupings that edges cross by
            // design — sequence box bands, swimlane lanes — are dominant too,
            // but they never contain every non-container node.
            let bounds = container.frame.insetBy(dx: -2, dy: -2)
            return boxes5.allSatisfy { bounds.contains($0.frame) }
        }
        if dominantContainers.count == 1, let plot = dominantContainers.first {
            let bounds = plot.frame.insetBy(dx: -2, dy: -2)
            for (ei, edge) in scene.edges.enumerated() where edge.polyline.contains(where: { !bounds.contains($0) }) {
                out.append(.init(.error, "mark-escapes-plot", "edge #\(ei) runs outside the plot area"))
            }
        }

        // 6. Edge crossings (warning) beyond a modest budget.
        var crossings = 0
        for i in scene.edges.indices {
            for j in scene.edges.indices where j > i {
                if edgesCross(scene.edges[i], scene.edges[j]) { crossings += 1 }
            }
        }
        let budget = max(2, scene.edges.count / 3)
        if crossings > budget {
            out.append(.init(.warning, "edge-crossings", "\(crossings) edge crossings (budget \(budget))"))
        }

        // Dedup while preserving order.
        var seen = Set<String>()
        return out.filter { seen.insert($0.severity.rawValue + $0.kind + $0.detail).inserted }
    }

    /// A one-line-per-violation report, or a clean bill.
    public static func report(_ scene: DiagramScene) -> String {
        let v = lint(scene)
        let header = "\(scene.name): \(scene.nodes.count) nodes, \(scene.edges.count) edges, \(scene.labels.count) labels"
        guard !v.isEmpty else { return "\(header)\n  ✓ clean" }
        let errors = v.filter { $0.severity == .error }.count
        let warns = v.filter { $0.severity == .warning }.count
        let lines = v.map { "  \($0.severity == .error ? "✗" : "⚠") [\($0.kind)] \($0.detail)" }
        return "\(header)  (\(errors) errors, \(warns) warnings)\n" + lines.joined(separator: "\n")
    }

    // MARK: - Geometry

    /// True when either end of the edge lands within `margin` of the node's frame.
    static func isEndpoint(_ node: DiagramScene.Node, of edge: DiagramScene.Edge, margin: CGFloat = 6) -> Bool {
        guard let first = edge.polyline.first, let last = edge.polyline.last else { return false }
        let padded = node.frame.insetBy(dx: -margin, dy: -margin)
        return padded.contains(first) || padded.contains(last)
    }

    /// True when segments a–b and c–d properly cross (shared endpoints and
    /// collinear touches don't count).
    static func segmentsCross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func cross(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
        }
        let o1 = cross(a, b, c), o2 = cross(a, b, d), o3 = cross(c, d, a), o4 = cross(c, d, b)
        // Strictly opposite orientations on BOTH segments: any zero means an
        // endpoint touches the other segment (a T-junction — tree guide
        // stubs meeting their spine), which is a join, not a crossing.
        return o1 * o2 < 0 && o3 * o4 < 0
    }

    /// Length of the portion of segment a→b lying inside rect `r`
    /// (Liang–Barsky clip). 0 when the segment misses the rect. A segment
    /// lying exactly along a border counts at full length — callers wanting
    /// interior-only penetration must inset the rect first (the linter insets
    /// by its occlusion tolerance before measuring).
    static func segmentInsideLength(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        var t0: CGFloat = 0, t1: CGFloat = 1
        let clip: [(CGFloat, CGFloat)] = [
            (-dx, a.x - r.minX), (dx, r.maxX - a.x),
            (-dy, a.y - r.minY), (dy, r.maxY - a.y),
        ]
        for (p, q) in clip {
            if p == 0 {
                if q < 0 { return 0 }               // parallel and outside
            } else {
                let t = q / p
                if p < 0 { if t > t1 { return 0 }; if t > t0 { t0 = t } }
                else { if t < t0 { return 0 }; if t < t1 { t1 = t } }
            }
        }
        return max(0, t1 - t0) * hypot(dx, dy)
    }

    /// True when segment a→b has an endpoint inside rect `r` or crosses one
    /// of its sides.
    static func segmentIntersectsRect(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> Bool {
        if r.contains(a) || r.contains(b) { return true }
        let tl = CGPoint(x: r.minX, y: r.minY), tr = CGPoint(x: r.maxX, y: r.minY)
        let bl = CGPoint(x: r.minX, y: r.maxY), br = CGPoint(x: r.maxX, y: r.maxY)
        return segmentsCross(a, b, tl, tr) || segmentsCross(a, b, tr, br)
            || segmentsCross(a, b, br, bl) || segmentsCross(a, b, bl, tl)
    }

    /// The intersection point of segments a–b and c–d when they properly cross
    /// (strictly interior to both); nil for parallel, collinear, or endpoint
    /// touches (a T-junction is a join, not a crossing).
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

    /// Distance from point `p` to segment a→b (0 when p lies on it).
    static func pointSegmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-9 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(max(t, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Intersection area of two rects; 0 when disjoint.
    static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ov = a.intersection(b)
        return ov.isNull ? 0 : ov.width * ov.height
    }

    /// True when any segment of e1 properly crosses any segment of e2.
    static func edgesCross(_ e1: DiagramScene.Edge, _ e2: DiagramScene.Edge) -> Bool {
        for s1 in zip(e1.polyline, e1.polyline.dropFirst()) {
            for s2 in zip(e2.polyline, e2.polyline.dropFirst()) {
                if segmentsCross(s1.0, s1.1, s2.0, s2.1) { return true }
            }
        }
        return false
    }
}
