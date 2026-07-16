#if canImport(AppKit)
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
}
#endif
