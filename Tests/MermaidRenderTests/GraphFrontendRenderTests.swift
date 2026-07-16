// Regression coverage for the "never trap on a parsed diagram" contract as it
// applies to the non-Mermaid front-ends (Dippin, DOT). A parsed `Flowchart`
// wrapped in a `MermaidDiagram` must render to `pngData` for both themes without
// trapping — no force-unwrap on a back-edge, an `exit:`-only node, or a shape
// with no measured size may reach the layout/scene/draw path.
#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
@testable import MermaidRender
@testable import MermaidLayout

final class GraphFrontendRenderTests: XCTestCase {

    /// The Dippin workflow that surfaced the report: conditional back-edges
    /// (TestsPass -> Draft, Approve -> Draft) plus a node reached only through a
    /// loop-back. Must parse and render (non-nil PNG) in light and dark.
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
}
#endif
