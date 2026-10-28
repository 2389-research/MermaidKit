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
}
