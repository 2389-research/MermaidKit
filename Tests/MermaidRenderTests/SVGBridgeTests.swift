#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// The end-to-end path: Mermaid source → `RenderScene` → SVG, proving the
/// `DiagramTheme.resolved` → `RenderTheme` mapping and the family lowerings wire
/// up. Phase 0a: flowchart; Phase 0b: + state, ER, class, sequence. Families
/// not yet lowered return nil.
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

    func testPhase0bFamiliesRenderSVG() throws {
        // state, ER, class, sequence all lower now (Phase 0b).
        let sources = [
            "stateDiagram-v2\n    [*] --> Idle\n    Idle --> [*]",
            "erDiagram\n    ORG ||--o{ USER : has",
            "classDiagram\n    Animal <|-- Dog\n    Animal : +move() void",
            "sequenceDiagram\n    Alice->>Bob: Hi\n    Bob-->>Alice: Bye",
        ]
        for source in sources {
            let svg = try XCTUnwrap(MermaidRenderer.svg(source: source, theme: theme),
                                    "expected an SVG for:\n\(source)")
            XCTAssertTrue(svg.hasPrefix("<svg"))
            XCTAssertTrue(svg.contains("</svg>"))
            #if canImport(Darwin)
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(),
                          "bridged SVG must be XML-parseable for:\n\(source)")
            #endif
        }
    }

    func testUnloweredFamilyReturnsNil() {
        // Families not yet lowered still decline (marked `// Phase 0b:`).
        let pie = "pie\n    \"A\" : 40\n    \"B\" : 60"
        XCTAssertNil(MermaidRenderer.svg(source: pie, theme: theme))
        XCTAssertNil(MermaidRenderer.renderScene(source: pie, theme: theme))
    }

    func testUnparseableReturnsNil() {
        XCTAssertNil(MermaidRenderer.svg(source: "not a diagram", theme: theme))
    }
}
#endif
