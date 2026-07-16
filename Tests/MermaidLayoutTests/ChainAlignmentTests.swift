import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Straight spines stay straight. Brandes-Koepf's balancing leaves single-
/// parent chains a few points off their parent's centre (a visible jog with
/// the edge label on the kink); the straightening pass snaps them. This test
/// pins the property on the fixture's opening chain.
final class ChainAlignmentTests: XCTestCase {
    func testFixtureSpineIsStraight() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let src = try String(contentsOf: dir.appendingPathComponent("flowchart.mmd"), encoding: .utf8)
        guard case .flowchart(let chart) = MermaidParser.parse(src) else { return XCTFail() }
        let measure: DiagramTextMeasurer = { t, s in
            CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
        }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        func centerX(_ id: String) throws -> CGFloat {
            try XCTUnwrap(layout.nodes.first { $0.id == id }, "fixture drifted: no node \(id)").frame.midX
        }
        // SRC -> CAPS -> HDR is a single-parent chain; centres must coincide.
        let src_ = try centerX("SRC"), caps = try centerX("CAPS"), hdr = try centerX("HDR")
        XCTAssertEqual(src_, caps, accuracy: 0.5, "SRC->CAPS should be a straight drop")
        XCTAssertEqual(caps, hdr, accuracy: 0.5, "CAPS->HDR should be a straight drop (was a 19.8pt jog before straightening)")
    }
}
