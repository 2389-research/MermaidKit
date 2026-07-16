import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Edge-label layout quality — placement on a clean straight run with a
/// visible connector stub on each side, and the two linter rules that reject
/// the failures (`label-on-fixture`, `label-crowds-edge`).
///
/// The two repro fixtures below come from real renders: a caption landing on a
/// bend/junction and overlapping siblings (the back-edge chart), and a long
/// caption on a short edge that swallows the connector (the short-edge chart).
/// The OLD placement tripped the new rules — reconstructed here as bad scenes —
/// and the FIXED layout is lint-clean.
final class EdgeLabelLayoutTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    private let backEdgeSource = """
    flowchart TD
        Draft --> Test
        Test --> Decide{Tests pass?}
        Decide -->|success| Approve
        Decide -->|fail| Draft
        Approve -->|approve| Ship
        Approve -->|reject| Draft
    """

    private let shortEdgeSource = """
    flowchart LR
        Source[Source] -->|records| Valid{Valid?}
        Valid -->|yes| Warehouse
        Valid -->|no| DeadLetter[Dead-letter]
    """

    // MARK: - Fixed layout is clean

    /// Both repro charts lay out with no `label-on-fixture` / `label-crowds-edge`
    /// (and no other) errors after the fix.
    func testReproFixturesAreLintClean() throws {
        for src in [backEdgeSource, shortEdgeSource] {
            guard let diagram = MermaidParser.parse(src) else { return XCTFail("parse") }
            let scene = DiagramScene.lower(diagram, measure: measure)
            let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty,
                "expected clean, got:\n" + errors.map { "  \($0.kind): \($0.detail)" }.joined(separator: "\n"))
        }
    }

    /// Every placed caption sits ON a straight axis-aligned run of its route,
    /// centered, with at least the reserved stub of connector on each side —
    /// the guarantee the placement makes, checked over the real layout.
    func testFixedLabelsSitOnStraightRunsWithStubs() throws {
        for src in [backEdgeSource, shortEdgeSource] {
            guard case .flowchart(let chart) = MermaidParser.parse(src) else { return XCTFail("parse") }
            let layout = DiagramLayoutEngine.layout(chart, measure: measure)
            for edge in layout.edges {
                guard let label = edge.label, !label.isEmpty else { continue }
                let lp = try XCTUnwrap(edge.labelPoint, "\(label): missing label anchor")
                let sz = measure(label, DiagramLayoutEngine.labelFontSize)
                // Nearest segment (the run the caption sits on).
                var run: (a: CGPoint, b: CGPoint, d: CGFloat)?
                for (a, b) in zip(edge.points, edge.points.dropFirst()) {
                    let d = distanceToSegment(lp, a, b)
                    if run == nil || d < run!.d { run = (a, b, d) }
                }
                let seg = try XCTUnwrap(run, "\(label): no run")
                // On the run: the anchor is within a couple points of the line.
                XCTAssertLessThanOrEqual(seg.d, 3, "label \"\(label)\" floats off its route")
                let horiz = abs(seg.a.x - seg.b.x) >= abs(seg.a.y - seg.b.y)
                // Axis-aligned run (orthogonal routing).
                let offAxis = horiz ? abs(seg.a.y - seg.b.y) : abs(seg.a.x - seg.b.x)
                XCTAssertLessThanOrEqual(offAxis, 0.5, "label \"\(label)\" run isn't axis-aligned")
                let lo = horiz ? min(seg.a.x, seg.b.x) : min(seg.a.y, seg.b.y)
                let hi = horiz ? max(seg.a.x, seg.b.x) : max(seg.a.y, seg.b.y)
                let along = horiz ? sz.width + 6 : sz.height + 2
                let c = horiz ? lp.x : lp.y
                let stub = min((c - along / 2) - lo, hi - (c + along / 2))
                XCTAssertGreaterThanOrEqual(stub, DiagramLayoutEngine.edgeLabelStub,
                    "label \"\(label)\" leaves only \(Int(stub))pt of connector")
            }
        }
    }

    /// The `records` case (`Source[Source] -->|records| Valid{Valid?}`): the
    /// caption must center on the ARROW-FREE portion of its run — the segment
    /// minus the arrowhead the head end eats — and keep at least the reserved
    /// stub of VISIBLE (arrow-free) connector between the label edge and BOTH
    /// the arrowhead tip and the source node. Before the fix it centered on the
    /// full segment, so the arrowhead ate its head-side clearance and the word
    /// hugged the arrow.
    func testRecordsLabelCentersOnArrowFreeRun() throws {
        guard case .flowchart(let chart) = MermaidParser.parse(shortEdgeSource) else { return XCTFail("parse") }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let e = try XCTUnwrap(layout.edges.first { $0.label == "records" })
        XCTAssertTrue(e.hasArrow, "records edge should carry an arrowhead")
        let lp = try XCTUnwrap(e.labelPoint, "records: missing label anchor")
        let sz = measure("records", DiagramLayoutEngine.labelFontSize)
        let along = sz.width + 6

        // The run the caption sits on (nearest segment of its own route).
        var run: (a: CGPoint, b: CGPoint, d: CGFloat)?
        for (a, b) in zip(e.points, e.points.dropFirst()) {
            let d = distanceToSegment(lp, a, b)
            if run == nil || d < run!.d { run = (a, b, d) }
        }
        let seg = try XCTUnwrap(run)
        XCTAssertLessThanOrEqual(seg.d, 3, "records floats off its route")
        let horiz = abs(seg.a.x - seg.b.x) >= abs(seg.a.y - seg.b.y)
        XCTAssertLessThanOrEqual(horiz ? abs(seg.a.y - seg.b.y) : abs(seg.a.x - seg.b.x), 0.5,
                                 "records run isn't axis-aligned")
        let lo = horiz ? min(seg.a.x, seg.b.x) : min(seg.a.y, seg.b.y)
        let hi = horiz ? max(seg.a.x, seg.b.x) : max(seg.a.y, seg.b.y)
        // Head (arrowhead) end of this run; the other end abuts the source node.
        let head = try XCTUnwrap(e.points.last)
        let headAtHi = abs((horiz ? head.x : head.y) - hi) < 0.5
        let ah = DiagramLayoutEngine.flowchartArrowheadLen
        let afLo = headAtHi ? lo : lo + ah        // source-node side / arrow-free lo
        let afHi = headAtHi ? hi - ah : hi        // arrow-free hi
        let center = horiz ? lp.x : lp.y

        // 1. Centered on the arrow-free midpoint.
        XCTAssertEqual(center, (afLo + afHi) / 2, accuracy: 1.0,
                       "records isn't centered on the arrow-free midpoint")
        // 2. A real arrow-free stub on EACH side: between the label edge and the
        //    arrowhead, and between the label edge and the source node.
        let arrowSideStub = headAtHi ? afHi - (center + along / 2) : (center - along / 2) - afLo
        let nodeSideStub  = headAtHi ? (center - along / 2) - afLo : afHi - (center + along / 2)
        XCTAssertGreaterThanOrEqual(arrowSideStub, DiagramLayoutEngine.edgeLabelStub,
            "records leaves only \(Int(arrowSideStub))pt of visible line before the arrowhead")
        XCTAssertGreaterThanOrEqual(nodeSideStub, DiagramLayoutEngine.edgeLabelStub,
            "records leaves only \(Int(nodeSideStub))pt of visible line before the source node")
    }

    /// A labeled self-loop in the layered (state/class/ER) router must host its
    /// caption without clipping or crowding: the loop is widened to the label
    /// plus a stub on each side, and the canvas grows for the label frame. Before
    /// the fix, `A --> A: retry` placed the word beside a fixed 24pt loop — off
    /// the canvas (no size growth) and then crammed onto too short a run.
    func testLayeredSelfLoopLabelsAreClean() {
        let sources = [
            "stateDiagram-v2\n    A --> A: retry",
            "classDiagram\n    A --> A : self",
            "stateDiagram-v2\n    [*] --> A\n    A --> A: retry\n    A --> B: go",
            "erDiagram\n    CUSTOMER ||--o{ CUSTOMER : refers",
        ]
        for src in sources {
            guard let diagram = MermaidParser.parse(src) else { return XCTFail("parse: \(src)") }
            let scene = DiagramScene.lower(diagram, measure: measure)
            let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty,
                "self-loop \"\(src)\" not clean:\n" + errors.map { "  \($0.kind): \($0.detail)" }.joined(separator: "\n"))
        }
    }

    // MARK: - Linter rejects the OLD (unfixed) geometry

    /// `label-crowds-edge`: the OLD short-edge placement centered "records" on a
    /// 56pt run, leaving ~3pt of connector on each side. Reconstructed as a
    /// scene, it must be flagged (error).
    func testCrowdedLabelIsFlagged() {
        // Old geometry: Source→Valid straight run 83→139 (len 56); "records"
        // (~50pt wide) centered at x=111 → ~3pt stub each side.
        let w = measure("records", DiagramLayoutEngine.labelFontSize).width
        let scene = DiagramScene(
            name: "flowchart", size: CGSize(width: 300, height: 120),
            nodes: [.init(id: "Source", frame: CGRect(x: 12, y: 42, width: 71, height: 34)),
                    .init(id: "Valid", frame: CGRect(x: 139, y: 34, width: 92, height: 51))],
            edges: [.init(polyline: [CGPoint(x: 83, y: 59), CGPoint(x: 139, y: 59)], label: "records")],
            labels: [.init(text: "records",
                           frame: CGRect(x: 111 - w / 2, y: 52, width: w, height: 14),
                           anchorEdge: 0, backed: true)])
        let hits = DiagramLayoutLinter.lint(scene).filter { $0.kind == "label-crowds-edge" }
        XCTAssertEqual(hits.count, 1, "a long caption on a short run must be flagged")
        XCTAssertEqual(hits.first?.severity, .error)
    }

    /// `label-on-fixture`: the OLD back-edge placement dropped "reject" on a
    /// 30pt jog between two bends — the caption frame contains both corners.
    func testLabelOnBendIsFlagged() {
        let route: [CGPoint] = [
            CGPoint(x: 103, y: 299), CGPoint(x: 103, y: 263), CGPoint(x: 216, y: 263),
            CGPoint(x: 216, y: 173), CGPoint(x: 186, y: 173), CGPoint(x: 186, y: 87),
            CGPoint(x: 99, y: 87), CGPoint(x: 99, y: 46),
        ]
        let w = measure("reject", DiagramLayoutEngine.labelFontSize).width
        let scene = DiagramScene(
            name: "flowchart", size: CGSize(width: 260, height: 440),
            nodes: [.init(id: "Approve", frame: CGRect(x: 42, y: 299, width: 78, height: 34)),
                    .init(id: "Draft", frame: CGRect(x: 49, y: 12, width: 64, height: 34))],
            // OLD anchor: the jog midpoint (201,173), between bends (216,173)/(186,173).
            edges: [.init(polyline: route, label: "reject")],
            labels: [.init(text: "reject",
                           frame: CGRect(x: 201 - w / 2, y: 166, width: w, height: 14),
                           anchorEdge: 0, backed: true)])
        let hits = DiagramLayoutLinter.lint(scene).filter { $0.kind == "label-on-fixture" }
        XCTAssertFalse(hits.isEmpty, "a caption sitting on a bend must be flagged")
        XCTAssertEqual(hits.first?.severity, .error)
        XCTAssertTrue(hits.contains { $0.detail.contains("bend") })
    }

    /// `label-on-fixture`: a caption dropped on a crossing of two edges.
    func testLabelOnCrossingIsFlagged() {
        let w = measure("cross", DiagramLayoutEngine.labelFontSize).width
        let scene = DiagramScene(
            name: "state", size: CGSize(width: 200, height: 200),
            nodes: [.init(id: "A", frame: CGRect(x: 10, y: 10, width: 40, height: 20)),
                    .init(id: "B", frame: CGRect(x: 150, y: 170, width: 40, height: 20))],
            edges: [.init(polyline: [CGPoint(x: 20, y: 20), CGPoint(x: 180, y: 180)], label: "cross"),
                    .init(polyline: [CGPoint(x: 180, y: 20), CGPoint(x: 20, y: 180)], label: nil)],
            // Both diagonals cross at (100,100); anchor the caption right there.
            labels: [.init(text: "cross",
                           frame: CGRect(x: 100 - w / 2, y: 93, width: w, height: 14),
                           anchorEdge: 0, backed: true)])
        let hits = DiagramLayoutLinter.lint(scene).filter { $0.kind == "label-on-fixture" }
        XCTAssertTrue(hits.contains { $0.detail.contains("crossing") },
            "a caption on an edge crossing must be flagged")
        XCTAssertEqual(hits.first?.severity, .error)
    }

    /// `label-on-fixture`: a caption crammed against a FOREIGN edge's arrowhead
    /// tip (within the clearance) must be flagged — the rule that guards the
    /// "labels hug the arrowhead" complaint.
    func testLabelCrowdingArrowheadIsFlagged() {
        let w = measure("hug", DiagramLayoutEngine.labelFontSize).width
        // Edge #1's arrowhead lands at (150,100); the caption of edge #0 is
        // parked ~3pt to its left — clearing the shaft but crowding the head.
        let scene = DiagramScene(
            name: "flowchart", size: CGSize(width: 300, height: 200),
            nodes: [.init(id: "A", frame: CGRect(x: 10, y: 40, width: 40, height: 20)),
                    .init(id: "B", frame: CGRect(x: 150, y: 90, width: 40, height: 20))],
            edges: [.init(polyline: [CGPoint(x: 30, y: 60), CGPoint(x: 30, y: 160)], label: "hug"),
                    .init(polyline: [CGPoint(x: 30, y: 30), CGPoint(x: 150, y: 100)], label: nil)],
            labels: [.init(text: "hug",
                           frame: CGRect(x: 146 - w, y: 93, width: w, height: 14),
                           anchorEdge: 0, backed: true)])
        let hits = DiagramLayoutLinter.lint(scene).filter { $0.kind == "label-on-fixture" }
        XCTAssertTrue(hits.contains { $0.detail.contains("arrowhead") },
            "a caption crammed against a foreign arrowhead must be flagged")
    }

    /// `edges-doubled`: two DISTINCT edges sharing a collinear vertical run that
    /// overlaps by more than a stub render as a single doubled connector — the
    /// degenerate geometry the back-edge gutter reroute must never emit. The
    /// linter is the ratchet that catches it if the router ever regresses.
    func testDoubledConnectorsAreFlagged() {
        let scene = DiagramScene(
            name: "flowchart", size: CGSize(width: 200, height: 200),
            nodes: [.init(id: "A", frame: CGRect(x: 60, y: 10, width: 40, height: 20)),
                    .init(id: "B", frame: CGRect(x: 60, y: 170, width: 40, height: 20))],
            // Both edges run up the SAME x=150 channel over an overlapping y-span.
            edges: [.init(polyline: [CGPoint(x: 100, y: 20), CGPoint(x: 150, y: 20),
                                     CGPoint(x: 150, y: 120), CGPoint(x: 100, y: 120)], label: nil),
                    .init(polyline: [CGPoint(x: 100, y: 60), CGPoint(x: 150, y: 60),
                                     CGPoint(x: 150, y: 180), CGPoint(x: 100, y: 180)], label: nil)],
            labels: [])
        let hits = DiagramLayoutLinter.lint(scene).filter { $0.kind == "edges-doubled" }
        XCTAssertEqual(hits.count, 1, "two edges doubled on a shared line must be flagged once")
        XCTAssertEqual(hits.first?.severity, .error)
    }

    // MARK: - Route quality on the real back-edge layout

    /// #3 — the `fail` back edge (`Decide -> Draft`) must have NO needless zag:
    /// a straightened route of at most a single bend on each axis, never the
    /// tiny sideways step the old router left between a diamond vertex and its
    /// dummy channel.
    func testFailEdgeHasNoZag() throws {
        guard case .flowchart(let chart) = MermaidParser.parse(backEdgeSource) else { return XCTFail() }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let fail = try XCTUnwrap(layout.edges.first { $0.label == "fail" })
        // No interior segment is a tiny cross-axis jog (< the zag threshold)
        // sitting between two longer perpendicular runs.
        let p = fail.points
        for k in 1..<(max(p.count - 2, 1)) where k + 2 < p.count {
            let a = p[k - 1], b = p[k], c = p[k + 1], d = p[k + 2]
            let stepX = abs(b.x - c.x), stepY = abs(b.y - c.y)
            // b→c horizontal jog flanked by two vertical runs?
            if stepY < 0.5, stepX > 0.5, stepX <= DiagramLayoutEngine.flowchartMinJog,
               abs(a.x - b.x) < 0.5, abs(c.x - d.x) < 0.5 {
                XCTFail("fail edge has a \(Int(stepX))pt horizontal zag at \(b)")
            }
            if stepX < 0.5, stepY > 0.5, stepY <= DiagramLayoutEngine.flowchartMinJog,
               abs(a.y - b.y) < 0.5, abs(c.y - d.y) < 0.5 {
                XCTFail("fail edge has a \(Int(stepY))pt vertical zag at \(b)")
            }
        }
    }

    /// #2 — the `reject` back edge (`Approve -> Draft`) must exit Approve's EAST
    /// face and return up a side channel clear of the node stack, so its route
    /// never runs under the `success` caption.
    func testRejectExitsEastSideChannel() throws {
        guard case .flowchart(let chart) = MermaidParser.parse(backEdgeSource) else { return XCTFail() }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let reject = try XCTUnwrap(layout.edges.first { $0.label == "reject" })
        let approve = try XCTUnwrap(layout.nodes.first { $0.id == "Approve" })
        // Exits the east (right) face of Approve.
        let start = reject.points[0]
        XCTAssertEqual(start.x, approve.frame.maxX, accuracy: 1.0,
            "reject should leave Approve's east face, not its top")
        // The return run sits in a gutter to the RIGHT of every node.
        let maxNodeX = layout.nodes.map { $0.frame.maxX }.max() ?? 0
        let gutterX = reject.points.map(\.x).max() ?? 0
        XCTAssertGreaterThan(gutterX, maxNodeX - 0.5, "reject return isn't in a side gutter")
        // It does not run under the success caption. Check the route against the
        // full MEASURED, clearance-expanded label frame — not merely its center:
        // the `success` caption is wide, so a route can cut through the word while
        // still staying >12pt from the anchor point.
        let success = try XCTUnwrap(layout.edges.first { $0.label == "success" })
        let sp = try XCTUnwrap(success.labelPoint)
        let ssz = measure("success", DiagramLayoutEngine.labelFontSize)
        let clearance: CGFloat = 6
        let protectedFrame = CGRect(
            x: sp.x - (ssz.width + 6) / 2 - clearance,
            y: sp.y - (ssz.height + 2) / 2 - clearance,
            width: ssz.width + 6 + 2 * clearance,
            height: ssz.height + 2 + 2 * clearance)
        for (a, b) in zip(reject.points, reject.points.dropFirst()) {
            XCTAssertFalse(segmentIntersectsRect(a, b, protectedFrame),
                "reject route cuts through the success label frame")
        }
    }

    /// #4 — the `fail` and `reject` back-edge captions sit on parallel VERTICAL
    /// channels at similar heights. Their x-positions are routing-fixed, so they
    /// can't move apart horizontally; the placer must STAGGER them vertically —
    /// sliding the later/rightmost caption (`reject`) DOWN along its own run —
    /// until they clear the comfort gap. Before the fix both centered on their
    /// arrow-free midpoints ~8pt apart vertically and read as crowded.
    func testFailRejectLabelsStaggerVertically() throws {
        guard case .flowchart(let chart) = MermaidParser.parse(backEdgeSource) else { return XCTFail() }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)

        func frame(_ label: String) throws -> CGRect {
            let e = try XCTUnwrap(layout.edges.first { $0.label == label }, "\(label): missing edge")
            let lp = try XCTUnwrap(e.labelPoint, "\(label): missing anchor")
            let sz = measure(label, DiagramLayoutEngine.labelFontSize)
            return CGRect(x: lp.x - (sz.width + 6) / 2, y: lp.y - (sz.height + 2) / 2,
                          width: sz.width + 6, height: sz.height + 2)
        }
        let fail = try frame("fail")
        let reject = try frame("reject")

        // They crowd horizontally (channel x's overlap or sit within the gap), so
        // the comfort clearance must come from a VERTICAL stagger.
        let dxGap = max(fail.minX - reject.maxX, reject.minX - fail.maxX, 0)
        XCTAssertLessThan(dxGap, DiagramLayoutEngine.flowchartLabelGap,
                          "fail/reject don't crowd horizontally — this fixture no longer exercises the stagger")
        let dyGap = max(fail.minY - reject.maxY, reject.minY - fail.maxY, 0)
        XCTAssertGreaterThanOrEqual(dyGap, DiagramLayoutEngine.flowchartLabelGap,
            "fail/reject captions crowd: only \(Int(dyGap))pt of vertical clearance, need \(Int(DiagramLayoutEngine.flowchartLabelGap))")
        // The stagger pushes the later caption (reject) DOWN, not fail UP.
        XCTAssertGreaterThan(reject.minY, fail.maxY, "reject should sit below fail")

        // reject stays ON its straight run with a full stub each side (round-3
        // guarantee preserved — the stagger doesn't shove it onto a bend).
        let e = try XCTUnwrap(layout.edges.first { $0.label == "reject" })
        let lp = try XCTUnwrap(e.labelPoint)
        var run: (a: CGPoint, b: CGPoint, d: CGFloat)?
        for (a, b) in zip(e.points, e.points.dropFirst()) {
            let d = distanceToSegment(lp, a, b)
            if run == nil || d < run!.d { run = (a, b, d) }
        }
        let seg = try XCTUnwrap(run)
        XCTAssertLessThanOrEqual(seg.d, 3, "reject floated off its route after staggering")
        let horiz = abs(seg.a.x - seg.b.x) >= abs(seg.a.y - seg.b.y)
        let lo = horiz ? min(seg.a.x, seg.b.x) : min(seg.a.y, seg.b.y)
        let hi = horiz ? max(seg.a.x, seg.b.x) : max(seg.a.y, seg.b.y)
        let along = horiz ? reject.width : reject.height
        let c = horiz ? lp.x : lp.y
        let stub = min((c - along / 2) - lo, hi - (c + along / 2))
        XCTAssertGreaterThanOrEqual(stub, DiagramLayoutEngine.edgeLabelStub,
            "reject leaves only \(Int(stub))pt of connector after staggering")
    }

    /// The state fixture (composite states + choice/fork/join + cycles) — whose
    /// adjacent-layer labels used to land on jogs and stack on top of each
    /// other — is now clean of both new rules.
    func testStateFixtureCleanOfLabelRules() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams/state.mmd")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let diagram = MermaidParser.parse(source) else { return XCTFail("parse") }
        let scene = DiagramScene.lower(diagram, measure: measure)
        let bad = DiagramLayoutLinter.lint(scene)
            .filter { $0.kind == "label-on-fixture" || $0.kind == "label-crowds-edge" }
        XCTAssertTrue(bad.isEmpty, "state label defects:\n" + bad.map { "  \($0.detail)" }.joined(separator: "\n"))
    }

    private func segmentIntersectsRect(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> Bool {
        if r.contains(a) || r.contains(b) { return true }
        let c = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                 CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        for i in 0..<4 where segmentsCross(a, b, c[i], c[(i + 1) % 4]) { return true }
        return false
    }

    private func segmentsCross(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func ccw(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let d1 = ccw(p3, p4, p1), d2 = ccw(p3, p4, p2)
        let d3 = ccw(p1, p2, p3), d4 = ccw(p1, p2, p4)
        return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-9 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(max(t, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
