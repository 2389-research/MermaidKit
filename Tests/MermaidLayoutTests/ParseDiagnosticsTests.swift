import XCTest
@testable import MermaidLayout

final class ParseDiagnosticsTests: XCTestCase {

    func testValidSourceHasNoDiagnostics() {
        XCTAssertEqual(MermaidParser.diagnose("flowchart TD\n A --> B"), [])
        XCTAssertEqual(MermaidParser.diagnose("pie\n \"a\": 1"), [])
    }

    /// A flowchart with nothing to draw parses as an empty chart, as in
    /// mermaid (a header alone, or only comments and `classDef`, `class`,
    /// `linkStyle` or `click` lines), and `diagnose` notes it, so a host can still tell. (A
    /// `style X` line names node `X`, which mermaid draws.) One whose
    /// statements couldn't be read still doesn't parse.
    func testAFlowchartWithNothingToDrawIsEmpty() throws {
        for source in ["graph LR;", "flowchart TD\n  %% only a comment", "flowchart LR\n  click A callback",
                       "flowchart LR\n  classDef hot fill:#f96\n  class A hot"] {
            guard case .flowchart(let chart)? = MermaidParser.parse(source) else {
                return XCTFail("should parse empty: \(source.debugDescription)")
            }
            XCTAssertEqual(chart.nodes.count, 0, source)
            let notes = MermaidParser.diagnose(source)
            XCTAssertEqual(notes.map(\.severity), [.note], source)
            XCTAssertEqual(notes.first?.line, 1, source)
            XCTAssertTrue(notes.first?.message.contains("nothing to draw") == true, "\(notes)")
        }
        guard case .flowchart(let lr)? = MermaidParser.parse("graph LR;") else { return XCTFail() }
        XCTAssertEqual(lr.direction, .leftRight)
        XCTAssertNil(MermaidParser.parse("flowchart LR\n  -->"), "unreadable isn't empty")
        // Nor is a header mermaid doesn't read (it rejects each of these).
        for header in ["graphical", "flowchart LR junk", "flowchart QQ"] {
            XCTAssertNil(MermaidParser.parse(header), header)
        }
        XCTAssertNotNil(MermaidParser.parse("flowchart-elk LR"))
        // A top-level `direction` is noted but loses nothing (mermaid draws
        // these); an empty box is something to draw.
        for source in ["flowchart LR\n  direction TB", "flowchart LR\n  subgraph S\n  end\n  direction TB"] {
            guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return XCTFail(source) }
            XCTAssertEqual(chart.direction, .leftRight, source)
        }
        // A header is split on any whitespace, as mermaid splits it.
        guard case .flowchart(let tabbed)? = MermaidParser.parse("flowchart\tLR\n  A --> B") else { return XCTFail("tab") }
        XCTAssertEqual(tabbed.direction, .leftRight)
        XCTAssertEqual(MermaidParser.diagnose("flowchart\tLR\n  A --> B"), [])
        XCTAssertNotNil(MermaidParser.parse("graph"))
        // With content it still draws, and says what it didn't read.
        XCTAssertEqual(MermaidParser.diagnose("flowchart LR junk\n  A --> B").map(\.line), [1])
        // An empty box is something to draw.
        XCTAssertEqual(MermaidParser.diagnose("flowchart LR\n  subgraph S [Storage]\n  end"), [])
        XCTAssertEqual(MermaidParser.diagnose("flowchart LR\n  -->").first?.severity, .error)
        XCTAssertEqual(MermaidAltText.describe(source: "graph LR;"), "Empty flowchart.")
        XCTAssertEqual(MermaidAltText.describe(source: "flowchart LR\n  subgraph S [Storage]\n  end"),
                       "Flowchart with no nodes, only 1 empty group: Storage.")
        XCTAssertEqual(MermaidAltText.describe(source: "flowchart LR\n  subgraph A\n  end\n  subgraph B\n  end\n  A --> B"),
                       "Flowchart with no nodes, only 2 empty groups and 1 connection: A, B.")
        // A box is content: it draws, and what couldn't be read is noted, as
        // for a chart with nodes.
        let boxed = "flowchart LR\n  subgraph S\n  end\n  linkStyle 0 stroke:red"
        XCTAssertNotNil(MermaidParser.parse(boxed))
        XCTAssertEqual(MermaidParser.diagnose(boxed).map(\.line), [4])
    }

    /// A `linkStyle` index must name a link read before it, as in mermaid,
    /// which rejects the chart otherwise. MermaidKit draws the rest and notes
    /// it; a chart with nothing else in it doesn't parse.
    func testALinkStyleNamingNoLinkIsNoted() throws {
        for source in ["flowchart LR\n  linkStyle 0 stroke:red\n  A --> B", "flowchart LR\n  A --> B\n  linkStyle 1 stroke:red",
                       "flowchart LR\n  A --> B\n  linkStyle 0,1 stroke:red", "flowchart LR\n  A --> B\n  linkStyle\t1 stroke:red"] {
            XCTAssertNotNil(MermaidParser.parse(source), source)
            let notes = MermaidParser.diagnose(source)
            XCTAssertEqual(notes.map(\.severity), [.note], source)
            XCTAssertTrue(notes.first?.message.contains("names no link") == true, "\(notes)")
        }
        for source in ["flowchart LR\n  A --> B\n  linkStyle 0 stroke:red", "flowchart LR\n  A --> B & C\n  linkStyle 1 stroke:red",
                       "flowchart LR\n  linkStyle default stroke:red", "flowchart LR\n  A --> B\n  linkStyle 0 interpolate basis"] {
            XCTAssertEqual(MermaidParser.diagnose(source).filter { $0.message.contains("link") }, [], source)
        }
        XCTAssertNil(MermaidParser.parse("graph TD\n  linkStyle 0 stroke:red"))
        // A target that isn't a link's index names none either (mermaid
        // rejects the chart).
        for target in ["nope", "-1", "99999999999999999999", "0,x", "0,"] {
            let source = "flowchart LR\n  A --> B\n  linkStyle \(target) stroke:red"
            XCTAssertEqual(MermaidParser.diagnose(source).map(\.severity), [.note], source)
            XCTAssertNil(MermaidParser.parse("graph TD\n  linkStyle \(target) stroke:red"), target)
        }
    }

    func testEmptySource() {
        let d = MermaidParser.diagnose("   \n \n")
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d[0].severity, .error)
        XCTAssertTrue(d[0].message.contains("empty"))
    }

    func testTypoSuggestsNearestHeader() throws {
        let d = try XCTUnwrap(MermaidParser.diagnose("flowchar TD\n A --> B").first)
        XCTAssertEqual(d.line, 1)
        XCTAssertTrue(d.message.contains("did you mean 'flowchart'"), d.message)

        let d2 = try XCTUnwrap(MermaidParser.diagnose("sequenceDigram\n A->>B: hi").first)
        XCTAssertTrue(d2.message.contains("did you mean 'sequenceDiagram'"), d2.message)
    }

    func testUnknownDialectWithoutNearMissGetsPlainError() throws {
        let d = try XCTUnwrap(MermaidParser.diagnose("nonesuchDiagram\n a --> b").first)
        XCTAssertTrue(d.message.contains("unknown diagram type 'nonesuchDiagram'"), d.message)
        XCTAssertFalse(d.message.contains("did you mean"), "a wild string must not be 'corrected'")
    }

    func testHeaderAfterCommentsGetsCorrectLineNumber() throws {
        let d = try XCTUnwrap(MermaidParser.diagnose("%% a comment\n\nflowchar TD").first)
        XCTAssertEqual(d.line, 3)
    }

    func testOversizeSourceNamesTheCap() throws {
        let big = "flowchart TD\n" + String(repeating: " a --> b\n", count: 10_000)
        let d = try XCTUnwrap(MermaidParser.diagnose(big).first)
        XCTAssertTrue(d.message.contains("\(MermaidParser.maxTextSize)"), d.message)
    }

    func testEdgeCapNamesTheCap() throws {
        var flow = "flowchart TD\n"
        for i in 0..<600 { flow += " n\(i) --> n\(i + 1)\n" }
        let d = try XCTUnwrap(MermaidParser.diagnose(flow).first)
        XCTAssertTrue(d.message.contains("\(MermaidParser.maxEdges)"), d.message)
        XCTAssertTrue(d.message.contains("601") || d.message.contains("600"), d.message)
    }

    func testRecognizedHeaderEmptyBody() throws {
        let d = try XCTUnwrap(MermaidParser.diagnose("gitGraph\n \n").first)
        XCTAssertTrue(d.message.contains("recognized 'gitGraph'"), d.message)
    }

    // MARK: Notes on a flowchart that parses

    /// A statement the flowchart parser can't read is left out of the diagram,
    /// and `diagnose` says so at its line, so a host can tell a diagram that
    /// rendered whole from one with parts missing.
    func testSetAsideStatementsAreNoted() {
        let source = "flowchart LR\n  A --> B\n  this is not mermaid\n  end\n  B --> C"
        XCTAssertNotNil(MermaidParser.parse(source))
        let notes = MermaidParser.diagnose(source)
        XCTAssertEqual(notes.map(\.severity), [.note, .note])
        XCTAssertEqual(notes.map(\.line), [3, 4])
        XCTAssertTrue(notes[0].message.contains("this is not mermaid"), notes[0].message)
        XCTAssertTrue(notes[1].message.contains("end"), notes[1].message)
    }

    /// Directions the parser doesn't know fall back, and are noted.
    func testUnknownDirectionsAreNoted() {
        let notes = MermaidParser.diagnose("flowchart XY\n  A --> B\n  subgraph S\n    direction QQ\n    C\n  end")
        XCTAssertEqual(notes.map(\.line), [1, 4])
        XCTAssertTrue(notes[0].message.contains("XY"), notes[0].message)
        XCTAssertTrue(notes[1].message.contains("QQ"), notes[1].message)
    }

    /// Styling is ignored on purpose (the theme draws every node alike), so
    /// it isn't noted.
    func testIgnoredStylingIsNotNoted() {
        XCTAssertEqual(MermaidParser.diagnose("""
            flowchart LR
              classDef hot fill:#f96
              A --> B:::hot
              class B hot
              style A fill:#fff
              linkStyle 0 stroke:red
              click A "https://example.com"
            """), [])
    }

    /// Lines keep their numbers in the source past front matter, `acc…`
    /// statements and `;`-joined statements.
    func testNoteLinesCountTheWholeSource() {
        let source = "---\ntitle: T\n---\nflowchart LR\n  accTitle: a title\n  A --> B; ??? nope; B --> C\n  !!!"
        XCTAssertEqual(MermaidParser.diagnose(source).map(\.line), [6, 7])
        XCTAssertEqual(MermaidParser.diagnose("flowchart LR\n  A --> B; %% a comment"), [])
    }

    /// A line is found by its place in the source, not its text: a body line
    /// that repeats a line of an `accDescr` block is noted where it is.
    func testNoteLinesSurviveRepeatedText() {
        let source = "flowchart LR\n  accDescr {\n  ???\n  }\n  ???\n  A --> B"
        XCTAssertEqual(MermaidParser.diagnose(source).map(\.line), [5])
    }

    /// An `&` fan endpoint that isn't a node is left out, and noted.
    func testUnreadFanEndpointsAreNoted() {
        let notes = MermaidParser.diagnose("flowchart LR\n  A & ??? --> B")
        XCTAssertEqual(notes.map(\.line), [2])
        XCTAssertTrue(notes.first?.message.contains("???") == true, notes.first?.message ?? "")
    }

    /// A top-level `direction` changes nothing (the header sets the flow), as
    /// in mermaid, and says so; an unknown one is noted as unknown.
    func testTopLevelDirectionsAreNoted() {
        let notes = MermaidParser.diagnose("flowchart TD\n  direction LR\n  direction QQ\n  A --> B")
        XCTAssertEqual(notes.map(\.line), [2, 3])
        guard notes.count == 2 else { return }
        XCTAssertTrue(notes[0].message.contains("no effect"), notes[0].message)
        XCTAssertTrue(notes[1].message.contains("unknown direction 'QQ'"), notes[1].message)
    }
}
