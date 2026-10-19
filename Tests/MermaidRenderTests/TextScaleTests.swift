#if canImport(AppKit)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// `DiagramSpacing.textScale` lays text out at its scaled size, so every
/// fixture must still fit at the sizes Dynamic Type reaches. From the drawn
/// text rects (the `drawText` capture hook): no two texts overlap, text inside
/// a box stays inside it, and nothing leaves the canvas — no problem a fixture
/// doesn't already have at the default size.
final class TextScaleTests: XCTestCase {

    /// xSmall, xxxLarge (the largest standard size), and two accessibility
    /// sizes (AX2 is about 2, AX5 is past 3 and clamps there).
    private static let scales: [CGFloat] = [0.82, 1.118, 1.235, 1.35, 2, 3]

    /// Problems a fixture's text has, as readable lines; nil when the diagram
    /// is past the renderer's 4000pt canvas guard at this size and isn't
    /// drawn (the state fixture, 1755pt tall at 1×, at 3×).
    private func problems(_ name: String, source: String, scale: CGFloat) throws -> [String]? {
        // Cache-busting comment: the hook only fires on a real draw.
        let source = source + "\n%% text scale \(scale)"
        let diagram = try XCTUnwrap(MermaidParser.parse(source), name)
        var drawn: [(text: String, rect: CGRect)] = []
        DiagramRenderer.textCaptureHook = { drawn.append(($0, $1)) }
        defer { DiagramRenderer.textCaptureHook = nil }
        let image = MermaidRenderer.image(source: source, theme: DiagramTheme(prefersDark: false),
                                          spacing: DiagramSpacing(textScale: scale))
        let scene = DiagramScene.lower(diagram, measure: MermaidRenderer.textMeasurer,
                                       spacing: DiagramSpacing(textScale: scale))
        guard let image else {
            XCTAssertGreaterThanOrEqual(max(scene.size.width, scene.size.height), 4000,
                                        "\(name) at \(scale)×: not drawn, yet within the canvas guard")
            return nil
        }
        // Force the deferred draw, and require it: with no text captured, every
        // check below would pass without checking anything.
        XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                        "\(name) at \(scale)×: not rasterized")
        XCTAssertFalse(drawn.isEmpty, "\(name) at \(scale)×: drew no text")
        let canvas = CGRect(origin: .zero, size: scene.size).insetBy(dx: -1, dy: -1)
        // Tree view rows are invisible frames (glyph through label, measured
        // regular), and directory names draw semibold past them: not a box.
        let boxes = name == "treeview" ? [] : scene.nodes.filter { !$0.isContainer }.map(\.frame)
        // Glyph bounds run a little past the measured line; overlaps under a
        // point are rounding, not a collision.
        let ink = drawn.map { (text: $0.text, rect: $0.rect.insetBy(dx: 1, dy: 1)) }

        var out: [String] = []
        for (i, a) in ink.enumerated() {
            if !canvas.contains(drawn[i].rect) { out.append("off canvas: \"\(a.text)\"") }
            let center = CGPoint(x: drawn[i].rect.midX, y: drawn[i].rect.midY)
            if let box = boxes.filter({ $0.contains(center) }).min(by: { $0.width * $0.height < $1.width * $1.height }),
               !box.insetBy(dx: -1, dy: -1).contains(drawn[i].rect) {
                out.append("outside its box: \"\(a.text)\"")
            }
            for b in ink[(i + 1)...] where a.rect.intersects(b.rect) {
                out.append("overlap: \"\(a.text)\" / \"\(b.text)\"")
            }
        }
        return out
    }

    func testFixturesFitAtEveryTextScale() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 30)
        let report = ProcessInfo.processInfo.environment["TEXT_SCALE_REPORT"] != nil
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent
            let source = try String(contentsOf: url, encoding: .utf8)
            // A few fixtures have one label touching another at the default
            // size already (er, quadrant, requirement) — a layout matter of
            // its own, so it's the baseline here, not a failure.
            let baseline = Set(try XCTUnwrap(problems(name, source: source, scale: 1), name))
            for scale in Self.scales {
                guard let found = try problems(name, source: source, scale: scale) else { continue }
                let new = found.filter { !baseline.contains($0) }
                if report { print("TSR | \(name) | \(scale) | \(new.count) | \(new.prefix(3).joined(separator: " ; "))") }
                XCTAssertTrue(new.isEmpty, "\(name) at \(scale)×: \(new.count) — " + new.prefix(4).joined(separator: " ; "))
            }
        }
    }

    /// Multi-line message labels and notes stack at a pitch that grows with
    /// the text, in the layout's row reservation and both renderers.
    func testMultilineSequenceTextFits() throws {
        let source = """
            sequenceDiagram
              A->>B: first line<br/>second line<br/>third line
              Note over A,B: a note<br/>on two lines
              B-->>A: done
            """
        for scale in Self.scales {
            let found = try XCTUnwrap(problems("multiline sequence", source: source, scale: scale))
            XCTAssertTrue(found.isEmpty, "at \(scale)×: " + found.joined(separator: " ; "))
        }
    }

    /// The default size draws exactly what it did before text scaling.
    func testDefaultTextScaleIsUnchanged() throws {
        let source = "flowchart TD\n  A[Start] --> B{Choice}\n  B -->|yes| C[(Store)]"
        let theme = DiagramTheme(prefersDark: false)
        let plain = try XCTUnwrap(MermaidRenderer.pngData(source: source, theme: theme))
        let scaled = try XCTUnwrap(MermaidRenderer.pngData(source: source + "\n%% scale 1", theme: theme,
                                                          spacing: DiagramSpacing(textScale: 1)))
        XCTAssertEqual(plain, scaled)
    }

    /// Larger text lays out larger: the boxes around the labels grow with
    /// them.
    func testLargerTextGrowsTheLayout() throws {
        let source = "flowchart LR\n  A[Read the input] --> B[Write the output]"
        let theme = DiagramTheme(prefersDark: false)
        let one = try XCTUnwrap(MermaidRenderer.image(source: source, theme: theme))
        let two = try XCTUnwrap(MermaidRenderer.image(source: source, theme: theme,
                                                      spacing: DiagramSpacing(textScale: 2)))
        // The gap between the boxes keeps its width.
        XCTAssertGreaterThan(two.size.width, one.size.width * 1.3)
        XCTAssertLessThan(two.size.width, one.size.width * 2)
    }
}
#endif
