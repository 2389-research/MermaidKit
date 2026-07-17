import XCTest
@testable import MermaidLayout

/// `DOTExporter` is the inverse of `DOTParser`. The headline property is a stable
/// round-trip: for a flat chart, `parse(export(chart)) == chart` exactly; for a
/// clustered chart, the round-trip preserves structure (nodes, shapes, edges,
/// membership). Two shapes with no DOT equivalent degrade as documented.
final class DOTExporterTests: XCTestCase {

    // MARK: - Flat charts round-trip exactly

    func testFlatRoundTripIsExact() throws {
        let shapes: [Flowchart.NodeShape] =
            [.rectangle, .rounded, .stadium, .diamond, .circle, .cylinder, .hexagon]
        let nodes = shapes.enumerated().map { i, s in
            // n0 carries a label distinct from its id (exercises the label attr);
            // the rest fall back to id (exercises label omission).
            Flowchart.Node(id: "n\(i)", label: i == 0 ? "Start here" : "n\(i)", shape: s)
        }
        let edges: [Flowchart.Edge] = [
            .init(from: "n0", to: "n1", label: "go",   dashed: false, hasArrow: true,  backArrow: false),
            .init(from: "n1", to: "n2", label: nil,    dashed: true,  hasArrow: true,  backArrow: false),
            .init(from: "n2", to: "n3", label: nil,    dashed: false, hasArrow: false, backArrow: false), // dir=none
            .init(from: "n3", to: "n4", label: "back", dashed: false, hasArrow: false, backArrow: true),  // dir=back
            .init(from: "n4", to: "n5", label: nil,    dashed: false, hasArrow: true,  backArrow: true),  // dir=both
            .init(from: "n5", to: "n6", label: "loop", dashed: true,  hasArrow: true,  backArrow: false),
        ]
        for dir: Flowchart.Direction in [.topDown, .leftRight, .rightLeft, .bottomTop] {
            let chart = Flowchart(direction: dir, nodes: nodes, edges: edges)
            let dot = DOTExporter.export(chart)
            let reparsed = try XCTUnwrap(DOTParser.parse(dot), "exported DOT failed to parse:\n\(dot)")
            XCTAssertEqual(reparsed, chart, "round-trip mismatch for \(dir):\n\(dot)")
        }
    }

    /// Starting from real DOT sources, `export(parse(dot))` is a fixed point of
    /// the parser — the strongest form of "DOT → Flowchart → DOT is stable".
    func testDOTSourceIdempotenceFlat() throws {
        let sources = [
            "digraph { A -> B -> C; C -> A; }",
            "digraph G { rankdir=LR; A [shape=diamond]; B [shape=cylinder]; A -> B [label=\"x\", style=dashed]; B -> A [dir=none]; }",
            "graph { A -- B -- C; }",                        // undirected → open links
            "digraph { node [shape=hexagon]; X -> Y [dir=both]; }",
        ]
        for src in sources {
            let f1 = try XCTUnwrap(DOTParser.parse(src), "source didn't parse: \(src)")
            let dot = DOTExporter.export(f1)
            let f2 = try XCTUnwrap(DOTParser.parse(dot), "export didn't re-parse:\n\(dot)")
            XCTAssertEqual(f2, f1, "not idempotent for: \(src)\n-> \(dot)")
        }
    }

    // MARK: - Clustered charts round-trip structurally

    func testSubgraphRoundTripsStructurally() throws {
        let src = """
        digraph {
          subgraph cluster_g {
            label="Group";
            A [shape=diamond];
            B;
          }
          C;
          A -> B;
          B -> C;
          C -> A [label="back"];
        }
        """
        let f1 = try XCTUnwrap(DOTParser.parse(src))
        let dot = DOTExporter.export(f1)
        let f2 = try XCTUnwrap(DOTParser.parse(dot), "clustered export didn't re-parse:\n\(dot)")

        XCTAssertEqual(Set(f2.nodes.map(\.id)), Set(f1.nodes.map(\.id)), "node set changed")
        XCTAssertEqual(shapesByID(f2), shapesByID(f1), "shapes changed")
        XCTAssertEqual(Set(f2.edges), Set(f1.edges), "edge set changed")
        XCTAssertEqual(membership(f2), membership(f1), "cluster membership changed")
    }

    // MARK: - Documented degradations

    func testLossyShapesDegradeAsDocumented() throws {
        let cases: [(Flowchart.NodeShape, Flowchart.NodeShape)] = [
            (.subroutine, .rectangle),
            (.stateStart, .circle),
            (.stateEnd,   .circle),
        ]
        for (input, expected) in cases {
            let chart = Flowchart(
                direction: .topDown,
                nodes: [Flowchart.Node(id: "A", label: "A", shape: input),
                        Flowchart.Node(id: "B", label: "B", shape: .rectangle)],
                edges: [.init(from: "A", to: "B", label: nil, dashed: false, hasArrow: true, backArrow: false)])
            let f2 = try XCTUnwrap(DOTParser.parse(DOTExporter.export(chart)))
            XCTAssertEqual(f2.nodes.first { $0.id == "A" }?.shape, expected,
                           "\(input) should degrade to \(expected)")
        }
    }

    // MARK: - Quoting

    func testQuotingHandlesSpacesAndReservedWords() throws {
        let chart = Flowchart(
            direction: .topDown,
            nodes: [Flowchart.Node(id: "graph", label: "graph", shape: .rectangle),   // reserved word
                    Flowchart.Node(id: "a b",   label: "two words", shape: .diamond)], // spaces in id + label
            edges: [.init(from: "graph", to: "a b", label: "e", dashed: false, hasArrow: true, backArrow: false)])
        let dot = DOTExporter.export(chart)
        let f2 = try XCTUnwrap(DOTParser.parse(dot), "quoted ids failed to parse:\n\(dot)")
        XCTAssertEqual(f2, chart, "reserved/space ids didn't round-trip:\n\(dot)")
    }

    // MARK: - Diagram-union convenience

    func testMermaidDiagramConvenience() throws {
        let chart = Flowchart(direction: .topDown,
                              nodes: [Flowchart.Node(id: "A", label: "A", shape: .rectangle)],
                              edges: [])
        XCTAssertNotNil(DOTExporter.export(.flowchart(chart)))

        let pie = try XCTUnwrap(MermaidParser.parse("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85"))
        XCTAssertNil(DOTExporter.export(pie), "only flowcharts should export to DOT")
    }

    // MARK: - helpers

    private func shapesByID(_ f: Flowchart) -> [String: Flowchart.NodeShape] {
        Dictionary(uniqueKeysWithValues: f.nodes.map { ($0.id, $0.shape) })
    }
    private func membership(_ f: Flowchart) -> [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: f.subgraphs.map { ($0.id, Set($0.nodeIDs)) })
    }
}
