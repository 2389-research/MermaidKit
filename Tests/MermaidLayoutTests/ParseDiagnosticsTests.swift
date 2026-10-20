import XCTest
@testable import MermaidLayout

final class ParseDiagnosticsTests: XCTestCase {

    func testValidSourceHasNoDiagnostics() {
        XCTAssertEqual(MermaidParser.diagnose("flowchart TD\n A --> B"), [])
        XCTAssertEqual(MermaidParser.diagnose("pie\n \"a\": 1"), [])
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
}
