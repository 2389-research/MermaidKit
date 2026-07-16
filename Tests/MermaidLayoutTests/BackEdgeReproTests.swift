import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Issue #1 — a flowchart cycle back-edge must route to a real, attached path.
///
/// The reporter proposed "every edge's polyline endpoints must coincide with
/// its node anchors" as a *linter* invariant. Empirically it doesn't
/// generalize: sequence arrows land on lifelines, ishikawa bones on the spine,
/// gitgraph/wardley/treeview edges on non-node geometry — so a scene-level
/// check flags clean fixtures. It IS a valid invariant for the node-graph
/// families (flowchart/state), where every edge connects two boxes, so it is
/// pinned here as a scoped test rather than a global linter rule.
final class BackEdgeReproTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    /// Distance from `p` to the nearest point of rect `r` (0 inside/on border).
    private func exteriorDistance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    /// The reported repro (with `B` kept a diamond, the mermaid-faithful bare
    /// back-reference): every edge — including the `D -->|who| B` back-edge —
    /// must have both polyline endpoints land on a node border AND be a real,
    /// non-degenerate path.
    func testBackEdgeEndpointsAttachToNodes() throws {
        try assertEveryEdgeAttaches("""
        flowchart LR
            A[Start] --> B{Decision}
            B -->|yes| C[Ship it]
            B -->|nah| D[Bite It]
            D -->|who| B
        """)
    }

    /// The literal reported repro, with the `B[Figga]` re-declaration that
    /// turns `B` into a rectangle: the back-edge must still route cleanly and
    /// its `who` label must sit on the path, not float near `B`.
    func testBackEdgeWithRedeclarationRoutesAndLabels() throws {
        let src = """
        flowchart LR
            A[Start] --> B{Decision}
            B -->|yes| C[Ship it]
            B -->|nah| D[Bite It]
            D -->|who| B[Figga]
        """
        try assertEveryEdgeAttaches(src)
        guard case .flowchart(let chart) = MermaidParser.parse(src) else { return XCTFail() }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        guard let back = layout.edges.first(where: { $0.label == "who" }) else {
            return XCTFail("back-edge lost")
        }
        // A real path, not a collapsed stub, and the label sits on it.
        XCTAssertGreaterThanOrEqual(back.points.count, 2)
        let extent = back.points.dropFirst().reduce(CGFloat(0)) {
            max($0, hypot($1.x - back.points[0].x, $1.y - back.points[0].y))
        }
        XCTAssertGreaterThan(extent, 20, "back-edge collapsed")
        let lp = try XCTUnwrap(back.labelPoint, "back-edge label has no anchor")
        let onPath = zip(back.points, back.points.dropFirst()).contains { a, b in
            distanceToSegment(lp, a, b) <= 14
        }
        XCTAssertTrue(onPath, "label \(lp) does not sit on the back-edge path")
    }

    /// A two-node tight cycle: the back-edge is the whole reverse connection.
    func testTightCycleBackEdgeAttaches() throws {
        try assertEveryEdgeAttaches("""
        flowchart TD
            A[One] --> B[Two]
            B --> A
        """)
        try assertEveryEdgeAttaches("""
        flowchart LR
            A[One] --> B[Two]
            B --> A
        """)
    }

    /// Longer and mid-graph cycles: the back-edge spans multiple ranks (dummy
    /// channels) — still a real, attached, non-degenerate polyline.
    func testMultiRankCyclesAttach() throws {
        try assertEveryEdgeAttaches("flowchart LR\n A-->B\n B-->C\n C-->D\n D-->A")
        try assertEveryEdgeAttaches("flowchart TD\n A-->B\n B-->C\n C-->D\n D-->A")
        try assertEveryEdgeAttaches("flowchart LR\n A-->B\n B-->C\n C-->A\n C-->D")
    }

    /// The scoped linter rule must pass the repro clean (no
    /// `edge-endpoint-detached`) — this is the automatic guard for the class.
    func testReproPassesLinter() throws {
        let src = """
        flowchart LR
            A[Start] --> B{Decision}
            B -->|yes| C[Ship it]
            B -->|nah| D[Bite It]
            D -->|who| B[Figga]
        """
        guard case .flowchart(let chart) = MermaidParser.parse(src) else { return XCTFail() }
        let scene = DiagramScene.lower(.flowchart(chart), measure: measure)
        let detached = DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-endpoint-detached" }
        XCTAssertTrue(detached.isEmpty, "unexpected: \(detached.map(\.detail))")
    }

    /// The linter rule actually fires on a synthetic detached / degenerate edge
    /// (so the guard can't silently rot into a no-op).
    func testLinterCatchesDetachedAndDegenerate() {
        let a = DiagramScene.Node(id: "A", frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        let b = DiagramScene.Node(id: "B", frame: CGRect(x: 0, y: 100, width: 40, height: 20))
        // Dangling: end floats in empty space far from any node.
        let dangling = DiagramScene(
            name: "flowchart", size: CGSize(width: 400, height: 400),
            nodes: [a, b],
            edges: [DiagramScene.Edge(polyline: [CGPoint(x: 20, y: 20), CGPoint(x: 300, y: 300)], label: nil)])
        XCTAssertTrue(DiagramLayoutLinter.lint(dangling).contains { $0.kind == "edge-endpoint-detached" })
        // Degenerate: a zero-length stub at the origin (the old fallback).
        let degenerate = DiagramScene(
            name: "flowchart", size: CGSize(width: 400, height: 400),
            nodes: [a, b],
            edges: [DiagramScene.Edge(polyline: [.zero, .zero], label: nil)])
        XCTAssertTrue(DiagramLayoutLinter.lint(degenerate).contains { $0.kind == "edge-endpoint-detached" })
    }

    /// Distance from `p` to segment a→b.
    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-9 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(max(t, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func assertEveryEdgeAttaches(_ src: String) throws {
        guard case .flowchart(let chart) = MermaidParser.parse(src) else { return XCTFail() }
        let scene = DiagramScene.lower(.flowchart(chart), measure: measure)
        let boxes = scene.nodes.filter { !$0.isContainer }
        XCTAssertFalse(scene.edges.isEmpty, "no edges laid out")
        for (i, edge) in scene.edges.enumerated() {
            guard let first = edge.polyline.first, let last = edge.polyline.last else {
                return XCTFail("edge #\(i) has no polyline")
            }
            // Non-degenerate: the polyline must have real extent, never a
            // collapsed dot / origin stub.
            let extent = edge.polyline.dropFirst().reduce(CGFloat(0)) {
                max($0, hypot($1.x - first.x, $1.y - first.y))
            }
            XCTAssertGreaterThan(extent, 1, "edge #\(i) is a degenerate stub")
            for (which, p) in [("start", first), ("end", last)] {
                let onABox = boxes.contains { exteriorDistance(p, $0.frame) <= 6 }
                XCTAssertTrue(onABox,
                    "edge #\(i) \(which) (\(Int(p.x)),\(Int(p.y))) reaches no node — dangling")
            }
        }
        // The scoped linter must agree: no detached endpoints on this scene.
        let detached = DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-endpoint-detached" }
        XCTAssertTrue(detached.isEmpty, "linter flagged: \(detached.map(\.detail))")
    }
}
