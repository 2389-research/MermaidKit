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
}
