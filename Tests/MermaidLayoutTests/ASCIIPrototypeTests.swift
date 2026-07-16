import XCTest
@testable import MermaidLayout

/// POC demonstration: render three flowcharts to ASCII/Unicode boxes and print
/// the result to stdout. Run: `swift test --filter ASCIIPrototype 2>&1`.
final class ASCIIPrototypeTests: XCTestCase {

    private func show(_ title: String, _ source: String) {
        print("\n===== \(title) =====")
        print("--- source ---")
        print(source)
        print("--- ascii ---")
        if let out = ASCIIRenderer.asciiRenderFlowchart(source) {
            print(out)
        } else {
            print("(nil — not a flowchart or failed to parse)")
        }
        print("===== end \(title) =====\n")
    }

    func testLinearTopDown() {
        show("linear TD", """
        flowchart TD
        A[Start] --> B{Choice}
        B -->|yes| C[Do it]
        B -->|no| D[Skip]
        """)
    }

    func testLeftRight() {
        show("LR chain", """
        flowchart LR
        A[Ingest] --> B[Parse]
        B --> C[Layout]
        C --> D[Render]
        """)
    }

    func testBranchMerge() {
        show("branch/merge", """
        flowchart TD
        A[Request] --> B{Valid?}
        B -->|yes| C[Process]
        B -->|no| D[Reject]
        C --> E[Respond]
        D --> E[Respond]
        """)
    }

    func testNonFlowchartReturnsNil() {
        XCTAssertNil(ASCIIRenderer.asciiRenderFlowchart("pie title Pets\n\"Dogs\": 3\n\"Cats\": 2"))
    }
}
