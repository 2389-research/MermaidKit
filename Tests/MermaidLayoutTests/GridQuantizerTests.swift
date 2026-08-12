import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The grid-snap transform (`GridQuantizer`, opt-in via `DiagramSpacing.gridSnap`).
/// The metric side is guarded by `GridAlignmentTests`; here we prove the transform
/// (a) fully aligns the geometry it snaps, (b) keeps the layout lint-clean — edges
/// stay attached to their (grown) boxes and no box is occluded or overlapping —
/// and (c) does nothing at all when off.
final class GridQuantizerTests: XCTestCase {

    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    private var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
    }

    private func flowchart() throws -> Flowchart {
        let source = try String(contentsOf: fixturesDir.appendingPathComponent("flowchart.mmd"), encoding: .utf8)
        guard case let .flowchart(chart)? = MermaidParser.parse(source) else {
            throw XCTSkip("flowchart fixture did not parse to a flowchart")
        }
        return chart
    }

    /// Snapping the flowchart fixture drives every node coordinate onto the 4px grid.
    func testSnapAlignsAllNodeCoords() throws {
        let chart = try flowchart()
        let snapped = DiagramLayoutEngine.layout(chart, measure: measure, spacing: DiagramSpacing(gridSnap: 4))
        for node in snapped.nodes {
            for (name, v) in [("x", node.frame.minX), ("y", node.frame.minY),
                              ("w", node.frame.width), ("h", node.frame.height)] {
                let onGrid = abs(v - (v / 4).rounded() * 4) < 1e-6
                XCTAssertTrue(onGrid, "node \(node.id) \(name)=\(v) is off the 4px grid")
            }
        }
        // …and the grid-alignment metric agrees end-to-end (through the lint IR).
        let scene = DiagramScene.from(snapped, measure: measure)
        let ga = DiagramLayoutLinter.gridAlignment(scene)
        XCTAssertEqual(ga?.coordFraction ?? 0, 1.0, accuracy: 1e-9,
                       "expected full grid alignment after snapping")
    }

    /// Snapping must not introduce layout errors: grown boxes keep their edges
    /// attached (no `edge-endpoint-detached`), out of their interiors (no
    /// `edge-occludes-node`), and apart (no `nodes-overlap`).
    func testSnappedLayoutStaysLintClean() throws {
        let chart = try flowchart()
        let snapped = DiagramLayoutEngine.layout(chart, measure: measure, spacing: DiagramSpacing(gridSnap: 4))
        let scene = DiagramScene.from(snapped, measure: measure)
        let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
            "grid-snapped flowchart introduced layout errors:\n" +
            errors.map { "  ✗ [\($0.kind)] \($0.detail)" }.joined(separator: "\n"))
    }

    /// Boxes only ever grow (never clip): each snapped frame contains its original.
    func testSnappedBoxesNeverShrink() throws {
        let chart = try flowchart()
        let raw = DiagramLayoutEngine.layout(chart, measure: measure)
        let snapped = DiagramLayoutEngine.layout(chart, measure: measure, spacing: DiagramSpacing(gridSnap: 4))
        let rawByID = Dictionary(uniqueKeysWithValues: raw.nodes.map { ($0.id, $0.frame) })
        for node in snapped.nodes {
            guard let o = rawByID[node.id] else { continue }
            XCTAssertLessThanOrEqual(node.frame.minX, o.minX + 1e-6, "\(node.id) x grew inward")
            XCTAssertLessThanOrEqual(node.frame.minY, o.minY + 1e-6, "\(node.id) y grew inward")
            XCTAssertGreaterThanOrEqual(node.frame.maxX, o.maxX - 1e-6, "\(node.id) clipped on the right")
            XCTAssertGreaterThanOrEqual(node.frame.maxY, o.maxY - 1e-6, "\(node.id) clipped on the bottom")
        }
    }

    /// Off by default: an unset `gridSnap` leaves geometry byte-for-byte identical.
    func testGridSnapOffIsIdentity() throws {
        let chart = try flowchart()
        let a = DiagramLayoutEngine.layout(chart, measure: measure)                       // default
        let b = DiagramLayoutEngine.layout(chart, measure: measure, spacing: .regular)    // explicit, gridSnap nil
        XCTAssertNil(DiagramSpacing().gridSnap)
        XCTAssertEqual(a.nodes.count, b.nodes.count)
        for (x, y) in zip(a.nodes, b.nodes) { XCTAssertEqual(x.frame, y.frame) }
    }

    /// The cache fingerprint distinguishes snapped from unsnapped (else a snapped
    /// and unsnapped render of the same source/theme would collide in the cache).
    func testFingerprintReflectsGridSnap() {
        XCTAssertNotEqual(DiagramSpacing().fingerprint, DiagramSpacing(gridSnap: 4).fingerprint)
        XCTAssertNotEqual(DiagramSpacing(gridSnap: 4).fingerprint, DiagramSpacing(gridSnap: 8).fingerprint)
    }
}
