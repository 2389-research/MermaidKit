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
