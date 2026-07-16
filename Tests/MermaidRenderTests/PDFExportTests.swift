#if canImport(AppKit) || canImport(UIKit)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// The vector export path: every fixture must produce a plausible one-page
/// PDF, and garbage must fail the same way the raster APIs fail (nil).
final class PDFExportTests: XCTestCase {
    private func fixtures() throws -> [(String, String)] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
            .map { ($0.deletingPathExtension().lastPathComponent,
                    try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testEveryFixtureExportsAOnePagePDF() throws {
        let theme = DiagramTheme(prefersDark: false)
        var count = 0
        for (name, source) in try fixtures() {
            let data = try XCTUnwrap(MermaidRenderer.pdfData(source: source, theme: theme),
                                     "\(name) failed to export")
            XCTAssertGreaterThan(data.count, 1_000, "\(name): implausibly small PDF")
            XCTAssertTrue(data.prefix(5).elementsEqual("%PDF-".utf8), "\(name): not a PDF header")
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            let document = try XCTUnwrap(CGPDFDocument(provider), "\(name): CG can't open it")
            XCTAssertEqual(document.numberOfPages, 1, "\(name): expected a single page")
            let page = try XCTUnwrap(document.page(at: 1))
            let box = page.getBoxRect(.mediaBox)
            XCTAssertGreaterThan(box.width, 50, "\(name): degenerate media box")
            count += 1
        }
        XCTAssertEqual(count, 30, "expected all 30 fixture types to export")
    }

    func testGarbageReturnsNilLikeTheRasterPath() {
        XCTAssertNil(MermaidRenderer.pdfData(source: "not a diagram",
                                             theme: DiagramTheme(prefersDark: false)))
    }
}
#endif
