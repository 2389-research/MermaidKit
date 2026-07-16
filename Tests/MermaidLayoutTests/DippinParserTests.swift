import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Exercises the Dippin front-end (`DippinParser`) against the shared `Flowchart`
/// IR: the `workflow` structure, the eight typed node kinds → distinct shapes,
/// the edge grammar (`when` conditions → edge labels, `loop`/`restart: true`
/// back-edges, the `parallel …-> a,b` / `fan_in …<- a,b` fan sugar), the
/// skipping of raw multiline blocks — and, non-negotiably, that malformed/hostile
/// input never crashes or hangs (nil is always acceptable). A final case runs the
/// full parse → layout → scene → lint pipeline and asserts it comes back clean.
final class DippinParserTests: XCTestCase {

    private let measure: DiagramTextMeasurer = { text, size in
        let lines = text.components(separatedBy: "\n")
        let cols = lines.map { $0.count }.max() ?? 1
        return CGSize(width: CGFloat(max(cols, 1)) * size * 0.6,
                      height: CGFloat(max(lines.count, 1)) * (size + 4))
    }

    private func parse(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> Flowchart {
        guard let chart = DippinParser.parse(s) else {
            XCTFail("expected a parse", file: file, line: line)
            return Flowchart(direction: .topDown, nodes: [], edges: [])
        }
        return chart
    }

    private func node(_ chart: Flowchart, _ id: String,
                      file: StaticString = #filePath, line: UInt = #line) -> Flowchart.Node {
        guard let n = chart.nodes.first(where: { $0.id == id }) else {
            XCTFail("missing node \(id)", file: file, line: line)
            return Flowchart.Node(id: id, label: id, shape: .rectangle)
        }
        return n
    }

    private func edge(_ chart: Flowchart, _ from: String, _ to: String) -> Flowchart.Edge? {
        chart.edges.first { $0.from == from && $0.to == to }
    }

    // MARK: the README hello.dip

    private let hello = """
    workflow Hello
      goal: "Ask the user a question and respond"
      start: Ask
      exit: Respond

      human Ask
        mode: freeform

      agent Respond
        model: claude-sonnet-4-6
        provider: anthropic
        prompt:
          The user said something. Respond helpfully.

      edges
        Ask -> Respond
    """

    func testHelloWorkflow() {
        let chart = parse(hello)
        XCTAssertEqual(chart.direction, .topDown)
        XCTAssertEqual(chart.nodes.map(\.id), ["Ask", "Respond"])
        XCTAssertEqual(node(chart, "Ask").shape, .stadium)         // human
        XCTAssertEqual(node(chart, "Respond").shape, .rectangle)   // agent
        // Agent subtitle carries the model on a second line.
        XCTAssertTrue(node(chart, "Respond").label.contains("Respond"))
        XCTAssertTrue(node(chart, "Respond").label.contains("claude-sonnet-4-6"))
        XCTAssertEqual(chart.edges.count, 1)
        XCTAssertEqual(chart.edges[0].from, "Ask")
        XCTAssertEqual(chart.edges[0].to, "Respond")
        XCTAssertTrue(chart.edges[0].hasArrow)
    }

    func testMultilinePromptDoesNotLeak() {
        // The indented prompt body contains `->` and the word `agent`; neither
        // may become an edge or a node.
        let chart = parse(hello)
        XCTAssertEqual(chart.nodes.count, 2)
        XCTAssertEqual(chart.edges.count, 1)
        XCTAssertFalse(chart.nodes.contains { $0.id.contains("said") })
    }

    // MARK: a richer workflow — every kind, when, fan, restart, subgraph

    private let rich = """
    workflow Triage
      goal: "Investigate, fan out, loop until resolved"
      start: Intake
      exit: Report

      defaults
        model: claude-sonnet-4-6
        provider: anthropic

      human Intake
        mode: freeform

      agent Classify
        model: claude-opus-4-6
        prompt:
          Classify severity.

      conditional Severe
        label: "Severe?"

      parallel ReviewFan -> Logs, Metrics, Traces
      agent Logs
        prompt:
          Read logs.
      agent Metrics
        prompt:
          Read metrics.
      agent Traces
        prompt:
          Read traces.
      fan_in ReviewJoin <- Logs, Metrics, Traces

      tool Remediate
        timeout: 60s
        command:
          #!/bin/sh
          ./remediate.sh

      subgraph Postmortem
        ref: postmortem/write_up.dip

      manager_loop Supervise
        subgraph_ref: watch.dip

      agent Report
        prompt:
          Summarize.

      edges
        Intake -> Classify
        Classify -> Severe
        Severe -> ReviewFan when ctx.severity == "high"
        Severe -> Remediate when ctx.severity == "low"
        ReviewJoin -> Remediate
        Remediate -> Classify when ctx.outcome == "fail" restart: true
        Remediate -> Postmortem when ctx.outcome == "success"
        Postmortem -> Supervise
        Supervise -> Report
    """

    func testEveryKindMapsToADistinctShape() {
        let chart = parse(rich)
        XCTAssertEqual(node(chart, "Intake").shape, .stadium)       // human
        XCTAssertEqual(node(chart, "Classify").shape, .rectangle)   // agent
        XCTAssertEqual(node(chart, "Severe").shape, .diamond)       // conditional
        XCTAssertEqual(node(chart, "ReviewFan").shape, .hexagon)    // parallel
        XCTAssertEqual(node(chart, "ReviewJoin").shape, .circle)    // fan_in
        XCTAssertEqual(node(chart, "Remediate").shape, .cylinder)   // tool
        XCTAssertEqual(node(chart, "Postmortem").shape, .subroutine) // subgraph
        XCTAssertEqual(node(chart, "Supervise").shape, .rounded)    // manager_loop

        // All eight kinds resolve to eight distinct shapes.
        let kindShapes: Set<Flowchart.NodeShape> = [
            node(chart, "Intake").shape, node(chart, "Classify").shape,
            node(chart, "Severe").shape, node(chart, "ReviewFan").shape,
            node(chart, "ReviewJoin").shape, node(chart, "Remediate").shape,
            node(chart, "Postmortem").shape, node(chart, "Supervise").shape,
        ]
        XCTAssertEqual(kindShapes.count, 8)
    }

    func testWhenConditionBecomesEdgeLabel() {
        let chart = parse(rich)
        XCTAssertEqual(edge(chart, "Severe", "ReviewFan")?.label, "ctx.severity == high")
        XCTAssertEqual(edge(chart, "Severe", "Remediate")?.label, "ctx.severity == low")
        XCTAssertEqual(edge(chart, "Remediate", "Postmortem")?.label, "ctx.outcome == success")
        // A plain edge has no label.
        XCTAssertNil(edge(chart, "Intake", "Classify")?.label)
    }

    func testParallelFanOutAndFanInEdges() {
        let chart = parse(rich)
        // parallel ReviewFan -> Logs, Metrics, Traces
        XCTAssertNotNil(edge(chart, "ReviewFan", "Logs"))
        XCTAssertNotNil(edge(chart, "ReviewFan", "Metrics"))
        XCTAssertNotNil(edge(chart, "ReviewFan", "Traces"))
        // fan_in ReviewJoin <- Logs, Metrics, Traces
        XCTAssertNotNil(edge(chart, "Logs", "ReviewJoin"))
        XCTAssertNotNil(edge(chart, "Metrics", "ReviewJoin"))
        XCTAssertNotNil(edge(chart, "Traces", "ReviewJoin"))
    }

    func testRestartIsABackEdge() {
        let chart = parse(rich)
        // The restart edge points from a later node back to an earlier one,
        // forming the loop; its `when` condition still labels it.
        let back = edge(chart, "Remediate", "Classify")
        XCTAssertNotNil(back)
        XCTAssertEqual(back?.label, "ctx.outcome == fail")
    }

    func testBareRestartIsLabelledRestart() {
        let chart = parse("""
        workflow Loop
          start: A
          exit: B
          agent A
            prompt:
              go
          agent B
            prompt:
              done
          edges
            A -> B
            B -> A restart: true
        """)
        XCTAssertEqual(edge(chart, "B", "A")?.label, "restart")
    }

    func testExplicitLabelWinsOverWhen() {
        let chart = parse("""
        workflow L
          start: A
          exit: B
          agent A
            prompt:
              go
          agent B
            prompt:
              done
          edges
            A -> B when ctx.x == "y" label: "happy path"
        """)
        XCTAssertEqual(edge(chart, "A", "B")?.label, "happy path")
    }

    func testSubgraphSubtitleIsRefBasename() {
        let chart = parse(rich)
        XCTAssertTrue(node(chart, "Postmortem").label.contains("write_up.dip"))
        XCTAssertFalse(node(chart, "Postmortem").label.contains("postmortem/"))
    }

    func testDefaultModelSubtitleForAgentWithoutExplicitModel() {
        // Report has no explicit model → the defaults block model is its subtitle.
        let chart = parse(rich)
        XCTAssertTrue(node(chart, "Report").label.contains("claude-sonnet-4-6"))
    }

    func testDipVersionHeaderTolerated() {
        let chart = parse("""
        dip 2
        workflow V
          start: A
          exit: A
          agent A
            prompt:
              go
          edges
            A -> A
        """)
        XCTAssertEqual(chart.nodes.map(\.id), ["A"])
    }

    // MARK: adversarial — nil is fine, crashing/hanging is not

    func testAdversarialNeverCrashes() {
        let cases: [String] = [
            "", " ", "\n\n", "workflow", "workflow X", "workflow X\n",
            "not dippin at all", "flowchart TD\n A --> B",
            "graph LR\n A --> B",
            "workflow X\n  edges\n    -> ", "workflow X\n  edges\n    A ->",
            "workflow X\n  edges\n    -> B",
            "workflow X\n  agent",
            "workflow X\n  agent A\n    prompt:\n", // block opens then EOF
            "workflow X\n  parallel P ->",
            "workflow X\n  fan_in F <-",
            "workflow X\n  conditional",
            "workflow X\n\tagent\tA\n\t\tprompt:\n\t\t\t-> not an edge",
            "workflow X\n  edges\n    else -> Z",   // section default, no real edge
            "workflow\nworkflow\nworkflow",
            "＜＞〔〕 🧜‍♀️",
        ]
        for s in cases {
            let chart = DippinParser.parse(s)
            if let chart { XCTAssertGreaterThanOrEqual(chart.nodes.count, 0) }
        }
    }

    func testDeeplyIndentedInputDoesNotHang() {
        let deep = "workflow X\n" + (0..<5_000).map {
            String(repeating: " ", count: $0 % 40) + "agent N\($0)\n" +
            String(repeating: " ", count: ($0 % 40) + 2) + "prompt:"
        }.joined(separator: "\n")
        _ = DippinParser.parse(deep)   // returns (no crash/hang)
    }

    func testHugeInputReturnsNil() {
        let over = String(repeating: "x", count: 200_000)
        XCTAssertNil(DippinParser.parse("workflow X\n  agent \(over)"))
    }

    func testEdgeCapHonored() {
        // A fan that blows past maxEdges returns nil.
        let targets = (0..<600).map { "N\($0)" }.joined(separator: ", ")
        let src = "workflow X\n  parallel P -> \(targets)\n"
        XCTAssertNil(DippinParser.parse(src))
    }

    // MARK: full pipeline — parse → layout → scene lints clean

    func testParseLayoutSceneLintsClean() {
        let chart = parse(rich)
        let scene = DiagramScene.lower(.flowchart(chart), measure: measure)
        XCTAssertGreaterThan(scene.size.width, 0)
        let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "layout errors: \(errors)")
    }
}
