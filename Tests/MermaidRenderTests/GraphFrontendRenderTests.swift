// Regression coverage for the "never trap on a parsed diagram" contract as it
// applies to the non-Mermaid front-ends (Dippin, DOT). A parsed `Flowchart`
// wrapped in a `MermaidDiagram` must render to `pngData` for both themes without
// trapping — no force-unwrap on a conditional back-edge (a loop-back into an
// earlier node) or a typed shape may reach the layout/scene/draw path.
#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
@testable import MermaidRender
@testable import MermaidLayout

final class GraphFrontendRenderTests: XCTestCase {

    /// The Dippin workflow that surfaced the report: conditional back-edges
    /// (TestsPass -> Draft, Approve -> Draft) that loop back into the start node.
    /// Must parse and render (non-nil PNG) in light and dark.
    func testDippinWorkflowRendersBothThemes() throws {
        let src = """
        workflow Review
          goal: "draft, test, ship"
          start: Draft
          exit: Ship
          agent Draft
            model: claude-opus-4-6
          tool Test
          conditional TestsPass
            label: "Tests pass?"
          human Approve
          agent Ship
          edges
            Draft -> Test
            Test -> TestsPass
            TestsPass -> Approve when ctx.outcome == "success"
            TestsPass -> Draft when ctx.outcome == "fail"
            Approve -> Ship when ctx.choice == "approve"
            Approve -> Draft when ctx.choice == "reject"
        """
        let chart = try XCTUnwrap(DippinParser.parse(src), "Dippin source failed to parse")
        let diagram = MermaidDiagram.flowchart(chart)
        for prefersDark in [false, true] {
            let theme = DiagramTheme(prefersDark: prefersDark)
            let png = try XCTUnwrap(
                MermaidRenderer.pngData(diagram: diagram, theme: theme),
                "Dippin diagram rendered nil (prefersDark=\(prefersDark))")
            XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47],
                           "not a PNG (prefersDark=\(prefersDark))")
        }
    }

    /// A DOT source through the same already-parsed render path — the other
    /// graph front-end — must likewise render both themes without trapping.
    func testDOTGraphRendersBothThemes() throws {
        let src = """
        digraph G {
            Draft -> Test;
            Test -> TestsPass;
            TestsPass -> Draft;
            TestsPass -> Ship;
        }
        """
        let chart = try XCTUnwrap(DOTParser.parse(src), "DOT source failed to parse")
        let diagram = MermaidDiagram.flowchart(chart)
        for prefersDark in [false, true] {
            let theme = DiagramTheme(prefersDark: prefersDark)
            let png = try XCTUnwrap(
                MermaidRenderer.pngData(diagram: diagram, theme: theme),
                "DOT diagram rendered nil (prefersDark=\(prefersDark))")
            XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47],
                           "not a PNG (prefersDark=\(prefersDark))")
        }
    }

    #if canImport(AppKit) || canImport(UIKit)
    /// `rgbaRaster` must bound `targetWidth` like the parser input caps: a
    /// pathological width can't be allowed to trap the height conversion or
    /// exhaust memory. A sane width still rasters.
    func testRasterWidthIsBounded() throws {
        let chart = try XCTUnwrap(DOTParser.parse("digraph G { A -> B; B -> C; }"))
        let diagram = MermaidDiagram.flowchart(chart)
        let theme = DiagramTheme(prefersDark: false)
        let bg: (r: UInt8, g: UInt8, b: UInt8) = (255, 255, 255)

        // Absurd widths are rejected up front (no trap, no allocation).
        XCTAssertNil(MermaidRenderer.rgbaRaster(diagram: diagram, theme: theme,
                                                targetWidth: Int.max, background: bg))
        XCTAssertNil(MermaidRenderer.rgbaRaster(diagram: diagram, theme: theme,
                                                targetWidth: MermaidRenderer.maxRasterDimension + 1,
                                                background: bg))
        XCTAssertNil(MermaidRenderer.rgbaRaster(diagram: diagram, theme: theme,
                                                targetWidth: 0, background: bg))

        // A reasonable width still produces a correctly sized buffer.
        let raster = try XCTUnwrap(
            MermaidRenderer.rgbaRaster(diagram: diagram, theme: theme,
                                       targetWidth: 200, background: bg))
        XCTAssertEqual(raster.width, 200)
        XCTAssertEqual(raster.pixels.count, raster.width * raster.height * 4)
    }
    #endif
}
#endif
