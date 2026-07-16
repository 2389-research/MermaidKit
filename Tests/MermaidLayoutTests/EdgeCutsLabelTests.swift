import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The `edge-cuts-label` invariant — added after a branch-point commit label
/// shipped with the branch line running straight through it. A human caught
/// it; the linter couldn't, because no check covered edges vs free-standing
/// text. Now one does, and this class of defect fails CI automatically.
final class EdgeCutsLabelTests: XCTestCase {

    /// The original defect, reconstructed: a vertical branch leg descending
    /// through a label that sits below its commit dot. Must be an ERROR.
    func testVerticalLegThroughLabelIsAnError() {
        let scene = DiagramScene(
            name: "synthetic", size: CGSize(width: 200, height: 120),
            nodes: [.init(id: "dot", frame: CGRect(x: 93, y: 23, width: 14, height: 14), isContainer: false)],
            edges: [.init(polyline: [CGPoint(x: 100, y: 30), CGPoint(x: 100, y: 100)], label: nil)],
            labels: [.init(text: "label reservation", frame: CGRect(x: 60, y: 46, width: 80, height: 14))])
        let hits = DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-cuts-label" }
        XCTAssertEqual(hits.count, 1, "a leg through free-standing text must be flagged")
        XCTAssertEqual(hits.first?.severity, .error, "it gates CI, so it must be an error")
    }

    /// An edge label ON its own route is design, not defect: exempt via
    /// anchorEdge — but a DIFFERENT edge through the same label still fails.
    func testAnchoredLabelExemptsOnlyItsOwnEdge() {
        let route: [CGPoint] = [CGPoint(x: 20, y: 50), CGPoint(x: 180, y: 50)]
        var scene = DiagramScene(
            name: "synthetic", size: CGSize(width: 200, height: 100),
            nodes: [],
            edges: [.init(polyline: route, label: "on my route")],
            labels: [.init(text: "on my route", frame: CGRect(x: 70, y: 43, width: 60, height: 14),
                           anchorEdge: 0)])
        XCTAssertTrue(DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-cuts-label" }.isEmpty,
                      "a label may sit on its own edge")

        scene = DiagramScene(
            name: "synthetic", size: scene.size, nodes: [],
            edges: scene.edges + [.init(polyline: [CGPoint(x: 100, y: 10), CGPoint(x: 100, y: 90)], label: nil)],
            labels: scene.labels)
        XCTAssertEqual(DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-cuts-label" }.count, 1,
                       "another edge through the same label is still a defect")
    }

    /// A grazing touch (an edge skimming the frame border) is not a cut.
    func testBorderGrazeIsNotFlagged() {
        let scene = DiagramScene(
            name: "synthetic", size: CGSize(width: 200, height: 100),
            nodes: [],
            edges: [.init(polyline: [CGPoint(x: 20, y: 44), CGPoint(x: 180, y: 44)], label: nil)],
            labels: [.init(text: "just below the wire", frame: CGRect(x: 60, y: 45, width: 90, height: 14))])
        XCTAssertTrue(DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-cuts-label" }.isEmpty,
                      "a border graze must not fire; only real traversals")
    }
}

extension EdgeCutsLabelTests {
    /// A chip keeps text readable, but a line vanishing under it is still a
    /// placement smell: WARNING, not silence. (The old full exemption let a
    /// wardley layout stamp labels straight onto its links, unflagged.)
    func testBackedLabelUnderForeignEdgeWarns() {
        let scene = DiagramScene(
            name: "synthetic", size: CGSize(width: 200, height: 100),
            nodes: [],
            edges: [.init(polyline: [CGPoint(x: 20, y: 50), CGPoint(x: 180, y: 50)], label: nil)],
            labels: [.init(text: "on a chip", frame: CGRect(x: 70, y: 43, width: 60, height: 14),
                           backed: true)])
        let hits = DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-under-label" }
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.severity, .warning)
        XCTAssertTrue(DiagramLayoutLinter.lint(scene).filter { $0.kind == "edge-cuts-label" }.isEmpty,
                      "backed downgrades, it doesn't double-report")
    }
}
