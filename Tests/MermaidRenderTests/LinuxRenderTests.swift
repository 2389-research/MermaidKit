// Linux (Silica/Cairo) rendering backend smoke tests. Guarded to the Linux
// render backend so they run under `swift test` in the Linux CI container and
// compile away on Apple platforms (which have their own render tests).
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import XCTest
@testable import MermaidRender
@testable import MermaidLayout

final class LinuxRenderTests: XCTestCase {
    private let theme = DiagramTheme(prefersDark: false)

    /// A representative diagram renders to a non-empty PNG via the Silica
    /// backend — proves the whole parse → layout → draw → encode pipeline runs
    /// on swift-corelibs-foundation.
    func testFlowchartRendersToPNG() throws {
        let src = """
        flowchart LR
            A[Start] --> B{Decision}
            B -->|yes| C[Ship it]
            B -->|nah| D[Bite It]
            D -->|who| B
        """
        let image = try XCTUnwrap(MermaidRenderer.image(source: src, theme: theme),
                                  "render returned nil on Linux")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        let png = try XCTUnwrap(image.pngData(), "PNG encode failed")
        // PNG magic number, and a plausible non-trivial payload.
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertGreaterThan(png.count, 200)
    }

    /// Every bundled fixture renders without crashing or returning nil — the
    /// same 30-type coverage the Apple conformance suite exercises, proving no
    /// per-type renderer hits an unsupported Silica path.
    func testAllFixturesRender() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".mmd") }
        try XCTSkipIf(files.isEmpty, "fixtures not found")
        for file in files.sorted() {
            let src = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            let image = MermaidRenderer.image(source: src, theme: theme)
            XCTAssertNotNil(image, "\(file) rendered nil on Linux")
            XCTAssertNotNil(image?.pngData(), "\(file) PNG encode failed on Linux")
        }
    }

    /// PDF export works through Silica's Cairo PDF surface.
    func testPDFExport() throws {
        let data = try XCTUnwrap(
            MermaidRenderer.pdfData(source: "flowchart TD\n A --> B", theme: theme))
        XCTAssertEqual(Array(data.prefix(4)), Array("%PDF".utf8))
    }
}
#endif
