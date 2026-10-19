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

    /// `outer` holds `inner`, edges compared directly: swift-corelibs-foundation's
    /// `CGRect.contains(CGRect)` is `union(r) == self`, which a last-bit rounding
    /// difference can make false on Linux for a rect that is inside.
    private func encloses(_ outer: CGRect, _ inner: CGRect) -> Bool {
        inner.minX >= outer.minX - 1e-9 && inner.maxX <= outer.maxX + 1e-9
            && inner.minY >= outer.minY - 1e-9 && inner.maxY <= outer.maxY + 1e-9
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

    // MARK: Text scale

    func testTextScaleDefaultsToOneAndClamps() {
        XCTAssertEqual(DiagramSpacing().textScale, 1)
        XCTAssertEqual(DiagramSpacing(textScale: 0.1).textScale, 0.5)
        XCTAssertEqual(DiagramSpacing(textScale: 9).textScale, 3)
        var spacing = DiagramSpacing()
        spacing.textScale = 12
        XCTAssertEqual(spacing.textScale, 3, "setting it clamps too")
    }

    /// Cached renders key on the fingerprint, so a text size must change it.
    func testTextScaleIsInTheFingerprint() {
        XCTAssertNotEqual(DiagramSpacing().fingerprint, DiagramSpacing(textScale: 1.35).fingerprint)
        XCTAssertEqual(DiagramSpacing().fingerprint, DiagramSpacing(textScale: 1).fingerprint)
    }

    /// A treemap group reserves its header strip exactly where a renderer
    /// draws the header, at every text size: no children under an empty strip.
    func testTreemapReservesHeadersOnlyWhereDrawn() throws {
        guard case .treemap(let treemap) = try fixture("treemap") else { return XCTFail() }
        for k in [1.0, 1.118, 1.35, 2.0, 3.0] {
          DiagramTextScale.run(DiagramSpacing(textScale: k), measure) { scaled in
            let layout = DiagramLayoutEngine.layout(treemap, measure: scaled)
            let header = DiagramLayoutEngine.grown(16, fontSize: 9.5, scaled)
            for group in layout.cells where !group.isLeaf {
                let children = layout.cells.filter {
                    $0.depth == group.depth + 1 && encloses(group.frame, $0.frame)
                }
                guard let top = children.map(\.frame.minY).min() else { continue }
                let drawn = DiagramLayoutEngine.treemapDrawsHeader(group.label, in: group.frame, scaled)
                XCTAssertEqual(top, group.frame.minY + 2 + (drawn ? header : 0), accuracy: 0.01,
                               "\(group.label) at \(k)×")
            }
          }
        }
    }

    /// Every fixture lints clean with its text from xSmall to an
    /// accessibility size (2 is about AX2). At 3 two routing findings remain:
    /// the flowchart's long back-edge label leaves no stub, and two of the
    /// state diagram's antiparallel edges share a run.
    func testFixturesLintCleanAtLargerText() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
        // xSmall, then xLarge, xxLarge and xxxLarge — the sizes people use most,
        // where an estimate of the growth lagged the text — then about AX2.
        for k in [0.82, 1.118, 1.235, 1.353, 2.0] {
            for url in files {
                let name = url.deletingPathExtension().lastPathComponent
                let diagram = try XCTUnwrap(MermaidParser.parse(try String(contentsOf: url, encoding: .utf8)), name)
                let errors = DiagramLayoutLinter.lint(
                    DiagramScene.lower(diagram, measure: measure, spacing: DiagramSpacing(textScale: k)))
                    .filter { $0.severity == .error }
                XCTAssertTrue(errors.isEmpty, "\(name) at \(k)×: " + errors.prefix(3).map(\.detail).joined(separator: " | "))
            }
        }
    }

    // MARK: Text scale reaches every entry point

    /// Grown lengths track the text exactly — the old (line height − 4) /
    /// fontSize estimate stayed at 1 at xLarge (1.118) in the system font.
    func testGrowthIsTheTextScale() {
        for k in [1.0, 1.118, 1.235, 1.353, 2.0, 3.0] {
            DiagramTextScale.run(DiagramSpacing(textScale: k), measure) { _ in
                XCTAssertEqual(DiagramLayoutEngine.grown(10, fontSize: 9.5, measure), 10 * k, accuracy: 1e-9, "\(k)")
            }
        }
        XCTAssertEqual(DiagramLayoutEngine.grown(10, fontSize: 9.5, measure), 10, "outside a scaled layout")
        DiagramTextScale.run(DiagramSpacing(textScale: 0.82), measure) { _ in
            XCTAssertEqual(DiagramLayoutEngine.grown(10, fontSize: 9.5, measure), 10, "smaller text keeps the default room")
        }
    }

    /// The public headless engines honor `textScale`, so headless geometry
    /// matches the image rendered from the same spacing.
    func testHeadlessLayoutHonorsTextScale() throws {
        guard case .flowchart(let chart) = try fixture("flowchart") else { return XCTFail() }
        let one = DiagramLayoutEngine.layout(chart, measure: measure, spacing: DiagramSpacing())
        let two = DiagramLayoutEngine.layout(chart, measure: measure, spacing: DiagramSpacing(textScale: 2))
        XCTAssertGreaterThan(two.size.width, one.size.width * 1.4)
        // Padding keeps its size; the box grows by exactly the text's extra
        // height (the geometry measurer's line is size + 4).
        XCTAssertEqual(two.nodes[0].frame.height - one.nodes[0].frame.height,
                       CGFloat(DiagramLayoutEngine.nodeFontSize), accuracy: 0.01)
        // Laying out inside a scope that already applied the scale (the
        // renderers' path) must not scale the text twice.
        let nested = DiagramTextScale.run(DiagramSpacing(textScale: 2), measure) { scaled in
            DiagramLayoutEngine.layout(chart, measure: scaled, spacing: DiagramSpacing(textScale: 2))
        }
        XCTAssertEqual(nested.nodes.map(\.frame), two.nodes.map(\.frame))
    }

    /// The linter sees the scaled layout through `lower(_:measure:spacing:)`.
    func testLowerHonorsSpacing() throws {
        let diagram = try fixture("flowchart")
        guard case .flowchart(let chart) = diagram else { return XCTFail() }
        let spacing = DiagramSpacing(textScale: 2)
        let scene = DiagramScene.lower(diagram, measure: measure, spacing: spacing)
        let layout = DiagramLayoutEngine.layout(chart, measure: measure, spacing: spacing)
        XCTAssertEqual(scene.size, layout.size)
        XCTAssertEqual(DiagramScene.lower(diagram, measure: measure, spacing: DiagramSpacing()).size,
                       DiagramScene.lower(diagram, measure: measure).size)
    }

    /// Non-finite text scales fall back to the default, never into geometry.
    func testNonFiniteTextScaleIsTheDefault() {
        // Every non-finite value is the default size — the one contract the
        // C ABI and every binding document (garbage in, default out).
        for v in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertEqual(DiagramSpacing(textScale: v).textScale, 1, "\(v)")
            var spacing = DiagramSpacing()
            spacing.textScale = v
            XCTAssertEqual(spacing.textScale, 1, "\(v) by assignment")
            XCTAssertEqual(DiagramSpacing(textScale: v).fingerprint, DiagramSpacing().fingerprint, "\(v)")
        }
    }

    /// Scales closer than a hundredth still render differently, so they
    /// can't share a cache entry.
    func testCloseTextScalesHaveDistinctFingerprints() {
        XCTAssertNotEqual(DiagramSpacing(textScale: 1).fingerprint, DiagramSpacing(textScale: 1.004).fingerprint)
        XCTAssertNotEqual(DiagramSpacing(textScale: 1.351).fingerprint, DiagramSpacing(textScale: 1.353).fingerprint)
    }

    /// A group whose header label can't fit is drawn without a header, so it
    /// reserves no strip either — at the default size too. (Before, the
    /// layout reserved by height alone and children sat under an empty strip.)
    func testTreemapGroupWithAnUnfittableHeaderReservesNoStrip() throws {
        let source = """
            treemap
                "Root"
                    "An extraordinarily long group label that cannot fit"
                        "a": 10
                        "b": 10
                    "Big"
                        "c": 400
            """
        guard case .treemap(let treemap)? = MermaidParser.parse(source) else { return XCTFail() }
        let layout = DiagramLayoutEngine.layout(treemap, measure: measure)
        let group = try XCTUnwrap(layout.cells.first { $0.label.hasPrefix("An extraordinarily") })
        XCTAssertFalse(DiagramLayoutEngine.treemapDrawsHeader(group.label, in: group.frame, measure))
        let top = try XCTUnwrap(layout.cells.filter { $0.depth == group.depth + 1 && encloses(group.frame, $0.frame) }
            .map(\.frame.minY).min())
        XCTAssertEqual(top, group.frame.minY + 2, accuracy: 0.01, "no strip above the children")
    }

    /// An activation bar opens and closes exactly at its message arrows, at
    /// every text size (the bar used a fixed inset while the arrow's grew).
    func testActivationBarsMeetTheirArrows() throws {
        guard case .sequence(let diagram)? = MermaidParser.parse(
            "sequenceDiagram\n  A->>+B: start the work\n  B-->>-A: done") else { return XCTFail() }
        for k in [1.0, 1.353, 2.0, 3.0] {
            DiagramTextScale.run(DiagramSpacing(textScale: k), measure) { scaled in
                let layout = DiagramLayoutEngine.layout(diagram, measure: scaled)
                guard let bar = layout.bars.first, layout.arrows.count == 2 else { return XCTFail("\(k)") }
                XCTAssertEqual(bar.top, layout.arrows[0].y, accuracy: 1e-9, "opens at its arrow, \(k)×")
                XCTAssertEqual(bar.bottom, layout.arrows[1].y, accuracy: 1e-9, "closes at its arrow, \(k)×")
            }
        }
    }

    /// Each quadrant's name stays inside its quadrant at every text size (it
    /// was centered a fixed 14 from the edge, so large names crossed it).
    func testQuadrantNamesStayInTheirQuadrants() throws {
        guard case .quadrant(let chart) = try fixture("quadrant") else { return XCTFail() }
        for k in [1.0, 1.353, 2.0, 3.0] {
            DiagramTextScale.run(DiagramSpacing(textScale: k), measure) { scaled in
                let layout = DiagramLayoutEngine.layout(chart, measure: scaled)
                XCTAssertFalse(layout.quadrantLabels.isEmpty)
                for label in layout.quadrantLabels {
                    let size = scaled(label.text, 10)
                    let rect = CGRect(x: label.center.x - size.width / 2, y: label.center.y - size.height / 2,
                                      width: size.width, height: size.height)
                    XCTAssertTrue(layout.quadrantRects.contains { encloses($0, rect) },
                                  "\(label.text) at \(k)×: \(rect) not inside a quadrant")
                }
            }
        }
    }
}
