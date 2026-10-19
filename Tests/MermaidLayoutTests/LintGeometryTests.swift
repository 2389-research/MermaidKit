import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The linter's rect-in-rect checks give the same answer on every platform.
/// swift-corelibs-foundation's `CGRect.contains(CGRect)` is `union(r) == self`,
/// which is false for most fractional rects because rebuilding the width as
/// `maxX − minX` loses the last bit; the linter compares edges instead.
final class LintGeometryTests: XCTestCase {
    // A rect whose width doesn't survive `maxX − minX` (measured: about three
    // fractional rects in four don't).
    private let outer = CGRect(x: 1912.0685437784987, y: 10, width: 380.1744450825528, height: 200)

    func testTheFixtureRectLosesItsWidthInARoundTrip() {
        XCTAssertNotEqual(outer.maxX - outer.minX, outer.width,
                          "the input must be one that union(r) == self gets wrong")
    }

    func testEnclosesComparesEdgesInclusively() {
        XCTAssertTrue(DiagramLayoutLinter.encloses(outer, outer.insetBy(dx: 20, dy: 20)))
        XCTAssertTrue(DiagramLayoutLinter.encloses(outer, outer), "edges are inclusive")
        XCTAssertFalse(DiagramLayoutLinter.encloses(outer, outer.offsetBy(dx: 1, dy: 0)))
        XCTAssertFalse(DiagramLayoutLinter.encloses(outer, .null))
        XCTAssertFalse(DiagramLayoutLinter.encloses(.null, outer))
    }

    /// A box nested in another is nesting, not an overlap — on Linux too.
    func testNestedBoxesWithFractionalFramesAreNotAnOverlap() {
        let scene = DiagramScene(
            name: "flowchart", size: CGSize(width: 2400, height: 260),
            nodes: [DiagramScene.Node(id: "outer", frame: outer),
                    DiagramScene.Node(id: "inner", frame: outer.insetBy(dx: 30, dy: 30))],
            edges: [], labels: [])
        XCTAssertFalse(DiagramLayoutLinter.lint(scene).contains { $0.kind == "nodes-overlap" })
    }

    /// Content inside the canvas is on it, at fractional sizes too.
    func testFractionalContentInsideTheCanvasIsOnIt() {
        let scene = DiagramScene(
            name: "flowchart", size: CGSize(width: outer.maxX + 0.5, height: 260),
            nodes: [DiagramScene.Node(id: "edge-hugging", frame: outer)],
            edges: [], labels: [])
        XCTAssertFalse(DiagramLayoutLinter.lint(scene).contains { $0.kind == "off-canvas" })
    }
}
