import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Layout stability — the property that makes diagrams editable without
/// teleporting (ELK's "consider model order", verified with our own scene
/// diff as the fitness function).
final class StabilityTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    private func scene(_ source: String) throws -> DiagramScene {
        let diagram = try XCTUnwrap(MermaidParser.parse(source))
        return DiagramScene.lower(diagram, measure: measure)
    }

    private func fixtureSource(_ name: String) throws -> String {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        return try String(contentsOf: dir.appendingPathComponent("\(name).mmd"), encoding: .utf8)
    }

    /// Bit-for-bit determinism: the same source lays out identically across
    /// repeated runs (guards Set-iteration order in the optimizer).
    func testLayoutIsDeterministicAcrossRuns() throws {
        for name in ["flowchart", "class", "er", "state", "architecture"] {
            let source = try fixtureSource(name)
            let first = try scene(source)
            for _ in 0..<3 {
                let again = try scene(source)
                let delta = first.delta(to: again)
                XCTAssertTrue(delta.isEmpty, "\(name): re-running layout moved things: \(delta.summary)")
            }
        }
    }

    /// Editing one label to SAME-WIDTH text (the fake measurer is width =
    /// count x 6, so equal length = equal size) must not move anything: the
    /// only change a scene diff may report is nothing at all — geometry
    /// depends on the text's size, never its letters.
    func testSameWidthRenameMovesNothing() throws {
        let before = try fixtureSource("class")
        XCTAssertTrue(before.contains("Theme"), "fixture drifted; update this test's rename pair")
        let after = before.replacingOccurrences(of: "Theme", with: "Thema")

        let a = try scene(before)
        let b = try scene(after)
        let delta = a.delta(to: b)
        XCTAssertTrue(delta.movedNodes.isEmpty,
                      "same-width rename moved nodes: \(delta.movedNodes)")
        XCTAssertEqual(delta.reroutedEdges, 0,
                       "same-width rename rerouted \(delta.reroutedEdges) edges")
        XCTAssertEqual(a.size, b.size, "same-width rename changed the canvas")
    }

    /// Appending one LEAF node (no reshaping of existing structure) keeps
    /// most of the diagram still: a bounded blast radius, not a full
    /// re-shuffle. The bound is deliberately loose — appending legitimately
    /// shifts its own layer and the canvas — but a global teleport fails it.
    func testAppendingLeafHasBoundedBlastRadius() throws {
        let before = try fixtureSource("state")
        XCTAssertTrue(before.contains("Cached"), "fixture drifted; update this test's leaf parent")
        let after = before + "\n    Cached --> Evicted : memory pressure\n"

        let a = try scene(before)
        let b = try scene(after)
        let delta = a.delta(to: b)
        let movedFraction = Double(delta.movedNodes.count) / Double(max(a.nodes.count, 1))
        XCTAssertLessThan(movedFraction, 0.5,
                          "appending a leaf moved \(delta.movedNodes.count)/\(a.nodes.count) nodes — layout is teleporting")
    }
}
