import XCTest
@testable import MermaidLayout

/// A subgraph is laid out as one box in one row of its parent, unless that
/// would send an edge on no cycle back up: then it is laid out with its
/// parent's nodes and its box spans the rows its members take, as mermaid's
/// (dagre's) does (#103). Checked exactly, over seeded random charts with
/// nested subgraphs and direction overrides: every edge on no cycle points
/// forward along the main axis of the layout that places it, and no group box
/// overlaps a node that isn't in it.
final class SubgraphLayeringTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: Double(text.count) * size * 0.55, height: size * 1.2)
    }

    private func layout(_ source: String, file: StaticString = #filePath, line: UInt = #line)
        -> (chart: Flowchart, layout: FlowchartLayout)? {
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else {
            XCTFail("parse", file: file, line: line); return nil
        }
        return (chart, DiagramLayoutEngine.layout(chart, measure: measure))
    }

    /// Whether `outer` holds `inner`, edges compared directly: Foundation's
    /// `CGRect.contains(_:)` on Linux misses exact fits by a rounding error.
    private func holds(_ outer: CGRect, _ inner: CGRect) -> Bool {
        inner.minX >= outer.minX - 1e-9 && inner.maxX <= outer.maxX + 1e-9
            && inner.minY >= outer.minY - 1e-9 && inner.maxY <= outer.maxY + 1e-9
    }

    private func frames(_ layout: FlowchartLayout) -> [String: CGRect] {
        Dictionary(layout.nodes.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - The issue's charts

    func testIssueChartRanksLikeMermaid() throws {
        // X → A → Y is acyclic, so it reads top to bottom, with S's box
        // spanning X's row to Y's and A beside it.
        let (_, l) = try XCTUnwrap(layout("""
            flowchart TD
              subgraph S
                X
                Y
              end
              X --> A
              A --> Y
            """))
        let f = frames(l)
        XCTAssertLessThan(f["X"]!.midY, f["A"]!.midY)
        XCTAssertLessThan(f["A"]!.midY, f["Y"]!.midY)
        let box = try XCTUnwrap(l.containers.first { $0.id == "S" }).frame
        XCTAssertTrue(holds(box, f["X"]!) && holds(box, f["Y"]!), "\(box) holds its members")
        XCTAssertFalse(box.intersects(f["A"]!), "\(box) keeps A out")
    }

    func testMidCycleSubgraphIsFound() throws {
        // a → x, y → b, b → a: no cycle. Folded into one box, S sits in the
        // middle of A → S → B → A, so the edge drawn back up is b → a, whose
        // ends are both outside S.
        let (_, l) = try XCTUnwrap(layout("""
            flowchart TD
              subgraph S
                x
                y
              end
              a --> x
              y --> b
              b --> a
            """))
        let f = frames(l)
        XCTAssertLessThan(f["a"]!.midY, f["x"]!.midY)
        XCTAssertLessThan(f["y"]!.midY, f["b"]!.midY)
        XCTAssertLessThan(f["b"]!.midY, f["a"]!.midY)
    }

    func testEdgeToAnUnfoldedSubgraphEndsOnItsBox() throws {
        // S is laid out with the chart's nodes; an edge naming S still ends on
        // S's box, from outside it.
        let (_, l) = try XCTUnwrap(layout("""
            flowchart TD
              subgraph S
                X
                Y
              end
              X --> A
              A --> Y
              B --> S
            """))
        let box = try XCTUnwrap(l.containers.first { $0.id == "S" }).frame
        let b = frames(l)["B"]!
        let edge = try XCTUnwrap(l.edges.first { b.insetBy(dx: -0.5, dy: -0.5).contains($0.start) })
        let end = edge.end
        let onSide = (abs(end.x - box.minX) < 0.5 || abs(end.x - box.maxX) < 0.5)
            && end.y >= box.minY - 0.5 && end.y <= box.maxY + 0.5
        let onTopOrBottom = (abs(end.y - box.minY) < 0.5 || abs(end.y - box.maxY) < 0.5)
            && end.x >= box.minX - 0.5 && end.x <= box.maxX + 0.5
        XCTAssertTrue(onSide || onTopOrBottom, "B → S ends at \(end), on \(box)")
        XCTAssertFalse(box.contains(frames(l)["B"]!))
    }

    func testCaptionOnAnEdgeToAnUnfoldedSubgraphHasRoom() throws {
        // The edge leaves S's box from the side, toward B beside it, and is
        // cut at the box: B stands off far enough for the caption and a stub
        // either side, top-down or left-right, in or out.
        for (direction, edge) in [("TD", "S -->|a very long edge label| B"), ("LR", "S -->|a very long edge label| B"),
                                  ("TD", "B -->|a very long edge label| S")] {
            let (_, l) = try XCTUnwrap(layout("""
                flowchart \(direction)
                  subgraph S
                    X
                    Y
                  end
                  X --> A
                  A --> Y
                  \(edge)
                """))
            let crowded = DiagramLayoutLinter.lint(DiagramScene.from(l, measure: measure))
                .filter { $0.kind == "label-crowds-edge" || $0.kind == "label-on-fixture" }
            XCTAssertTrue(crowded.isEmpty, "\(direction) \(edge): \(crowded.map(\.detail))")
        }
    }

    func testChartsThatWereRightAreUnchanged() throws {
        // A subgraph whose box sends nothing back up stays one box in one row,
        // with its own direction.
        let (chart, l) = try XCTUnwrap(layout("""
            flowchart TD
              A --> S
              subgraph S
                direction LR
                X --> Y
              end
              S --> B
            """))
        let f = frames(l)
        XCTAssertEqual(f["X"]!.midY, f["Y"]!.midY, accuracy: 0.001)
        XCTAssertLessThan(f["X"]!.midX, f["Y"]!.midX)
        XCTAssertTrue(DiagramLayoutEngine.unfoldedSubgraphs(chart).isEmpty)
    }

    // MARK: - Properties over random charts

    private struct RandomChart {
        var source: String
        var nodeCount: Int
        /// Edges between nodes, by index.
        var edges: [(Int, Int)]
        /// Edges from a node to a subgraph, by index.
        var toSubgraph: [(Int, Int)]
    }

    /// Seeded random charts: up to four subgraphs, nested at random, some
    /// with a direction of their own, nodes spread over them, random edges,
    /// some captioned and some to a subgraph.
    private func randomCharts(seed: UInt64, count: Int) -> [RandomChart] {
        var state = seed
        func next(_ n: Int) -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(n))
        }
        let directions = ["TD", "LR", "BT", "RL"]
        return (0..<count).map { _ in
            let n = 2 + next(9)
            let subCount = 1 + next(4)
            let parent = (0..<subCount).map { k in k == 0 ? -1 : next(k + 1) - 1 }   // -1 = top level
            let home = (0..<n).map { _ in next(subCount + 1) - 1 }
            let edges = (0..<next(2 * n + 2)).map { _ in (next(n), next(n)) }
            let toSubgraph = (0..<next(3)).map { _ in (next(n), next(subCount)) }
            func body(_ sub: Int, _ indent: String) -> String {
                var s = ""
                for k in 0..<subCount where parent[k] == sub {
                    s += "\(indent)subgraph G\(k)\n"
                    if next(4) == 0 { s += "\(indent)  direction \(directions[next(4)])\n" }
                    s += body(k, indent + "  ")
                    s += "\(indent)end\n"
                }
                for i in 0..<n where home[i] == sub { s += "\(indent)n\(i)\n" }
                return s
            }
            let source = "flowchart \(directions[next(4)])\n" + body(-1, "  ")
                + edges.map { "  n\($0.0) -->\(next(4) == 0 ? "|go|" : "") n\($0.1)\n" }.joined()
                + toSubgraph.map { "  n\($0.0) --> G\($0.1)\n" }.joined()
            return RandomChart(source: source, nodeCount: n, edges: edges, toSubgraph: toSubgraph)
        }
    }

    func testEveryAcyclicEdgePointsForward() throws {
        for (trial, random) in randomCharts(seed: 0x6A09_E667_F3BC_C908, count: 600).enumerated() {
            let (chart, l) = try XCTUnwrap(layout(random.source))
            // Vertices: the nodes, then the subgraphs (an edge may name one).
            let n = random.nodeCount + chart.subgraphs.count
            let subIndex = Dictionary(chart.subgraphs.enumerated().map { ($1.id, random.nodeCount + $0) },
                                      uniquingKeysWith: { a, _ in a })
            var reach = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
            for (u, v) in random.edges { reach[u][v] = true }
            for (u, g) in random.toSubgraph { if let v = subIndex["G\(g)"] { reach[u][v] = true } }
            for k in 0..<n { for i in 0..<n where reach[i][k] { for j in 0..<n where reach[k][j] { reach[i][j] = true } } }
            let f = frames(l)
            let unfolded = DiagramLayoutEngine.unfoldedSubgraphs(chart)
            var containerOf: [String: String] = [:]
            for sub in chart.subgraphs {
                for id in sub.nodeIDs { containerOf[id] = sub.id }
                for id in sub.childIDs { containerOf[id] = sub.id }
            }
            func chain(_ id: String) -> [String] {
                var out: [String] = [], cur = containerOf[id]
                while let c = cur { out.append(c); cur = containerOf[c] }
                return out
            }
            let subByID = Dictionary(chart.subgraphs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (u, v) in random.edges where u != v && !reach[v][u] {
                let a = "n\(u)", b = "n\(v)"
                // The layout that places this edge: the innermost subgraph
                // holding both ends that is laid out on its own, else the chart.
                let shared = chain(a).filter { Set(chain(b)).contains($0) }
                let owner = shared.first { !unfolded.contains($0) }
                // Its direction: its own, else inherited; an unfolded subgraph
                // takes its parent's.
                var direction = chart.direction
                for scope in ([owner].compactMap { $0 } + chain(owner ?? "")).reversed()
                where !unfolded.contains(scope) {
                    if let d = subByID[scope]?.direction { direction = d }
                }
                let horizontal = direction == .leftRight || direction == .rightLeft
                let forward = horizontal ? f[b]!.midX - f[a]!.midX : f[b]!.midY - f[a]!.midY
                XCTAssertGreaterThan(forward, 0, "trial \(trial): \(a) → \(b) in \(owner ?? "the chart")\n\(random.source)")
            }
        }
    }

    func testNoBoxOverlapsANonMember() throws {
        for (trial, random) in randomCharts(seed: 0xBB67_AE85_84CA_A73B, count: 600).enumerated() {
            let (chart, l) = try XCTUnwrap(layout(random.source))
            var members: [String: Set<String>] = [:]
            let subByID = Dictionary(chart.subgraphs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            func collect(_ id: String) -> Set<String> {
                if let m = members[id] { return m }
                guard let sub = subByID[id] else { return [] }
                let m = Set(sub.nodeIDs).union(sub.childIDs).union(sub.childIDs.flatMap(collect))
                members[id] = m
                return m
            }
            // Every chart node is drawn once, and nothing else is (a
            // subgraph's stand-in is never drawn).
            XCTAssertEqual(l.nodes.map(\.id).sorted(), chart.nodes.map(\.id).sorted(), "trial \(trial)")
            XCTAssertEqual(Set(l.containers.map(\.id)), Set(chart.subgraphs.map(\.id)), "trial \(trial)")
            for box in l.containers {
                let inside = collect(box.id)
                for node in l.nodes {
                    if inside.contains(node.id) {
                        XCTAssertTrue(holds(box.frame, node.frame),
                                      "trial \(trial): \(box.id) \(box.frame) holds \(node.id) \(node.frame)\n\(random.source)")
                    } else {
                        XCTAssertFalse(box.frame.intersects(node.frame),
                                       "trial \(trial): \(box.id) \(box.frame) overlaps \(node.id) \(node.frame)\n\(random.source)")
                    }
                }
                // Boxes nest or stand apart.
                for other in l.containers where other.id != box.id && !inside.contains(other.id) && !collect(other.id).contains(box.id) {
                    XCTAssertFalse(box.frame.intersects(other.frame),
                                   "trial \(trial): \(box.id) \(box.frame) overlaps \(other.id) \(other.frame)\n\(random.source)")
                }
            }
        }
    }

    func testSnappedEdgesStayOnTheirBorders() throws {
        // On a grid, a box grows to whole cells; an edge ending on a box (one
        // naming its subgraph) must end on the grown border, not inside it.
        func onBorder(_ p: CGPoint, _ r: CGRect) -> Bool {
            let inX = p.x >= r.minX - 0.5 && p.x <= r.maxX + 0.5, inY = p.y >= r.minY - 0.5 && p.y <= r.maxY + 0.5
            return (inY && (abs(p.x - r.minX) < 0.5 || abs(p.x - r.maxX) < 0.5))
                || (inX && (abs(p.y - r.minY) < 0.5 || abs(p.y - r.maxY) < 0.5))
        }
        for unit: CGFloat in [4, 8] {
            for (trial, random) in randomCharts(seed: 0x1F83_D9AB_FB41_BD6B, count: 300).enumerated() {
                guard case .flowchart(let chart)? = MermaidParser.parse(random.source) else { return XCTFail("parse") }
                let l = DiagramLayoutEngine.layout(chart, measure: measure, spacing: DiagramSpacing(gridSnap: unit))
                let borders = l.nodes.map(\.frame) + l.containers.map(\.frame)
                for edge in l.edges where !edge.invisible && edge.start != edge.end {
                    for p in [edge.start, edge.end] {
                        XCTAssertTrue(borders.contains { onBorder(p, $0) },
                                      "grid \(unit), trial \(trial): \(p) on no border\n\(random.source)")
                    }
                }
            }
        }
    }

    func testLayoutIsDeterministic() throws {
        for random in randomCharts(seed: 0x3C6E_F372_FE94_F82B, count: 100) {
            let (_, a) = try XCTUnwrap(layout(random.source))
            let (_, b) = try XCTUnwrap(layout(random.source))
            XCTAssertEqual(a.nodes.map(\.frame), b.nodes.map(\.frame))
            XCTAssertEqual(a.containers.map(\.frame), b.containers.map(\.frame))
            XCTAssertEqual(a.edges.map(\.points), b.edges.map(\.points))
        }
    }
}
