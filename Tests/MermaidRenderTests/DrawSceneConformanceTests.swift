#if os(macOS)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// THE systemic guard from the blind-spot audit: everything the renderer
/// DRAWS must be visible to the geometry linter. The drawText capture hook
/// records every painted text rect (in layout coordinates); each must be
/// covered by a scene node or label. Types with known-uncovered chrome
/// (axis ticks, bit indices — deliberate, documented) carry a ceiling that
/// can only RATCHET DOWN: new uncovered text fails the build.
final class DrawSceneConformanceTests: XCTestCase {

    /// Uncovered-text ceilings, measured at introduction. 0 = full parity.
    /// Lowering more chrome tightens these; they must never rise.
    private let ceilings: [String: Int] = [
        // er's one straggler: when an adjacent-layer edge label has no
        // reserved anchor, the RENDERER's placement scorer slides it clear of
        // obstacles while the scene keeps the polyline midpoint — a known
        // draw-vs-scene parity gap (fix: move the scorer into layout so both
        // consume its result). Everything else is at full parity.
        "er": 1,
    ]

    func testEverythingDrawnIsVisibleToTheLinter() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 30)

        let theme = DiagramTheme(prefersDark: false)
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent
            // Cache-busting comment: the hook only fires on a real draw.
            let source = try String(contentsOf: url, encoding: .utf8) + "\n%% conformance"
            guard let diagram = MermaidParser.parse(source) else {
                XCTFail("\(name): failed to parse"); continue
            }

            var captured: [(text: String, rect: CGRect)] = []
            DiagramRenderer.textCaptureHook = { captured.append(($0, $1)) }
            defer { DiagramRenderer.textCaptureHook = nil }
            let image = MermaidRenderer.image(source: source, theme: theme)
            _ = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)  // force the deferred draw
            XCTAssertNotNil(image, name)

            let scene = DiagramScene.lower(diagram, measure: MermaidRenderer.textMeasurer)
            let covers: [CGRect] = scene.nodes.map(\.frame) + scene.labels.map(\.frame)
            let uncovered = captured.filter { item in
                !covers.contains { $0.insetBy(dx: -10, dy: -10).intersects(item.rect) }
            }
            let ceiling = ceilings[name] ?? 0
            if ProcessInfo.processInfo.environment["CONFORMANCE_REPORT"] != nil {
                print("CONF | \(name) | \(uncovered.count) | \(uncovered.prefix(4).map(\.text).joined(separator: ", "))")
            }
            XCTAssertLessThanOrEqual(
                uncovered.count, ceiling,
                "\(name): \(uncovered.count) drawn texts invisible to the linter " +
                "(ceiling \(ceiling)). New uncovered: " +
                uncovered.prefix(6).map(\.text).joined(separator: " | "))
        }
    }

    // MARK: - Lines: raster draw vs RenderScene

    /// Raster lines with no matching scene run, measured at introduction (#71)
    /// — all known placement gaps, none a missed line break: the scene puts
    /// these titles, er attribute columns and timeline captions a little off
    /// the raster's centers. Like `ceilings`, these only ratchet DOWN.
    private let lineCeilings: [String: Int] = [
        "architecture": 4, "er": 14, "eventmodeling": 4, "gitgraph": 5,
        "journey": 5, "timeline": 11, "treemap": 4, "wardley": 3,
    ]

    /// Every visual line the raster path paints for a fixture must be a scene
    /// run with the same text on the same center (within half a point), so
    /// SVG/SceneWire draw the lines the image draws.
    func testEveryDrawnLineIsASceneRun() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let theme = DiagramTheme(prefersDark: false)
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent
            let source = try String(contentsOf: url, encoding: .utf8) + "\n%% lines"   // cache-busting
            let missing = try unmatched(source, theme: theme)
            let ceiling = lineCeilings[name] ?? 0
            XCTAssertLessThanOrEqual(
                missing.count, ceiling,
                "\(name): \(missing.count) drawn lines with no scene run on their center " +
                "(ceiling \(ceiling)): " + missing.prefix(6).joined(separator: " | "))
        }
    }

    /// The visual lines the raster path paints, each with its center.
    private func drawnLines(_ source: String, theme: DiagramTheme) -> [(text: String, center: CGPoint)] {
        var lines: [(text: String, center: CGPoint)] = []
        DiagramRenderer.lineCaptureHook = { lines.append(($0, $1)) }
        defer { DiagramRenderer.lineCaptureHook = nil }
        let image = MermaidRenderer.image(source: source, theme: theme)
        _ = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)  // force the deferred draw
        XCTAssertNotNil(image)
        return lines
    }

    /// The scene's horizontal text runs (rotated ones have no raster capture).
    private func sceneLines(_ source: String, theme: DiagramTheme) throws -> [(text: String, center: CGPoint)] {
        let scene = try XCTUnwrap(MermaidRenderer.renderScene(source: source, theme: theme))
        return scene.elements.compactMap {
            guard case .text(let t) = $0, t.rotation == 0 else { return nil }
            return (t.string, t.center)
        }
    }

    /// Raster lines with no scene run of the same text within half a point.
    private func unmatched(_ source: String, theme: DiagramTheme) throws -> [String] {
        var scene = try sceneLines(source, theme: theme)
        var missing: [String] = []
        for line in drawnLines(source, theme: theme) {
            if let i = scene.firstIndex(where: {
                $0.text == line.text && hypot($0.center.x - line.center.x, $0.center.y - line.center.y) <= 0.5
            }) {
                scene.remove(at: i)
            } else {
                missing.append(line.text)
            }
        }
        return missing
    }

    /// The raster path is the reference: every line it paints for a label with
    /// `<br/>`, `<br>` or a real newline must be its own scene run on the same
    /// center, so SVG and SceneWire break exactly where the image breaks (#71).
    func testSceneBreaksLinesWhereTheRasterDoes() throws {
        let theme = DiagramTheme(prefersDark: false)
        let sources = [
            "flowchart TD\n    A[one<br/>two] --> B[three<br>four]\n    A -->|five<br/>six| B\n    B --> C[seven&#8232;eight]",
            "classDiagram\n    class Animal\n    Animal : +one<br/>two\n    Animal --> Dog : three<br>four",
            "stateDiagram-v2\n    state \"one<br/>two\" as s1\n    s1 --> s2 : three<br>four",
        ]
        for (i, base) in sources.enumerated() {
            let source = base + "\n%% lines \(i)"   // cache-busting: the hook only fires on a real draw
            let drawn = drawnLines(source, theme: theme).map(\.text)
            XCTAssertFalse(drawn.contains { $0.contains("<br") }, "raster split the labels")
            XCTAssertEqual(try sceneLines(source, theme: theme).map(\.text).sorted(), drawn.sorted(),
                           "scene lines differ from drawn lines")
            XCTAssertEqual(try unmatched(source, theme: theme), [], "lines placed off the raster's centers")
        }
    }
}
#endif
