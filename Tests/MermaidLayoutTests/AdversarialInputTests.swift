import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The parser and layout engines must never crash, hang, or trap on
/// arbitrary input — a library invites hostile/fuzzed/malformed sources.
/// Every case here runs the FULL pipeline (parse → layout → scene → lint)
/// and asserts only that it returns (nil is always acceptable; crashing is
/// not).
final class AdversarialInputTests: XCTestCase {

    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    /// Runs the whole pipeline; the assertion is simply "we got here".
    private func pipeline(_ source: String, _ label: String) {
        guard let diagram = MermaidParser.parse(source) else { return }
        let scene = DiagramScene.lower(diagram, measure: measure)
        _ = DiagramLayoutLinter.lint(scene)
        XCTAssertGreaterThanOrEqual(scene.size.width, 0, label)
    }

    func testEmptyAndWhitespace() {
        for s in ["", " ", "\n", "\n\n\n", "\t\t", "   \n   \n", "\r\n\r\n"] {
            pipeline(s, "whitespace")
        }
    }

    func testHeadersWithNoBody() {
        for header in ["flowchart TD", "sequenceDiagram", "pie", "classDiagram",
                       "erDiagram", "stateDiagram-v2", "gantt", "timeline",
                       "mindmap", "journey", "quadrantChart", "packet-beta",
                       "xychart-beta", "kanban", "radar-beta", "treemap-beta",
                       "gitGraph", "sankey-beta", "requirementDiagram", "zenuml",
                       "C4Context", "architecture-beta", "block-beta"] {
            pipeline(header, header)
            pipeline(header + "\n", header)
            pipeline(header + "\n\n\n", header)
        }
    }

    /// Nonsense bodies (and half-written node syntax) under real headers: the
    /// pipeline returns, whatever it makes of them.
    func testGarbageBodies() {
        let garbage = [
            "{{{{{{{{", "))))((((", "-->", "--> --> -->", ":::::",
            "\u{0}\u{1}\u{2}", "🧜‍♀️🧜‍♀️🧜‍♀️", "＜＞〔〕", "علامة تجريبية",
            "a\u{202E}b", String(repeating: "|", count: 500),
            // Node-token syntax: shape data, doubled and slanted brackets, ids
            // that are all separators.
            "A@{", "A@{}", "A@{ shape: }", "A@{ shape: diam, label: \"unterminated }",
            "A@{ , , : , }", "A{{", "A}}", "A[[x]", "A[/", "A[/x\\", "A>", "A>x] & B>y] & ]]] & C", "a@ --- @b --- @", "x@x@x--x@x", "@--o@", "< < <--- o--o x", "o--> --> -->x", "] & ) & }","-.-.", "a-.-.b",
            "a--b.c--d", "a.-b", ".a --> -b",
            // Statements, entities and tags: lone and doubled `;`, entities
            // cut short, out of range or enormous, tags left open.
            ";", ";;;;", "A;B;;C", "; --> ;", "A[\";\"];", "A[\"#quot\"]", "A[\"&#;\"]", "A[\"&#x;\"]",
            "A[\"&#xFFFFFFF;\"]", "A[\"#99999999;\"]", "A[\"&#55296;\"]",
            "A[\"#" + String(repeating: "a", count: 200) + ";\"]",
            "A[\"<b\"]", "A[\"</b>\"]", "A[\"<span <b>>\"]", "A[\"<<b>>x<</b>>\"]",
            // Link tokens: heads, strokes and lengths, alone, mismatched or
            // unfinished.
            "A --o", "o--o", "x--x", "A o--x B", "A <--o B", "A <~~~> B", "A ~~ B", "~~~~~~",
            "A ==", "A === ", "A ==o==o B", "A -.", "A -..- B -...-x C", "A -- o --o B",
            "A --ob", "o --> o --> o", "x x--x x", "A -- x --x", "A -. .-> B", "A == ==> B",
        ]
        for header in ["flowchart TD", "sequenceDiagram", "erDiagram", "gantt",
                       "sankey-beta", "xychart-beta", "gitGraph", "mindmap"] {
            for g in garbage { pipeline(header + "\n" + g, "\(header)+garbage") }
        }
    }

    func testVeryLongSingleLine() {
        let longLabel = String(repeating: "x", count: 100_000)
        pipeline("flowchart TD\n A[\(longLabel)] --> B", "100k label")
        pipeline("pie\n \"\(longLabel)\": 1", "100k pie label")
    }

    func testOversizedInputsRejected() {
        // Past mermaid.js-style caps (maxEdges / maxTextSize) the parser returns
        // nil BEFORE any layout runs — the caller never feeds the super-linear
        // layout, so `nil` is the whole guarantee. (No wall-clock assertion:
        // timing in tests is inherently flaky under CI load.)
        var flow = "flowchart TD\n"
        for i in 0..<2_000 { flow += " n\(i) --> n\(i + 1)\n" }
        XCTAssertNil(MermaidParser.parse(flow), "over the edge cap returns nil")

        let huge = "flowchart TD\n" + String(repeating: " a --> b\n", count: 10_000)
        XCTAssertNil(MermaidParser.parse(huge), "over maxTextSize returns nil")
    }

    func testAtCapInputCompletes() {
        var flow = "flowchart TD\n"
        for i in 0..<MermaidParser.maxEdges { flow += " n\(i) --> n\(i + 1)\n" }
        // At the cap the full pipeline runs and produces a valid scene without
        // crashing or trapping; a pathological hang would trip the CI job
        // timeout. (No wall-clock assertion — see testOversizedInputsRejected.)
        pipeline(flow, "at-cap edges")

        // Every link at the longest length honored, and one far past it.
        var long = "flowchart TD\n"
        let link = String(repeating: "-", count: 5_000) + ">"
        for i in 0..<MermaidParser.maxEdges { long += " n\(i) \(i == 0 ? link : "---------->") n\(i + 1)\n" }
        pipeline(long, "at-cap longest links")

        // The same edges on one line, a chain and a fan, each read in one
        // pass over the line (a per-link rescan of the rest was quadratic).
        // Parsing is what's at stake, so only parse.
        let chain = "flowchart LR\n" + (0...MermaidParser.maxEdges).map { "n\($0)" }.joined(separator: " --> ")
        guard case .flowchart(let read)? = MermaidParser.parse(chain) else { return XCTFail("at-cap chain on one line") }
        XCTAssertEqual(read.edges.count, MermaidParser.maxEdges)
        let fan = "flowchart LR\n" + (0..<MermaidParser.maxEdges).map { "n\($0)>\"a & b\"]" }.joined(separator: " & ") + " --> z"
        guard case .flowchart(let fanned)? = MermaidParser.parse(fan) else { return XCTFail("at-cap fan on one line") }
        XCTAssertEqual(fanned.edges.count, MermaidParser.maxEdges)
        XCTAssertEqual(Set(fanned.nodes.filter { $0.id != "z" }.map(\.label)), ["a & b"])

        var sank = "sankey-beta\n"
        for i in 0..<1_000 { sank += "a\(i),b\(i),1\n" }
        pipeline(sank, "1k sankey links")
    }

    func testDeepNesting() {
        // Mindmap indentation depth and state-diagram composite depth.
        var mind = "mindmap\n root\n"
        for depth in 2..<120 {
            mind += String(repeating: " ", count: depth) + "n\(depth)\n"
        }
        pipeline(mind, "deep mindmap")

        var state = "stateDiagram-v2\n"
        for i in 0..<60 { state += String(repeating: " ", count: i) + "state S\(i) {\n" }
        state += String(repeating: "}\n", count: 60)
        pipeline(state, "deep state nesting")
    }

    func testDuplicateAndSelfReferences() {
        pipeline("sankey-beta\nA,A,5\nA,A,5", "sankey self+dup")
        pipeline("flowchart TD\n A --> A\n A --> A", "flowchart self-loop dup")
        pipeline("erDiagram\n A ||--o{ A : self\n A ||--o{ A : self", "er dup self")
        pipeline("classDiagram\n A --|> A", "class self-inherit")
        pipeline("gitGraph\n commit\n merge main", "merge own branch")
    }

    func testHostileNumbers() {
        // The two crashes an external audit reproduced: a non-finite gantt
        // DURATION (the date path was covered; the duration path skipped the
        // sanitizer) and a packet bit index at Int.max (bare Int parse, then
        // `+ 1` overflow in layout). Plus radar's tick count, which drove an
        // unbounded polygon loop.
        pipeline("gantt\n title t\n section s\n T :t1, 2024-01-01, inf", "gantt inf duration")
        pipeline("gantt\n title t\n section s\n T :t1, 2024-01-01, nan", "gantt nan duration")
        pipeline("gantt\n title t\n section s\n T :t1, 2024-01-01, 1e308d", "gantt huge duration")
        pipeline("packet-beta\n9223372036854775807: \"x\"", "packet Int.max bit")
        pipeline("packet-beta\n0-9223372036854775807: \"x\"", "packet Int.max range")
        pipeline("radar-beta\n ticks 500000000\n axis a, b, c\n curve x{1,2,3}", "radar huge ticks")
        pipeline("pie\n \"a\": 1e308\n \"b\": 1e308", "pie 1e308")
        pipeline("pie\n \"a\": -5", "pie negative")
        pipeline("pie\n \"a\": 0\n \"b\": 0", "pie zeros")
        pipeline("xychart-beta\n line [1e308, -1e308, 0]", "xy 1e308")
        pipeline("xychart-beta\n bar [NaN, Infinity]", "xy NaN words")
        pipeline("sankey-beta\nA,B,1e308\nB,C,1e308", "sankey 1e308")
        pipeline("quadrantChart\n P: [5, -3]", "quadrant out of range")
        pipeline("gantt\n title t\n section s\n T :a, 9999-99-99, 1d", "gantt bad date")
    }

    func testCRLFAndMixedLineEndings() {
        pipeline("flowchart TD\r\n A --> B\r\n B --> C", "CRLF flowchart")
        pipeline("gantt\r\n title x\r\n section s\r\n T :t1, 2026-01-01, 1d", "CRLF gantt")
    }

    /// Layout entry points must tolerate hand-built (non-parser) models.
    func testHandBuiltDuplicateSankeyNodes() {
        let diagram = SankeyDiagram(
            nodes: ["A", "A", "B"],
            links: [.init(source: "A", target: "B", value: 1)]
        )
        let layout = DiagramLayoutEngine.layout(diagram, measure: measure)
        XCTAssertGreaterThan(layout.size.width, 0)
    }
}
