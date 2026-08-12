import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Tracks how aligned box-family layouts are to the 4px grid (see
/// `DiagramLayoutLinter.gridAlignment`). This is the "lint-first" baseline for the
/// grid work: a per-type FLOOR the layout can only ratchet UP — a layout change
/// that de-aligns boxes fails here, and when a `GridQuantizer` lands, alignment
/// jumps toward 1.0 and the floors get raised. Mirrors the draw-vs-scene
/// conformance ratchet (ceilings that only fall); here, floors that only rise.
final class GridAlignmentTests: XCTestCase {

    /// Same deterministic geometry-only measurer the lint tests use, so the
    /// recorded floors are reproducible on every platform (no font metrics).
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    /// Per-type floor on the fraction of node coordinates already on the 4px grid,
    /// under the measurer above. Recorded from the current layouts; a type may
    /// only get MORE aligned. Regenerate by running with `PRINT_GRID=1`.
    private let floors: [String: Double] = [
        // Measured under the geometry-only measurer above (see PRINT_GRID),
        // rounded down for a small jitter margin. These may only rise.
        "flowchart": 0.21, "block": 0.08, "c4": 0.44,
        "architecture": 0.42, "er": 0.14, "class": 0.14, "state": 0.08,
    ]

    private var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
    }

    private func scene(_ type: String) throws -> DiagramScene {
        let source = try String(contentsOf: fixturesDir.appendingPathComponent("\(type).mmd"), encoding: .utf8)
        guard let diagram = MermaidParser.parse(source) else {
            throw XCTSkip("\(type): fixture did not parse")
        }
        return DiagramScene.lower(diagram, measure: measure)
    }

    /// Every box-family fixture stays at least as grid-aligned as its recorded floor.
    func testGridAlignmentRatchet() throws {
        let printing = ProcessInfo.processInfo.environment["PRINT_GRID"] != nil
        for type in DiagramLayoutLinter.gridFamilies.sorted() {
            let s = try scene(type)
            guard let ga = DiagramLayoutLinter.gridAlignment(s) else {
                XCTFail("\(type): expected a grid-alignment reading for a box family"); continue
            }
            if printing {
                let frac = (ga.coordFraction * 10000).rounded() / 10000
                print("  \(type): \(frac)  (\(ga.coordsOnGrid)/\(ga.coordsTotal) coords, \(ga.nodesOnGrid)/\(ga.nodes) boxes)")
            }
            let floor = floors[type] ?? 0
            XCTAssertGreaterThanOrEqual(ga.coordFraction, floor - 1e-9,
                "\(type): grid alignment \(ga.coordFraction) fell below floor \(floor) — a layout change de-aligned boxes")
        }
    }

    /// The metric is undefined for families a grid doesn't apply to.
    func testMetricNilForNonBoxFamilies() throws {
        for type in ["pie", "radar", "timeline", "sequence", "mindmap"] {
            let s = try scene(type)
            XCTAssertNil(DiagramLayoutLinter.gridAlignment(s),
                "\(type) is not a box family; grid metric should be nil")
        }
    }

    /// Fractions are well-formed probabilities.
    func testFractionsAreBounded() throws {
        for type in DiagramLayoutLinter.gridFamilies.sorted() {
            guard let ga = DiagramLayoutLinter.gridAlignment(try scene(type)) else { continue }
            XCTAssertTrue((0...1).contains(ga.coordFraction), "\(type) coordFraction out of range")
            XCTAssertTrue((0...1).contains(ga.nodeFraction), "\(type) nodeFraction out of range")
            XCTAssertLessThanOrEqual(ga.nodesOnGrid, ga.nodes)
            XCTAssertEqual(ga.coordsTotal, ga.nodes * 4)
        }
    }

    /// A fully-snapped scene reads as 100% aligned (sanity-checks the measurement
    /// itself, independent of any fixture's current layout).
    func testSnappedSceneIsFullyAligned() {
        let nodes = [
            DiagramScene.Node(id: "a", frame: CGRect(x: 8, y: 12, width: 100, height: 40)),
            DiagramScene.Node(id: "b", frame: CGRect(x: 8, y: 80, width: 100, height: 40)),
        ]
        let s = DiagramScene(name: "flowchart", size: CGSize(width: 200, height: 200),
                             nodes: nodes, edges: [], labels: [])
        let ga = DiagramLayoutLinter.gridAlignment(s)
        XCTAssertEqual(ga?.coordFraction, 1.0)
        XCTAssertEqual(ga?.nodesOnGrid, 2)
    }
}
