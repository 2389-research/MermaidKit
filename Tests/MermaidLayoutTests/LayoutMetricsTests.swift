import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Layout-quality metrics over the layered-family fixtures. The edge-length
/// ceilings lock in the network-simplex gains: if a layering change regresses
/// total edge length past these bounds, this fails before anyone's eyes do.
final class LayoutMetricsTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    private func edgeLength(_ name: String) throws -> CGFloat {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let src = try String(contentsOf: dir.appendingPathComponent("\(name).mmd"), encoding: .utf8)
        let diagram = try XCTUnwrap(MermaidParser.parse(src))
        let scene = DiagramScene.lower(diagram, measure: measure)
        var total: CGFloat = 0
        for e in scene.edges {
            for (a, b) in zip(e.polyline, e.polyline.dropFirst()) {
                total += abs(b.x - a.x) + abs(b.y - a.y)
            }
        }
        return total
    }

    func testLayeredFamilyEdgeLengthBudgets() throws {
        // Measured on the self-referential fixtures with network-simplex
        // layering and label-space reservation, +10% headroom (class 1928 /
        // state 4447 / er 2403 / flowchart 2808 at re-baseline — recursive
        // subgraph clustering tightened flowchart's members, so its total
        // edge length fell from the pre-cluster 3335). Longest-path layering
        // blows these budgets regardless of content.
        for (name, budget) in [("class", CGFloat(2150)), ("state", 4800),
                               ("er", 2650), ("flowchart", 3700)] {
            let length = try edgeLength(name)
            XCTAssertLessThan(length, budget, "\(name): total edge length regressed")
        }
    }
}
