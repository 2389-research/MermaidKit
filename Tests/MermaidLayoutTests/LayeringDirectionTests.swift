import XCTest
@testable import MermaidLayout

/// A layered layout's one promise about direction: an edge that lies on no
/// cycle points strictly down the layering (#102, #104). Only a cycle forces
/// an edge to point back up. Checked exactly, over seeded random digraphs
/// that mix cycles, self-loops, parallel edges and isolated nodes, for the
/// layer solver itself and for every diagram that lays out in rows.
final class LayeringDirectionTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: Double(text.count) * size * 0.55, height: size * 1.2)
    }

    /// Seeded random digraphs on `n0`…`n(k-1)`.
    private func randomGraphs(seed: UInt64, count: Int) -> [(ids: [String], edges: [(Int, Int)])] {
        var state = seed
        func next(_ n: Int) -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(n))
        }
        return (0..<count).map { _ in
            let n = 1 + next(9)
            let edges = (0..<next(2 * n + 1)).map { _ in (next(n), next(n)) }
            return ((0..<n).map { "n\($0)" }, edges)
        }
    }

    /// The edges that lie on no cycle: `u → v` with no path back from `v` to `u`.
    private func acyclicEdges(_ n: Int, _ edges: [(Int, Int)]) -> [(Int, Int)] {
        var reach = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        for (u, v) in edges { reach[u][v] = true }
        for k in 0..<n { for i in 0..<n where reach[i][k] { for j in 0..<n where reach[k][j] { reach[i][j] = true } } }
        return edges.filter { !reach[$0.1][$0.0] }
    }

    // MARK: - The layer solver

    func testSelfEdgesAreIgnored() {
        // The issue's two cases: a self-edge must not lift its node.
        XCTAssertEqual(DiagramLayoutEngine.assignLayers(ids: ["x", "y"], edges: [("x", "y"), ("x", "x")]),
                       ["x": 0, "y": 1])
        XCTAssertEqual(DiagramLayoutEngine.assignLayers(
            ids: ["n0", "n1", "n2"], edges: [("n1", "n2"), ("n0", "n1"), ("n0", "n2"), ("n0", "n0")]),
                       ["n0": 0, "n1": 1, "n2": 2])
        XCTAssertEqual(DiagramLayoutEngine.longestPathLayers(ids: ["x"], edges: [("x", "x")]), ["x": 0])
    }

    func testSolverPointsEveryForwardEdgeDown() {
        // Callers strip back edges; self-edges may stay in, as the doc says.
        for (trial, g) in randomGraphs(seed: 0x9E37_79B9_7F4A_7C15, count: 400).enumerated() {
            let named = g.edges.map { (g.ids[$0.0], g.ids[$0.1]) }
            let back = DiagramLayoutEngine.backEdgeIndices(ids: g.ids, edges: named)
            let forward = named.enumerated().filter { !back.contains($0.offset) || $0.element.0 == $0.element.1 }
                .map(\.element)
            let layer = DiagramLayoutEngine.assignLayers(ids: g.ids, edges: forward)
            for (u, v) in forward where u != v {
                XCTAssertLessThan(layer[u]!, layer[v]!, "trial \(trial): \(u) → \(v) in \(named)")
            }
        }
    }

    // MARK: - Diagrams in rows

    func testC4RelationshipLeavingACycleDescends() throws {
        // The issue's chart: b → c is on no cycle, so C sits below B.
        guard case .c4(let c4)? = MermaidParser.parse("""
            C4Context
            Person(a, "A")
            Person(b, "B")
            Person(c, "C")
            Rel(a, b, "x")
            Rel(b, a, "y")
            Rel(b, c, "z")
            """) else { return XCTFail("parse") }
        let rows = DiagramLayoutEngine.layout(c4, measure: measure).boxes.map(\.frame.minY)
        XCTAssertLessThan(rows[0], rows[1])
        XCTAssertLessThan(rows[1], rows[2])
    }

    func testC4PointsEveryAcyclicRelationshipDown() {
        for (trial, g) in randomGraphs(seed: 0x2545_F491_4F6C_DD1D, count: 300).enumerated() {
            let source = "C4Context\n" + g.ids.map { "Person(\($0), \"\($0)\")" }.joined(separator: "\n")
                + "\n" + g.edges.map { "Rel(n\($0.0), n\($0.1), \"r\")" }.joined(separator: "\n")
            guard case .c4(let c4)? = MermaidParser.parse(source) else { return XCTFail("parse \(trial)") }
            let boxes = DiagramLayoutEngine.layout(c4, measure: measure).boxes
            XCTAssertEqual(boxes.count, g.ids.count, "trial \(trial)")
            for (u, v) in acyclicEdges(g.ids.count, g.edges) where u != v {
                XCTAssertLessThan(boxes[u].frame.minY, boxes[v].frame.minY, "trial \(trial): n\(u) → n\(v)\n\(source)")
            }
        }
    }

    func testFlowchartPointsEveryAcyclicEdgeDown() {
        for (trial, g) in randomGraphs(seed: 0xD1B5_4A32_D192_ED03, count: 300).enumerated() {
            let source = "flowchart TD\n" + g.ids.map { " \($0)" }.joined(separator: "\n")
                + "\n" + g.edges.map { " n\($0.0) --> n\($0.1)" }.joined(separator: "\n")
            guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return XCTFail("parse \(trial)") }
            let frames = Dictionary(DiagramLayoutEngine.layout(chart, measure: measure).nodes.map { ($0.id, $0.frame) },
                                    uniquingKeysWith: { a, _ in a })
            for (u, v) in acyclicEdges(g.ids.count, g.edges) where u != v {
                XCTAssertLessThan(frames["n\(u)"]!.midY, frames["n\(v)"]!.midY, "trial \(trial): n\(u) → n\(v)\n\(source)")
            }
        }
    }
}
