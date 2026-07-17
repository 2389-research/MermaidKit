#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// The end-to-end path: Mermaid source → `RenderScene` → SVG, proving the
/// `DiagramTheme.resolved` → `RenderTheme` mapping and the flowchart lowering
/// wire up. This slice is flowchart-only; other types return nil.
final class SVGBridgeTests: XCTestCase {

    private let theme = DiagramTheme(prefersDark: false)

    func testFlowchartSourceRendersSVG() throws {
        let svg = try XCTUnwrap(MermaidRenderer.svg(
            source: "flowchart TD\n A[Start] --> B{Choice}\n B -->|yes| C[(Store)]",
            theme: theme))
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.contains("</svg>"))
        #if canImport(Darwin)
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(),
                      "bridged SVG must be XML-parseable")
        #endif
        // Node fill uses the theme's resolved accent at 6% — a translucent rgba.
        XCTAssertTrue(svg.contains("rgba("))
    }

    func testRenderSceneCanvasMatchesResolvedTheme() throws {
        let scene = try XCTUnwrap(MermaidRenderer.renderScene(
            source: "flowchart LR\n A[One] --> B[Two]", theme: theme))
        XCTAssertEqual(scene.background, theme.resolved.canvas)
        XCTAssertGreaterThan(scene.elements.count, 0)
    }

    func testNonFlowchartReturnsNilThisSlice() {
        // Phase 0b will lower these; for now the bridge declines them.
        let sequence = """
        sequenceDiagram
            Alice->>Bob: Hi
        """
        XCTAssertNil(MermaidRenderer.svg(source: sequence, theme: theme))
        XCTAssertNil(MermaidRenderer.renderScene(source: sequence, theme: theme))
    }

    func testUnparseableReturnsNil() {
        XCTAssertNil(MermaidRenderer.svg(source: "not a diagram", theme: theme))
    }
}
#endif
