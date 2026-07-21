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

    /// Raw RGBA pixels come back from the Silica backend — the raw-raster path
    /// for framebuffers / GPU upload / SDL on Linux and embedded (Raspberry Pi),
    /// which have no display server and can't decode the PNG. Reads the Cairo
    /// ARGB32 surface directly.
    func testRgbaRasterOnLinux() throws {
        let r = try XCTUnwrap(
            MermaidRenderer.rgbaRaster(
                source: "flowchart LR\n A[Start] --> B[End]", theme: theme,
                targetWidth: 400, background: (255, 255, 255)),
            "rgbaRaster returned nil on Linux")
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertGreaterThan(r.height, 0)
        XCTAssertEqual(r.pixels.count, r.width * r.height * 4)
        // Some non-white ink lands (the diagram is drawn), and pixels are opaque.
        var inked = 0
        for i in stride(from: 0, to: r.pixels.count, by: 4) {
            if r.pixels[i] != 255 || r.pixels[i + 1] != 255 || r.pixels[i + 2] != 255 { inked += 1 }
            XCTAssertEqual(r.pixels[i + 3], 255) // opaque
        }
        XCTAssertGreaterThan(inked, 100, "expected drawn ink in the RGBA raster")
    }

    /// PDF export works through Silica's Cairo PDF surface.
    func testPDFExport() throws {
        let data = try XCTUnwrap(
            MermaidRenderer.pdfData(source: "flowchart TD\n A --> B", theme: theme))
        XCTAssertEqual(Array(data.prefix(4)), Array("%PDF".utf8))
    }
}
#endif
