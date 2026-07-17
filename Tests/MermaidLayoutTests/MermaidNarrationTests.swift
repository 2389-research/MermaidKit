import XCTest
@testable import MermaidLayout

/// `MermaidAltText.narrate` — the traversal walkthrough. Asserts on phrasing
/// fragments (not exact strings) so wording can evolve, and verifies the
/// fallback + bounded-length contracts.
final class MermaidNarrationTests: XCTestCase {

    private func diagram(_ s: String) throws -> MermaidDiagram {
        try XCTUnwrap(MermaidParser.parse(s), "failed to parse:\n\(s)")
    }

    func testFlowchartNarrationWalksDecisions() throws {
        let d = try diagram("""
        flowchart TD
          A[Start] --> B{Ready?}
          B -->|yes| C[(Save)]
          B -->|no| A
        """)
        let n = MermaidAltText.narrate(d)
        XCTAssertTrue(n.contains("The flowchart begins at"), n)
        XCTAssertTrue(n.contains("the decision “Ready?”"), n)
        XCTAssertTrue(n.contains("branches"), n)
        XCTAssertTrue(n.contains("on “yes”"), n)
        XCTAssertTrue(n.contains("the datastore “Save”"), n)
        // Richer than the one-line summary.
        XCTAssertNotEqual(n, MermaidAltText.describe(d))
    }

    func testStateNarrationReadsFromInitial() throws {
        let d = try diagram("""
        stateDiagram-v2
          [*] --> Idle
          Idle --> Running: start
          Running --> [*]: stop
        """)
        let n = MermaidAltText.narrate(d)
        XCTAssertTrue(n.contains("The state machine starts in the initial state"), n)
        XCTAssertTrue(n.contains("the state “Idle”"), n)
        XCTAssertTrue(n.contains("on “start”"), n)
        XCTAssertTrue(n.contains("the final state"), n)
    }

    func testERNarrationSpellsOutAttributesAndCardinality() throws {
        let d = try diagram("""
        erDiagram
          CUSTOMER ||--o{ ORDER : places
          CUSTOMER {
            string name
            int id
          }
        """)
        let n = MermaidAltText.narrate(d)
        XCTAssertTrue(n.contains("“CUSTOMER” has"), n)
        XCTAssertTrue(n.contains("name (string)"), n)
        XCTAssertTrue(n.contains("“CUSTOMER” relates to “ORDER”"), n)
        XCTAssertTrue(n.contains("one to zero or more"), n)
        XCTAssertTrue(n.contains("places"), n)
    }

    func testSequenceNarrationReplaysMessages() throws {
        let d = try diagram("""
        sequenceDiagram
          Alice->>Bob: Hello
          Bob-->>Alice: Hi there
        """)
        let n = MermaidAltText.narrate(d)
        XCTAssertTrue(n.contains("A sequence between"), n)
        XCTAssertTrue(n.contains("1. “Alice” calls “Bob”: “Hello”"), n)
        XCTAssertTrue(n.contains("2. “Bob” replies to “Alice”: “Hi there”"), n)
    }

    func testFallsBackToSummaryForNonTraversableTypes() throws {
        let d = try diagram("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85")
        XCTAssertEqual(MermaidAltText.narrate(d), MermaidAltText.describe(d))
    }

    func testNarrateSourceLeadsWithAccessibilityText() throws {
        let src = """
        flowchart LR
          accTitle: Deploy flow
          accDescr: How a change ships
          A[Commit] --> B[CI] --> C[Deploy]
        """
        let n = try XCTUnwrap(MermaidAltText.narrate(source: src))
        XCTAssertTrue(n.hasPrefix("Deploy flow."), n)
        XCTAssertTrue(n.contains("How a change ships."), n)
        XCTAssertTrue(n.contains("The flowchart begins at"), n)
    }

    func testNarrationIsBoundedAndSafe() throws {
        var lines = ["flowchart TD"]
        for i in 0..<200 { lines.append("N\(i) --> N\(i + 1)") }
        let d = try diagram(lines.joined(separator: "\n"))
        let n = MermaidAltText.narrate(d)
        XCTAssertTrue(n.contains("…and"), "should truncate: \(n.prefix(120))")
        XCTAssertLessThan(n.count, 4000, "narration should stay bounded")
    }
}
