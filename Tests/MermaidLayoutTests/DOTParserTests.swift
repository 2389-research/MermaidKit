import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Exercises the Graphviz DOT front-end (`DOTParser`) against the shared
/// `Flowchart` IR: the structural grammar, the attribute subset that maps onto
/// the model, and — non-negotiably — that malformed/hostile input never crashes
/// or hangs (nil is always an acceptable answer). A final case runs the full
/// parse → layout → scene → lint pipeline and asserts it comes back clean.
final class DOTParserTests: XCTestCase {

    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    private func parse(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> Flowchart {
        guard let chart = DOTParser.parse(s) else {
            XCTFail("expected a parse", file: file, line: line)
            return Flowchart(direction: .topDown, nodes: [], edges: [])
        }
        return chart
    }

    // MARK: nodes + edges

    func testNodesAndEdges() {
        let chart = parse("digraph { A -> B; B -> C }")
        XCTAssertEqual(chart.nodes.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(chart.edges.count, 2)
        XCTAssertEqual(chart.edges[0].from, "A")
        XCTAssertEqual(chart.edges[0].to, "B")
        XCTAssertTrue(chart.edges[0].hasArrow)   // digraph → directed
    }

    func testStandaloneNodeDeclaration() {
        let chart = parse("digraph { A; B; C }")
        XCTAssertEqual(chart.nodes.map(\.id), ["A", "B", "C"])
        XCTAssertTrue(chart.edges.isEmpty)
        // Bare id → label defaults to the id.
        XCTAssertEqual(chart.nodes[0].label, "A")
    }

    // MARK: edge chains

    func testEdgeChain() {
        let chart = parse("digraph { a -> b -> c }")
        XCTAssertEqual(chart.nodes.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(chart.edges.count, 2)
        XCTAssertEqual(chart.edges.map { "\($0.from)->\($0.to)" }, ["a->b", "b->c"])
    }

    // MARK: undirected

    func testUndirectedGraph() {
        let chart = parse("graph { a -- b -- c }")
        XCTAssertEqual(chart.edges.count, 2)
        // graph (not digraph) → no arrowheads.
        XCTAssertFalse(chart.edges[0].hasArrow)
        XCTAssertFalse(chart.edges[1].hasArrow)
    }

    func testDigraphAlwaysArrows() {
        // A `--` operator inside a digraph is still directed (graph type wins).
        let chart = parse("digraph { a -- b }")
        XCTAssertTrue(chart.edges[0].hasArrow)
    }

    // MARK: attributes

    func testLabelAndDiamondShape() {
        let chart = parse(#"digraph { A [label="Start", shape=diamond]; A -> B }"#)
        let a = chart.nodes.first { $0.id == "A" }
        XCTAssertEqual(a?.label, "Start")
        XCTAssertEqual(a?.shape, .diamond)
    }

    func testShapeMapping() {
        let chart = parse("""
        digraph {
          box [shape=box]; rec [shape=rect]; dia [shape=diamond];
          ell [shape=ellipse]; cir [shape=circle]; cyl [shape=cylinder];
          rc [shape=Mrecord]; unk [shape=somethingElse]
        }
        """)
        func shape(_ id: String) -> Flowchart.NodeShape? { chart.nodes.first { $0.id == id }?.shape }
        XCTAssertEqual(shape("box"), .rectangle)
        XCTAssertEqual(shape("rec"), .rectangle)
        XCTAssertEqual(shape("dia"), .diamond)
        XCTAssertEqual(shape("ell"), .rounded)
        XCTAssertEqual(shape("cir"), .circle)
        XCTAssertEqual(shape("cyl"), .cylinder)
        XCTAssertEqual(shape("rc"), .rectangle)   // Mrecord → rect
        XCTAssertEqual(shape("unk"), .rectangle)  // unknown → rect (degrade)
    }

    func testEdgeLabelAndStyle() {
        let chart = parse(#"digraph { A -> B [label="go", style=dashed] }"#)
        XCTAssertEqual(chart.edges.first?.label, "go")
        XCTAssertTrue(chart.edges.first?.dashed ?? false)
    }

    func testEdgeAttrIsEdgeNotNodeLabel() {
        // `A -> D [label="skip"]` labels the EDGE; D keeps its id label.
        let chart = parse(#"digraph { A -> D [label="skip"] }"#)
        XCTAssertEqual(chart.edges.first?.label, "skip")
        XCTAssertEqual(chart.nodes.first { $0.id == "D" }?.label, "D")
    }

    func testDirNoneClearsArrow() {
        let chart = parse("digraph { A -> B [dir=none]; C -> D [dir=both] }")
        XCTAssertFalse(chart.edges[0].hasArrow)
        XCTAssertTrue(chart.edges[1].backArrow)
    }

    func testLabelLineBreaks() {
        let chart = parse(#"digraph { A [label="one\ntwo\lthree"] }"#)
        XCTAssertEqual(chart.nodes.first?.label, "one\ntwo\nthree")
    }

    // MARK: default attributes

    func testNodeDefaultShape() {
        let chart = parse("digraph { node [shape=box]; A; B [shape=diamond]; C }")
        func shape(_ id: String) -> Flowchart.NodeShape? { chart.nodes.first { $0.id == id }?.shape }
        XCTAssertEqual(shape("A"), .rectangle)   // from default
        XCTAssertEqual(shape("B"), .diamond)     // explicit overrides default
        XCTAssertEqual(shape("C"), .rectangle)   // default still applies after
    }

    func testDefaultsDoNotLeakOutOfSubgraph() {
        let chart = parse("""
        digraph {
          A;
          subgraph { node [shape=diamond]; B }
          C
        }
        """)
        func shape(_ id: String) -> Flowchart.NodeShape? { chart.nodes.first { $0.id == id }?.shape }
        XCTAssertEqual(shape("A"), .rectangle)
        XCTAssertEqual(shape("B"), .diamond)
        XCTAssertEqual(shape("C"), .rectangle)   // default stayed inside the subgraph
    }

    // MARK: direction

    func testRankdirBare() {
        XCTAssertEqual(parse("digraph { rankdir=LR; A -> B }").direction, .leftRight)
        XCTAssertEqual(parse("digraph { rankdir=RL; A -> B }").direction, .rightLeft)
        XCTAssertEqual(parse("digraph { rankdir=BT; A -> B }").direction, .bottomTop)
        XCTAssertEqual(parse("digraph { rankdir=TB; A -> B }").direction, .topDown)
        XCTAssertEqual(parse("digraph { A -> B }").direction, .topDown)   // default
    }

    func testRankdirViaGraphAttrStmt() {
        XCTAssertEqual(parse("digraph { graph [rankdir=LR]; A -> B }").direction, .leftRight)
    }

    // MARK: subgraphs / clusters

    func testClusterBecomesSubgraph() {
        let chart = parse(#"digraph { subgraph cluster_0 { label="X"; a; b } c }"#)
        XCTAssertEqual(chart.subgraphs.count, 1)
        let sg = chart.subgraphs[0]
        XCTAssertEqual(sg.label, "X")
        XCTAssertEqual(Set(sg.nodeIDs), ["a", "b"])
        XCTAssertTrue(chart.nodes.contains { $0.id == "c" })
    }

    func testAnonymousSubgraphNoBox() {
        // Anonymous / non-cluster subgraph is scope only — no cluster box.
        let chart = parse("digraph { { a b } c }")
        XCTAssertTrue(chart.subgraphs.isEmpty)
        XCTAssertEqual(Set(chart.nodes.map(\.id)), ["a", "b", "c"])
    }

    func testSubgraphEdgeFanOut() {
        // `a -> { b c }` fans out to a->b and a->c.
        let chart = parse("digraph { a -> { b c } }")
        XCTAssertEqual(chart.edges.count, 2)
        XCTAssertEqual(Set(chart.edges.map(\.to)), ["b", "c"])
        XCTAssertTrue(chart.edges.allSatisfy { $0.from == "a" })
    }

    func testNestedClusters() {
        let chart = parse("""
        digraph {
          subgraph cluster_a {
            label="A";
            subgraph cluster_b { label="B"; x }
            y
          }
        }
        """)
        XCTAssertEqual(chart.subgraphs.count, 2)
        let outer = chart.subgraphs.first { $0.label == "A" }
        let inner = chart.subgraphs.first { $0.label == "B" }
        XCTAssertNotNil(outer)
        XCTAssertNotNil(inner)
        XCTAssertEqual(inner?.nodeIDs, ["x"])            // inner claims x
        XCTAssertEqual(outer?.nodeIDs, ["y"])            // outer claims only y
        XCTAssertEqual(outer?.childIDs.count, 1)
    }

    // MARK: ids: quoting, escapes, numerals, concat, html

    func testQuotedIdsWithSpaces() {
        let chart = parse(#"digraph { "hello world" -> "a \"quoted\" b" }"#)
        XCTAssertEqual(chart.nodes.map(\.id), ["hello world", #"a "quoted" b"#])
    }

    func testStringConcatenation() {
        let chart = parse(#"digraph { A [label="foo" + "bar"] }"#)
        XCTAssertEqual(chart.nodes.first?.label, "foobar")
    }

    func testNumericIds() {
        let chart = parse("digraph { 1 -> 2 -> 3 }")
        XCTAssertEqual(chart.nodes.map(\.id), ["1", "2", "3"])
    }

    func testHTMLLabelDegradesToText() {
        let chart = parse("digraph { A [label=<<b>Bold</b> text>] }")
        XCTAssertEqual(chart.nodes.first?.label, "Bold text")
    }

    func testPortsAreDiscarded() {
        let chart = parse("digraph { A:north -> B:f0:s }")
        XCTAssertEqual(chart.nodes.map(\.id), ["A", "B"])
        XCTAssertEqual(chart.edges.first.map { "\($0.from)->\($0.to)" }, "A->B")
    }

    // MARK: comments

    func testComments() {
        let chart = parse("""
        // line comment
        digraph {
          # preprocessor line
          A -> B   /* inline block */
          /* multi
             line */
          B -> C
        }
        """)
        XCTAssertEqual(chart.nodes.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(chart.edges.count, 2)
    }

    func testStrictKeywordAndGraphName() {
        let chart = parse("strict digraph MyGraph { A -> B }")
        XCTAssertEqual(chart.nodes.map(\.id), ["A", "B"])
    }

    // MARK: adversarial — must never crash or hang

    func testAdversarialNeverCrashes() {
        let cases: [String] = [
            "", " ", "\n\n", "{", "}", "{{{{{{{{", "}}}}}}}}",
            "digraph", "digraph {", "digraph }", "graph {",
            "digraph { -->  --  ->  }",
            "digraph { a -> }", "digraph { -> b }", "digraph { -> }",
            "digraph { A [ }", "digraph { A [label= }",
            "digraph { subgraph cluster_0 {", "digraph { subgraph {",
            "digraph { A ; ; ; ; B }",
            #"digraph { "unterminated -> B }"#,
            "digraph { A [label=<<b>unclosed html] }",
            "not a graph at all",
            "flowchart TD\n A --> B",   // Mermaid, not DOT → nil is fine
            "digraph { 1e308 -> 2 }",
            "＜＞〔〕 🧜‍♀️",
        ]
        for s in cases {
            // The assertion is simply: we return (nil is acceptable, crashing is not).
            let chart = DOTParser.parse(s)
            if let chart { XCTAssertGreaterThanOrEqual(chart.nodes.count, 0) }
        }
    }

    func testDeeplyNestedBracesDoNotStackOverflow() {
        let deep = "digraph { " + String(repeating: "subgraph { ", count: 5_000)
            + "a" + String(repeating: " }", count: 5_000) + " }"
        // Depth cap → nil (never a crash/hang).
        _ = DOTParser.parse(deep)
    }

    func testHugeInputReturnsFast() {
        // Over maxTextSize → nil immediately; also a well-formed huge chain.
        let huge = String(repeating: "a -> b -> ", count: 20_000)
        _ = DOTParser.parse("digraph { \(huge) a }")
        let over = String(repeating: "x", count: 200_000)
        XCTAssertNil(DOTParser.parse("digraph { \(over) }"))
    }

    func testEdgeCapHonored() {
        // A cross-product that blows past maxEdges returns nil (like MermaidParser).
        let left = (0..<60).map { "n\($0)" }.joined(separator: " ")
        let right = (0..<60).map { "m\($0)" }.joined(separator: " ")
        // 60×60 = 3600 edges > maxEdges(500) → nil.
        XCTAssertNil(DOTParser.parse("digraph { { \(left) } -> { \(right) } }"))
    }

    // MARK: full pipeline — parse → layout → scene lints clean

    func testParseLayoutSceneLintsClean() {
        let source = """
        digraph Pipeline {
          rankdir=LR;
          node [shape=box];
          A [label="Start"];
          A -> B -> C;
          B -> D [label="skip"];
          subgraph cluster_0 { label="group"; C; D }
        }
        """
        guard let chart = DOTParser.parse(source) else { return XCTFail("did not parse") }
        let scene = DiagramScene.lower(.flowchart(chart), measure: measure)
        XCTAssertGreaterThan(scene.size.width, 0)
        let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "layout errors: \(errors)")
    }
}
