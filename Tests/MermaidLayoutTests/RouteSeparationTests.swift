import XCTest
@testable import MermaidLayout

/// Two edges never draw as one: no two routes share a line for more than a
/// stub (`edges-doubled`). Checked over seeded random charts dense enough that
/// jogs from unrelated fans meet in one layer gap, and two-cycles, back edges
/// and self-loops share columns.
final class RouteSeparationTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: Double(text.count) * size * 0.55, height: size * 1.2)
    }

    private func randomCharts(seed: UInt64, count: Int, subgraphs: Bool) -> [String] {
        var state = seed
        func next(_ n: Int) -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(n))
        }
        let directions = ["TD", "LR", "BT", "RL"]
        return (0..<count).map { _ in
            let n = 2 + next(10)
            var source = "flowchart \(directions[next(4)])\n"
            if subgraphs {
                let members = (0..<n).filter { _ in next(3) == 0 }
                if !members.isEmpty {
                    source += "  subgraph G\n" + members.map { "    n\($0)\n" }.joined() + "  end\n"
                }
            }
            for _ in 0..<next(2 * n + 3) {
                source += "  n\(next(n)) -->\(next(4) == 0 ? "|go|" : "") n\(next(n))\n"
            }
            return source
        }
    }

    private func doubled(_ source: String) -> [String] {
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return ["parse"] }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        return DiagramLayoutLinter.lint(DiagramScene.from(layout, measure: measure))
            .filter { $0.kind == "edges-doubled" }.map(\.detail)
    }

    func testTheCrossScopePassLeavesABoxLoopAlone() {
        // A loop on a group's box (both ends on its border) whose far run
        // lies on another edge's line: the other edge moves, never the loop.
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let loop = FlowchartLayout.PlacedEdge(
            start: CGPoint(x: 100, y: 10), end: CGPoint(x: 100, y: 40),
            points: [CGPoint(x: 100, y: 10), CGPoint(x: 120, y: 10), CGPoint(x: 120, y: 40), CGPoint(x: 100, y: 40)],
            label: nil, dashed: false, hasArrow: true)
        let other = FlowchartLayout.PlacedEdge(
            start: CGPoint(x: 200, y: -20), end: CGPoint(x: 200, y: 80),
            points: [CGPoint(x: 200, y: -20), CGPoint(x: 200, y: 0), CGPoint(x: 120, y: 0),
                     CGPoint(x: 120, y: 60), CGPoint(x: 200, y: 60), CGPoint(x: 200, y: 80)],
            label: nil, dashed: false, hasArrow: true)
        let node = { (x: CGFloat, y: CGFloat) in
            FlowchartLayout.PlacedNode(id: "n\(x)\(y)", label: "", shape: .rectangle,
                                       frame: CGRect(x: x - 28, y: y, width: 56, height: 32)) }
        let nodes = [node(200, -52), node(200, 80)]
        let out = DiagramLayoutEngine.separatedAcrossScopes(
            [other, loop], nodes: nodes, containers: [FlowchartLayout.Container(id: "G", label: "G", frame: box, depth: 0)])
        XCTAssertEqual(out[1].points, loop.points, "the box's loop stands fast")
        XCTAssertNotEqual(out[0].points, other.points, "the other edge moves aside")
    }

    func testACarriedCaptionStaysOnItsSegment() {
        // A three-point route whose last run lies along its target's top face
        // and doubles another edge: it steps off the face on a stub at its
        // end. Its caption, on the first run, stays where it was.
        let a = CGRect(x: 0, y: -32, width: 56, height: 32), b = CGRect(x: 100, y: 100, width: 56, height: 32)
        let other = FlowchartLayout.PlacedEdge(
            start: CGPoint(x: 60, y: -60), end: CGPoint(x: 140, y: 200),
            points: [CGPoint(x: 60, y: -60), CGPoint(x: 60, y: 100), CGPoint(x: 140, y: 100), CGPoint(x: 140, y: 200)],
            label: nil, dashed: false, hasArrow: true)
        let captioned = FlowchartLayout.PlacedEdge(
            start: CGPoint(x: 20, y: 0), end: CGPoint(x: 110, y: 100),
            points: [CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 100), CGPoint(x: 110, y: 100)],
            label: "go", dashed: false, hasArrow: true, labelPoint: CGPoint(x: 20, y: 50))
        let nodes = [a, b].enumerated().map { FlowchartLayout.PlacedNode(id: "n\($0.offset)", label: "", shape: .rectangle, frame: $0.element) }
        let out = DiagramLayoutEngine.separatedAcrossScopes([other, captioned], nodes: nodes, containers: [])
        XCTAssertEqual(out[1].points.count, 4, "it stepped off the face: \(out[1].points)")
        XCTAssertEqual(out[1].labelPoint, CGPoint(x: 20, y: 50))
    }

    func testABoxLoopStaysOnItsBox() {
        // A subgraph's own loop (folded or unfolded) is laid out round its
        // box; no later pass may move it, whatever it crowds.
        var state: UInt64 = 0x3C6E_F372_FE94_F82B
        func next(_ n: Int) -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(n))
        }
        for trial in 0..<400 {
            let n = 3 + next(8)
            var source = "flowchart \(["TD", "LR"][next(2)])\n  subgraph G\n"
            source += (0..<n).filter { _ in next(2) == 0 }.map { "    n\($0)\n" }.joined() + "    n\(n)\n  end\n"
            for _ in 0..<next(3 * n + 3) { source += "  n\(next(n + 1)) --> n\(next(n + 1))\n" }
            source += "  G --> G\n"
            if next(2) == 0 { source += "  G -->|again| G\n" }
            guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return XCTFail("parse") }
            let layout = DiagramLayoutEngine.layout(chart, measure: measure)
            guard let box = layout.containers.first(where: { $0.id == "G" })?.frame else { return XCTFail("box") }
            func onBorder(_ p: CGPoint) -> Bool {
                let inX = p.x >= box.minX - 0.5 && p.x <= box.maxX + 0.5, inY = p.y >= box.minY - 0.5 && p.y <= box.maxY + 0.5
                return (inY && (abs(p.x - box.minX) < 0.5 || abs(p.x - box.maxX) < 0.5))
                    || (inX && (abs(p.y - box.minY) < 0.5 || abs(p.y - box.maxY) < 0.5))
            }
            let loops = layout.edges.filter { onBorder($0.start) && onBorder($0.end) }
            XCTAssertGreaterThanOrEqual(loops.count, 1, "trial \(trial)\n\(source)")
            for loop in loops {
                for p in loop.points {
                    let inside = p.x > box.minX + 0.5 && p.x < box.maxX - 0.5 && p.y > box.minY + 0.5 && p.y < box.maxY - 0.5
                    XCTAssertFalse(inside, "trial \(trial): loop \(loop.points) inside \(box)\n\(source)")
                }
            }
        }
    }

    func testNoTwoEdgesShareALine() {
        for (trial, source) in randomCharts(seed: 0x510E_527F_ADE6_82D1, count: 1000, subgraphs: false).enumerated() {
            let found = doubled(source)
            XCTAssertTrue(found.isEmpty, "trial \(trial): \(found)\n\(source)")
        }
    }

    func testNoTwoEdgesShareALineWithASubgraph() {
        for (trial, source) in randomCharts(seed: 0x9B05_688C_2B3E_6C1F, count: 1000, subgraphs: true).enumerated() {
            let found = doubled(source)
            XCTAssertTrue(found.isEmpty, "trial \(trial): \(found)\n\(source)")
        }
    }

    func testAWideFanJogsInsideItsGap() {
        // #108: a fan needs a track per edge in the gap it jogs in. Every jog
        // fits, so each edge leaves and enters its node along the main axis,
        // and no two share a line. (A fan wider than its node's face has
        // ports for still crowds them there, nearer than a line apart.)
        for direction in ["TD", "LR"] {
            for n in [7, 12, 16] {
                for (out, label) in [(true, ""), (false, ""), (true, "|x|")] {
                    let source = "flowchart \(direction)\n" + (0..<n).map {
                        out ? "  R -->\(label) N\($0)" : "  N\($0) -->\(label) R"
                    }.joined(separator: "\n")
                    let found = doubled(source)
                    XCTAssertTrue(found.isEmpty, "\(direction) \(n) out=\(out) \(label): \(found.count) doubled")
                    guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return XCTFail("parse") }
                    for edge in DiagramLayoutEngine.layout(chart, measure: measure).edges where edge.points.count > 2 {
                        for (a, b) in [(edge.points[0], edge.points[1]),
                                       (edge.points[edge.points.count - 2], edge.points[edge.points.count - 1])] {
                            let along = direction == "TD" ? abs(a.y - b.y) : abs(a.x - b.x)
                            let across = direction == "TD" ? abs(a.x - b.x) : abs(a.y - b.y)
                            XCTAssertTrue(across < 0.5 && along >= Self.arrowhead - 0.01,
                                          "\(direction) \(n) out=\(out) \(label): end segment \(a) → \(b)")
                        }
                    }
                }
            }
        }
    }

    func testALongFanEdgeGrowsOnlyTheGapsBesideItsEnds() {
        // A fan's tracks matter beside its hub: a fan of 30 out of R into a
        // chain N0 → … → N29 widens R's gap, and no gap further down, where
        // only the edges into one node meet.
        let source = "flowchart TD\n" + (0..<30).map { "  R --> N\($0)" }.joined(separator: "\n")
            + "\n" + (0..<29).map { "  N\($0) --> N\($0 + 1)" }.joined(separator: "\n")
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return XCTFail("parse") }
        let frames = Dictionary(uniqueKeysWithValues: DiagramLayoutEngine.layout(chart, measure: measure)
            .nodes.map { ($0.id, $0.frame) })
        for i in 0..<28 {
            let gap = frames["N\(i + 1)"]!.minY - frames["N\(i)"]!.maxY
            XCTAssertEqual(gap, 56, accuracy: 0.5, "gap below N\(i)")
        }
        XCTAssertEqual(doubled(source), [])
    }

    private static let arrowhead = DiagramLayoutEngine.flowchartArrowheadLen
}
