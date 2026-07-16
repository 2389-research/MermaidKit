#if canImport(AppKit) || canImport(UIKit)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// The front-matter `title:` renders as mermaid.js's centred caption above
/// the diagram — a band added around the shared render plan, so raster and
/// PDF both get it — and it must never double a title the dialect already
/// draws itself.
final class FrontMatterCaptionTests: XCTestCase {
    private let theme = DiagramTheme(prefersDark: false)

    func testFrontMatterTitleAddsACaptionBand() throws {
        let plain = try XCTUnwrap(MermaidRenderer.image(
            source: "flowchart TD\n  A --> B", theme: theme))
        let captioned = try XCTUnwrap(MermaidRenderer.image(
            source: "---\ntitle: Pipeline\n---\nflowchart TD\n  A --> B", theme: theme))
        XCTAssertGreaterThan(captioned.size.height, plain.size.height + 20,
                             "caption band missing")
    }

    func testCaptionTextIsActuallyDrawn() throws {
        #if canImport(AppKit) && DEBUG
        var captured: [String] = []
        DiagramRenderer.textCaptureHook = { text, _ in captured.append(text) }
        defer { DiagramRenderer.textCaptureHook = nil }
        let source = "---\ntitle: Pipeline\n---\nflowchart TD\n  A --> B\n%% caption-draw"
        let image = try XCTUnwrap(MermaidRenderer.image(source: source, theme: theme))
        _ = image.cgImage(forProposedRect: nil, context: nil, hints: nil)  // force the deferred draw
        XCTAssertTrue(captured.contains("Pipeline"), "caption never hit the context: \(captured)")
        #endif
    }

    func testDialectOwnTitleIsNeverDoubled() throws {
        // Pie draws its own `title` statement; adding a front-matter title
        // must not stack a second band on top.
        let own = try XCTUnwrap(MermaidRenderer.image(
            source: "pie\n  title Sales\n  \"A\": 1\n  \"B\": 2", theme: theme))
        let both = try XCTUnwrap(MermaidRenderer.image(
            source: "---\ntitle: Sales\n---\npie\n  title Sales\n  \"A\": 1\n  \"B\": 2",
            theme: theme))
        XCTAssertEqual(both.size.height, own.size.height, accuracy: 0.5,
                       "front-matter title doubled the dialect's own title")
    }

    func testCaptionReachesThePDFPath() throws {
        let plain = try XCTUnwrap(MermaidRenderer.pdfData(
            source: "flowchart TD\n  A --> B", theme: theme))
        let captioned = try XCTUnwrap(MermaidRenderer.pdfData(
            source: "---\ntitle: Pipeline\n---\nflowchart TD\n  A --> B", theme: theme))
        func pageHeight(_ data: Data) throws -> CGFloat {
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            let document = try XCTUnwrap(CGPDFDocument(provider))
            return try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox).height
        }
        XCTAssertGreaterThan(try pageHeight(captioned), try pageHeight(plain) + 20)
    }
}
#endif
