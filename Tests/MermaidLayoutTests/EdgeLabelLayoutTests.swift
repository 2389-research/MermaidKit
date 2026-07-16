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
                guard let label = edge.label, !label.isEmpty, let lp = edge.labelPoint else { continue }
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
                XCTAssertGreaterThanOrEqual(stub, 10,
                    "label \"\(label)\" leaves only \(Int(stub))pt of connector")
            }
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

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-9 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(max(t, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
