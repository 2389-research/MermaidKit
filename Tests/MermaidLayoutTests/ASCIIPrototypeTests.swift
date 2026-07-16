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

    // MARK: shape-aware rendering

    /// A decision `{}` node must be visibly NOT a rectangle. It uses angled
    /// corner slashes and chevron sides; a plain `[]` node next to it keeps the
    /// square box glyphs. Asserting both distinguishes shape from rectangle.
    func testDecisionNodeRendersDistinctFromRectangle() {
        let out = ASCIIRenderer.asciiRenderFlowchart("""
        flowchart TD
        A[Start] --> B{Choice}
        """)
        let ascii = try! XCTUnwrap(out)
        // Diamond markers present.
        XCTAssertTrue(ascii.contains("╱") && ascii.contains("╲"), "decision node should draw sloped corners")
        XCTAssertTrue(ascii.contains("<") && ascii.contains(">"), "decision node should draw chevron sides")
        // The rectangle node still keeps square corners.
        XCTAssertTrue(ascii.contains("┌") && ascii.contains("┘"), "rectangle node keeps square corners")
    }

    func testShapeGlyphsRounded_Stadium_Circle() {
        let out = ASCIIRenderer.asciiRenderFlowchart("""
        flowchart LR
        A(Rounded) --> B([Stadium])
        B --> C((Circle))
        """)
        let ascii = try! XCTUnwrap(out)
        XCTAssertTrue(ascii.contains("╭") && ascii.contains("╯"), "rounded corners present")
        XCTAssertTrue(ascii.contains("(") && ascii.contains(")"), "stadium/circle side caps present")
        XCTAssertTrue(ascii.contains("◜") || ascii.contains("◞"), "circle arc corners present")
    }

    // MARK: truecolor (Tier 4)

    func testTruecolorEmitsPaletteEscapes() {
        let out = ASCIIRenderer.asciiRenderFlowchart("""
        flowchart TD
        A[Start] --> B{Choice}
        B -->|yes| C(Go)
        """, color: .truecolor)
        let ascii = try! XCTUnwrap(out)
        XCTAssertTrue(ascii.contains("\u{1B}[38;2;57;214;197m"), "seafoam node border")
        XCTAssertTrue(ascii.contains("\u{1B}[38;2;201;182;255m"), "lavender decision node")
        XCTAssertTrue(ascii.contains("\u{1B}[38;2;255;143;163m"), "coral arrowhead")
        XCTAssertTrue(ascii.contains("\u{1B}[0m"), "runs reset")
    }

    func testPlainModeHasNoEscapes() {
        let out = ASCIIRenderer.asciiRenderFlowchart("flowchart TD\nA[Start] --> B{Choice}", color: .plain)
        XCTAssertFalse(try! XCTUnwrap(out).contains("\u{1B}"), "plain mode emits no ANSI escapes")
    }

    // MARK: capability detection

    func testCapabilityLadder() {
        let kitty = TerminalEnvironment(term: "xterm-kitty", colorterm: "truecolor", stdoutIsTTY: true)
        XCTAssertEqual(TerminalCapabilities.autoMode(kitty), .kitty)

        let ghostty = TerminalEnvironment(colorterm: "truecolor", termProgram: "ghostty")
        XCTAssertTrue(TerminalCapabilities.supportsKittyGraphics(ghostty))

        let truecolorOnly = TerminalEnvironment(term: "xterm-256color", colorterm: "truecolor")
        XCTAssertEqual(TerminalCapabilities.autoMode(truecolorOnly), .coloredBox)

        let bare = TerminalEnvironment(term: "xterm-256color", colorterm: nil)
        XCTAssertEqual(TerminalCapabilities.autoMode(bare), .plainBox)
    }

    func testColorAutoNeedsTTYAndTruecolor() {
        let ttyTrue = TerminalEnvironment(colorterm: "24bit", stdoutIsTTY: true)
        XCTAssertTrue(TerminalCapabilities.useColor(.auto, ttyTrue))
        let notTTY = TerminalEnvironment(colorterm: "truecolor", stdoutIsTTY: false)
        XCTAssertFalse(TerminalCapabilities.useColor(.auto, notTTY))
        XCTAssertTrue(TerminalCapabilities.useColor(.always, notTTY))
        XCTAssertFalse(TerminalCapabilities.useColor(.never, ttyTrue))
    }

    // MARK: Kitty graphics transport (Tier 1)

    func testKittyEncodingChunks() {
        // Force multiple chunks with a tiny chunk size.
        let bytes = Data((0..<300).map { UInt8($0 & 0xFF) })
        let stream = KittyGraphics.encode(pngData: bytes, chunkSize: 64)
        XCTAssertTrue(stream.hasPrefix("\u{1B}_Gf=100,a=T,m=1;"), "first chunk carries f/a control + m=1")
        XCTAssertTrue(stream.hasSuffix("\u{1B}\\"), "stream ends with a chunk terminator")
        // Exactly one final chunk.
        XCTAssertEqual(stream.components(separatedBy: "m=0;").count - 1, 1)
    }

    func testKittyEncodingSingleChunk() {
        let stream = KittyGraphics.encode(pngData: Data([1, 2, 3]), chunkSize: 4096)
        XCTAssertTrue(stream.hasPrefix("\u{1B}_Gf=100,a=T,m=0;"), "single chunk is first and last")
        XCTAssertTrue(stream.hasSuffix("\u{1B}\\"))
    }
}
