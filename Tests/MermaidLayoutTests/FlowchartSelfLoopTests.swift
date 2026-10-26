import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// A flowchart edge from a node back to itself (`T --> T`) must draw as a loop
/// off the node's side, never as a run through the box, and its caption must
/// sit beside the loop rather than on the node. It also must not take a face
/// port from the node's real edges.
final class FlowchartSelfLoopTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    /// A looped node in a cycle, with a long caption and an edge out into a
    /// decision. Before loops had a route of their own, the caption landed on
    /// the node and the `T → D` edge was pushed into a jog.
    private let retrySource = """
    flowchart TD
        A[Receive a request] --> B[Validate the input]
        B --> T[Process the job]
        T -->|Retry until it succeeds| T
        T --> D{Succeeded?}
        D -->|Yes| S[Send the result]
        D -->|No| E[Log the error]
        E --> B
    """

    private struct NotAFlowchart: Error {}

    private func flowchart(_ src: String) throws -> Flowchart {
        guard case .flowchart(let chart)? = MermaidParser.parse(src) else { throw NotAFlowchart() }
        return chart
    }

    private func lintErrors(_ src: String) -> [String] {
        guard let diagram = MermaidParser.parse(src) else { return ["parse failed"] }
        let scene = DiagramScene.lower(diagram, measure: measure)
        return DiagramLayoutLinter.lint(scene)
            .filter { $0.severity == .error }
            .map { "\($0.kind): \($0.detail)" }
    }

    /// Length of the polyline that runs strictly inside `rect` (inset 1pt so a
    /// route attached to the border doesn't count).
    private func lengthInside(_ pts: [CGPoint], _ rect: CGRect) -> CGFloat {
        let r = rect.insetBy(dx: 1, dy: 1)
        var total: CGFloat = 0
        for k in 0..<max(pts.count - 1, 0) {
            let a = pts[k], b = pts[k + 1]
            let steps = 64
            for s in 0..<steps {
                let t0 = CGFloat(s) / CGFloat(steps), t1 = CGFloat(s + 1) / CGFloat(steps)
                let p = CGPoint(x: a.x + (b.x - a.x) * (t0 + t1) / 2, y: a.y + (b.y - a.y) * (t0 + t1) / 2)
                if r.contains(p) { total += hypot(b.x - a.x, b.y - a.y) / CGFloat(steps) }
            }
        }
        return total
    }

    func testRetryChartIsLintClean() {
        let errors = lintErrors(retrySource)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
    }

    func testLoopAndCaptionStayOffTheNode() throws {
        let chart = try flowchart(retrySource)
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let job = try XCTUnwrap(layout.nodes.first { $0.id == "T" }?.frame)
        let loopIndex = try XCTUnwrap(chart.edges.firstIndex { $0.from == "T" && $0.to == "T" })
        let loop = layout.edges[loopIndex]

        XCTAssertLessThan(lengthInside(loop.points, job), 0.5, "loop runs through its node: \(loop.points)")
        XCTAssertGreaterThanOrEqual(loop.points.count, 4, "a loop needs out, across and back legs")
        XCTAssertGreaterThan(loop.points.map(\.x).max() ?? 0, job.maxX, "loop should leave the right face")
        try assertCaptionsBesideFarRun(retrySource)
    }

    /// Every labelled self-loop's caption, boxed the way `placeRunLabels`
    /// boxes it, sits beside its loop's far run: past the node's cross-far
    /// face (right in TD, bottom in LR) and level with the node, never on the
    /// node or on a bar in a layer gap. A loop is found by its ends, both on
    /// its node, since a chart with subgraphs places edges scope by scope.
    private func assertCaptionsBesideFarRun(
        _ src: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let chart = try flowchart(src)
        let horizontal = chart.direction == .leftRight || chart.direction == .rightLeft
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        for edge in chart.edges where edge.from == edge.to && !edge.invisible {
            guard let label = edge.label, !label.isEmpty else { continue }
            let node = try XCTUnwrap(layout.nodes.first { $0.id == edge.from }?.frame, file: file, line: line)
            let touching = node.insetBy(dx: -1, dy: -1)
            let loop = try XCTUnwrap(layout.edges.first {
                $0.label == label && touching.contains($0.start) && touching.contains($0.end)
            }, "\(src): no loop \"\(label)\" on \(edge.from)", file: file, line: line)
            let anchor = try XCTUnwrap(loop.labelPoint, file: file, line: line)
            let size = measure(label, DiagramLayoutEngine.labelFontSize)
            let rect = CGRect(x: anchor.x - (size.width + 6) / 2, y: anchor.y - (size.height + 2) / 2,
                              width: size.width + 6, height: size.height + 2)
            let (beyond, farFace) = horizontal ? (rect.minY, node.maxY) : (rect.minX, node.maxX)
            let (along, lo, hi) = horizontal ? (anchor.x, node.minX, node.maxX) : (anchor.y, node.minY, node.maxY)
            let (outer, canvas) = horizontal ? (rect.maxY, layout.size.height) : (rect.maxX, layout.size.width)
            XCTAssertGreaterThanOrEqual(beyond, farFace - 0.5,
                "\(src): caption \"\(label)\" \(rect) is not past the far face of \(node)", file: file, line: line)
            XCTAssertTrue(along > lo && along < hi,
                "\(src): caption \"\(label)\" at \(anchor) is not beside the far run of \(node)", file: file, line: line)
            XCTAssertLessThanOrEqual(outer, canvas,
                "\(src): caption \"\(label)\" runs off the canvas", file: file, line: line)
        }
    }

    /// The far run carries the caption even where a bar is longer: the outer
    /// of two nested loops, a loop on a wide node, a loop on a decision, in
    /// either direction and inside a subgraph.
    func testCaptionsRideTheFarRun() throws {
        try assertCaptionsBesideFarRun("flowchart TD\n A --> B --> C\n B -->|one| B\n B -->|two| B")
        try assertCaptionsBesideFarRun("flowchart LR\n A --> B --> C\n B -->|one| B\n B -->|two| B")
        try assertCaptionsBesideFarRun("flowchart TD\n A[a node label wide enough to stretch the box] -->|x| A\n A --> B")
        try assertCaptionsBesideFarRun("flowchart LR\n A[a node label wide enough to stretch the box] -->|x| A\n A --> B")
        try assertCaptionsBesideFarRun("flowchart TD\n D{x} -->|a| D\n D -->|b| D")
        try assertCaptionsBesideFarRun("flowchart TD\n subgraph G\n A --> B\n end\n B -->|retry| B")
        try assertCaptionsBesideFarRun("flowchart LR\n subgraph G\n A --> B\n end\n B -->|retry| B")
    }

    /// Where a self-loop and another drawn edge properly cross.
    private func loopCrossings(_ src: String) throws -> [String] {
        let chart = try flowchart(src)
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        func segments(_ pts: [CGPoint]) -> [(CGPoint, CGPoint)] { Array(zip(pts, pts.dropFirst())) }
        func crosses(_ s: (CGPoint, CGPoint), _ t: (CGPoint, CGPoint)) -> Bool {
            let (h, v) = abs(s.0.y - s.1.y) < 0.5 ? (s, t) : (t, s)
            guard abs(h.0.y - h.1.y) < 0.5, abs(v.0.x - v.1.x) < 0.5 else { return false }
            let x = v.0.x, y = h.0.y
            return x > min(h.0.x, h.1.x) + 0.5 && x < max(h.0.x, h.1.x) - 0.5
                && y > min(v.0.y, v.1.y) + 0.5 && y < max(v.0.y, v.1.y) - 0.5
        }
        var found: [String] = []
        for (i, loop) in chart.edges.enumerated() where loop.from == loop.to && !loop.invisible {
            for (j, other) in chart.edges.enumerated() where j != i && !other.invisible {
                for s in segments(layout.edges[i].points) {
                    for t in segments(layout.edges[j].points) where crosses(s, t) {
                        found.append("\(loop.from) loop crosses \(other.from) → \(other.to)")
                    }
                }
            }
        }
        return found
    }

    /// No drawn edge crosses a loop. A decision's branches toward the loop's
    /// side, forward or back, leave the face inside the loop at a slot each,
    /// since the loop wraps the side vertex; a jog biased off a gap's middle
    /// by fan-in, or slid toward a looped target, still clears the bars.
    func testNoEdgeCrossesALoop() throws {
        let sources = [
            "flowchart TD\n D{ok?} -->|retry| D\n D -->|yes| E\n D -->|no| F",
            "flowchart LR\n D{ok?} -->|retry| D\n D -->|yes| E\n D -->|no| F",
            "flowchart TD\n D{x} -->|a| D\n D -->|b| D\n D --> E & F & G",
            "flowchart TD\n D{x} -->|r| D\n D --> E & F & G & H",
            "flowchart TD\n S --> L & P & Q & R\n L -->|again| L\n L & P & Q & R --> T",
            "flowchart TD\n A --> B & C\n B --> D\n C -->|go| D\n D -->|again| D",
        ]
        for src in sources {
            let crossings = try loopCrossings(src)
            XCTAssertTrue(crossings.isEmpty, "\(src):\n" + crossings.joined(separator: "\n"))
        }
    }

    /// Branches leaving a looped decision toward its loops' side each leave
    /// from their own point, so no two run down one line.
    func testDecisionBranchesTowardTheLoopsLeaveApart() throws {
        let chart = try flowchart("flowchart TD\n D{x} -->|r| D\n D --> E & F & G & H")
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let decision = try XCTUnwrap(layout.nodes.first { $0.id == "D" }?.frame)
        let starts = chart.edges.indices
            .filter { chart.edges[$0].from == "D" && chart.edges[$0].to != "D" }
            .map { layout.edges[$0].start }
            .filter { $0.x > decision.midX + 0.5 }
        XCTAssertEqual(starts.count, 2, "expected two branches toward the loop's side, got \(starts)")
        XCTAssertGreaterThan(abs((starts.first?.x ?? 0) - (starts.last?.x ?? 0)), 1,
                             "branches toward the loop's side share a start: \(starts)")
    }

    /// The loop takes no slot on the node's bottom face, so the only real edge
    /// leaving it (`T → D`) stays a straight drop into the decision.
    func testLoopDoesNotDisplaceTheOutgoingEdge() throws {
        let chart = try flowchart(retrySource)
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let index = try XCTUnwrap(chart.edges.firstIndex { $0.from == "T" && $0.to == "D" })
        let pts = layout.edges[index].points
        XCTAssertEqual(pts.count, 2, "T → D should be one straight run, got \(pts)")
    }

    /// A node with a looped neighbour in its own layer must leave room for the
    /// loop and its caption, in either direction.
    func testSelfLoopsBesideNeighboursAreLintClean() {
        let sources = [
            "flowchart TD\n A --> B\n A --> C\n B -->|again and again| B",
            "flowchart TD\n A --> B\n A --> C\n A --> D\n C -->|retry| C",
            "flowchart LR\n A --> B\n A --> C\n B -->|again and again| B",
            "flowchart TD\n A --> A",
            "flowchart LR\n A -->|loop| A --> B",
            "flowchart TD\n A --> B --> C\n B -->|one| B\n B -->|two| B",
            "flowchart TD\n A ~~~ A\n A --> B",
            "flowchart TD\n D{x} -->|a| D\n D -->|b| D",
            "flowchart TD\n D{x} -->|r| D\n D --> E\n D --> F",
            "flowchart LR\n D{x} -->|r| D\n D --> E\n D --> F",
            "flowchart TD\n D{x} -->|r| D\n D --> E & F & G",
            "flowchart LR\n D{x} -->|r| D\n D --> E & F & G",
            "flowchart TD\n A[a node label wide enough to stretch the box] -->|x| A\n A --> B",
            "flowchart TD\n A --> B & C\n B --> D\n C -->|go| D\n D -->|again| D",
            "flowchart TD\n subgraph G\n A --> B\n end\n B -->|retry| B",
            "flowchart LR\n subgraph G\n A --> B\n end\n B -->|retry| B",
        ]
        for src in sources {
            let errors = lintErrors(src)
            XCTAssertTrue(errors.isEmpty, "\(src):\n" + errors.joined(separator: "\n"))
        }
    }
}
