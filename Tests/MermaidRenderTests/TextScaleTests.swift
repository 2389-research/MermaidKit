#if canImport(AppKit) && !targetEnvironment(macCatalyst)
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
    private func problems(_ name: String, source: String, scale: CGFloat,
                          family: String? = nil) throws -> [String]? {
        // Cache-busting comment: the hook only fires on a real draw.
        let source = source + "\n%% text scale \(scale) \(family ?? "")"
        let diagram = try XCTUnwrap(MermaidParser.parse(source), name)
        var drawn: [(text: String, rect: CGRect)] = []
        DiagramRenderer.textCaptureHook = { drawn.append(($0, $1)) }
        defer { DiagramRenderer.textCaptureHook = nil }
        let image = MermaidRenderer.image(source: source, theme: DiagramTheme(prefersDark: false, fontFamily: family),
                                          spacing: DiagramSpacing(textScale: scale))
        // The scene measured in the same family the render drew in.
        let scene = DiagramRenderer.$fontFamily.withValue(family) {
            DiagramScene.lower(diagram, measure: MermaidRenderer.textMeasurer,
                               spacing: DiagramSpacing(textScale: scale))
        }
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
        // Data regions (a plot, a quadrant) hold points whose labels may run
        // past them; only chrome — groups, bands, lanes, frames — holds titles.
        let containers = scene.nodes.filter { $0.isContainer && $0.id != "plot" && !$0.id.hasPrefix("quadrant-") }
            .map(\.frame)
        // Glyph bounds run a little past the measured line; overlaps under a
        // point are rounding, not a collision.
        let ink = drawn.map { (text: $0.text, rect: $0.rect.insetBy(dx: 1, dy: 1)) }

        var out: [String] = []
        for (i, a) in ink.enumerated() {
            if !canvas.contains(drawn[i].rect) { out.append("off canvas: \"\(a.text)\"") }
            let center = CGPoint(x: drawn[i].rect.midX, y: drawn[i].rect.midY)
            let own = boxes.filter({ $0.contains(center) }).min(by: { $0.width * $0.height < $1.width * $1.height })
            if let box = own, !box.insetBy(dx: -1, dy: -1).contains(drawn[i].rect) {
                out.append("outside its box: \"\(a.text)\"")
            }
            // Text in a container but no box (a group's title) stays inside
            // the innermost container holding it.
            if own == nil, let group = containers.filter({ $0.contains(center) })
                .min(by: { $0.width * $0.height < $1.width * $1.height }),
               !group.insetBy(dx: -1, dy: -1).contains(drawn[i].rect) {
                out.append("outside its group: \"\(a.text)\"")
            }
            // Nor may it run into a box it isn't in (a band label over the
            // heads below it, a title over the first row).
            for box in boxes where box != own && !box.contains(drawn[i].rect) && a.rect.intersects(box) {
                out.append("crosses a box: \"\(a.text)\"")
                break
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

    // MARK: Font family

    /// Labels set in another family are laid out in it too, at the default
    /// size and at 2×, with no problem a fixture hasn't in the system font:
    /// every fixture in Helvetica Neue, and the box types — where labels size
    /// the boxes — in faces far from the system font's metrics: Georgia (a
    /// serif with no medium), Verdana (wide) and Menlo (monospaced). The chart
    /// types cap some text columns (a gantt's label gutter) for the system
    /// font's widths, which a wide face can exceed.
    func testFixturesFitInAnotherFontFamily() throws {
        let boxTypes: Set<String> = ["flowchart", "sequence", "class", "er", "state", "block", "mindmap", "c4"]
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent
            let source = try String(contentsOf: url, encoding: .utf8)
            let baseline = Set(try XCTUnwrap(problems(name, source: source, scale: 1), name))
            let families = ["Helvetica Neue"] + (boxTypes.contains(name) ? ["Georgia", "Verdana", "Menlo"] : [])
            for family in families {
                for scale: CGFloat in [1, 2] {
                    guard let found = try problems(name, source: source, scale: scale, family: family) else { continue }
                    let new = found.filter { !baseline.contains($0) }
                    XCTAssertTrue(new.isEmpty, "\(name) in \(family) at \(scale)×: " + new.prefix(4).joined(separator: " ; "))
                }
            }
        }
    }

    /// The family reaches the drawn text and the layout around it, and a
    /// family this device doesn't have is the system font, pixel for pixel.
    func testFontFamilyIsUsedAndFallsBack() throws {
        let source = "flowchart LR\n  A[Read the input] --> B[Write the output]"
        let system = try XCTUnwrap(MermaidRenderer.pngData(source: source, theme: DiagramTheme(prefersDark: false)))
        let menlo = try XCTUnwrap(MermaidRenderer.image(source: source,
                                                        theme: DiagramTheme(prefersDark: false, fontFamily: "Menlo")))
        let plain = try XCTUnwrap(MermaidRenderer.image(source: source, theme: DiagramTheme(prefersDark: false)))
        XCTAssertGreaterThan(menlo.size.width, plain.size.width, "Menlo is wider: the boxes grow with it")
        let missing = try XCTUnwrap(MermaidRenderer.pngData(
            source: source, theme: DiagramTheme(prefersDark: false, fontFamily: "No Such Family 7f3a")))
        XCTAssertEqual(missing, system)
        let font = DiagramRenderer.$fontFamily.withValue("Menlo") { DiagramRenderer.font(12, weight: .semibold) }
        XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Menlo")
    }

    /// The family is part of the render-cache key, and the system font
    /// leaves the key as it was.
    func testFontFamilyIsInTheFingerprint() {
        XCTAssertEqual(DiagramTheme(prefersDark: false).fingerprint,
                       DiagramTheme(prefersDark: false, fontFamily: nil).fingerprint)
        XCTAssertNotEqual(DiagramTheme(prefersDark: false).fingerprint,
                          DiagramTheme(prefersDark: false, fontFamily: "Menlo").fingerprint)
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

    /// Constructs the fixtures don't exercise, each placing its own text: they
    /// must fit at every scale as well as the fixtures do.
    func testConstructsFitAtEveryTextScale() throws {
        let corpus: [(String, String)] = [
            ("sequence box", """
                sequenceDiagram
                  box Backend services
                    participant A as API
                    participant D as Database
                  end
                  A->>D: query
                  D-->>A: rows
                """),
            ("sequence self-message", """
                sequenceDiagram
                  participant S as Service
                  S->>S: retry with backoff
                  S->>S: give up
                """),
            ("flowchart subgraph titles", """
                flowchart TD
                  subgraph ingest [Ingest pipeline]
                    A[Read] --> B[Parse]
                  end
                  subgraph out [Output stage]
                    C[Render] --> D[Export]
                  end
                  B --> C
                """),
        ]
        for (name, source) in corpus {
            let baseline = Set(try XCTUnwrap(problems(name, source: source, scale: 1), name))
            for scale in Self.scales {
                guard let found = try problems(name, source: source, scale: scale) else { continue }
                let new = found.filter { !baseline.contains($0) }
                XCTAssertTrue(new.isEmpty, "\(name) at \(scale)×: " + new.prefix(4).joined(separator: " ; "))
            }
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
