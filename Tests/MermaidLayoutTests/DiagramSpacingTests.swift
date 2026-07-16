import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The density knob must stay SAFE at every preset: tighter spacing is where
/// edges start clipping boxes, so every spacing-aware type is linted at all
/// three presets, and the presets must actually order the canvas size.
final class DiagramSpacingTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    private func fixture(_ name: String) throws -> MermaidDiagram {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let src = try String(contentsOf: dir.appendingPathComponent("\(name).mmd"), encoding: .utf8)
        return try XCTUnwrap(MermaidParser.parse(src))
    }

    private func area(_ diagram: MermaidDiagram, _ spacing: DiagramSpacing) -> CGFloat? {
        switch diagram {
        case .flowchart(let d):
            let l = DiagramLayoutEngine.layout(d, measure: measure, spacing: spacing)
            return l.size.width * l.size.height
        case .classDiagram(let d):
            let l = DiagramLayoutEngine.layout(d, measure: measure, spacing: spacing)
            return l.size.width * l.size.height
        case .er(let d):
            let l = DiagramLayoutEngine.layout(d, measure: measure, spacing: spacing)
            return l.size.width * l.size.height
        case .state(let d):
            let l = DiagramLayoutEngine.layout(d, measure: measure, spacing: spacing)
            return l.size.width * l.size.height
        case .architecture(let d):
            let l = DiagramLayoutEngine.layout(d, measure: measure, spacing: spacing)
            return l.size.width * l.size.height
        default:
            return nil
        }
    }

    func testPresetsOrderCanvasArea() throws {
        for name in ["flowchart", "class", "er", "state", "architecture"] {
            let d = try fixture(name)
            let compact = try XCTUnwrap(area(d, .compact))
            let regular = try XCTUnwrap(area(d, .regular))
            let comfortable = try XCTUnwrap(area(d, .comfortable))
            XCTAssertLessThan(compact, regular, "\(name): compact should shrink the canvas")
            XCTAssertLessThan(regular, comfortable, "\(name): comfortable should grow the canvas")
        }
    }

    /// Compact is the dangerous direction: lint the compact CLASS and
    /// FLOWCHART scenes for occlusion errors by lowering their spaced layouts.
    func testCompactStaysOcclusionFree() throws {
        guard case .classDiagram(let cls) = try fixture("class") else { return XCTFail() }
        let classLayout = DiagramLayoutEngine.layout(cls, measure: measure, spacing: .compact)
        let classScene = DiagramScene.from(classLayout, measure: measure)
        XCTAssertEqual(DiagramLayoutLinter.lint(classScene).filter { $0.severity == .error }.count, 0,
                       "compact class layout must stay occlusion-free")

        guard case .flowchart(let flow) = try fixture("flowchart") else { return XCTFail() }
        let flowLayout = DiagramLayoutEngine.layout(flow, measure: measure, spacing: .compact)
        let flowScene = DiagramScene.from(flowLayout, measure: measure)
        XCTAssertEqual(DiagramLayoutLinter.lint(flowScene).filter { $0.severity == .error }.count, 0,
                       "compact flowchart layout must stay occlusion-free")
    }
}
