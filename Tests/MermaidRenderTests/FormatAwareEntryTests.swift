// Issue #46: format-aware attachment/narration entry points. DOT, Dippin, SQL
// DDL, and git-log sources must get the SAME image / text attachment / narration
// as Mermaid via `(source, format)`, with all parser/render logic inside the
// engine (no consumer touching the parsers).
#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
@testable import MermaidRender
@testable import MermaidLayout

final class FormatAwareEntryTests: XCTestCase {
    private let theme = DiagramTheme(prefersDark: false)

    private let mermaid = "flowchart TD\n A[Start] --> B[End]"
    private let dot = "digraph G { A -> B; B -> C; }"
    private let dippin = """
    workflow Review
      start: Draft
      exit: Ship
      agent Draft
      tool Test
      agent Ship
      edges
        Draft -> Test
        Test -> Ship
    """
    private let sql = """
    CREATE TABLE customer (
      id INT PRIMARY KEY,
      name VARCHAR(100) UNIQUE
    );
    CREATE TABLE orders (
      id INT PRIMARY KEY,
      customer_id INT REFERENCES customer(id)
    );
    """
    private let gitlog = """
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  first commit
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa second commit
    cccccccccccccccccccccccccccccccccccccccc bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (HEAD -> main) third commit
    """

    private var allFormats: [(MermaidRenderer.DiagramSourceFormat, String)] {
        [(.mermaid, mermaid), (.dot, dot), (.dippin, dippin), (.sqlDDL, sql), (.gitLog, gitlog)]
    }

    /// Every format renders to a PNG through the format-aware image path.
    func testImageForEachFormat() throws {
        for (format, src) in allFormats {
            let png = try XCTUnwrap(
                MermaidRenderer.pngData(source: src, format: format, theme: theme),
                "\(format) rendered nil")
            XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "\(format) not a PNG")
        }
    }

    /// Every format produces a non-empty narration.
    func testAltTextForEachFormat() throws {
        for (format, src) in allFormats {
            let alt = try XCTUnwrap(MermaidRenderer.altText(source: src, format: format),
                                    "\(format) altText nil")
            XCTAssertFalse(alt.isEmpty, "\(format) altText empty")
        }
    }

    /// The narration reflects the diagram type each front-end produces.
    func testAltTextReflectsType() throws {
        let er = try XCTUnwrap(MermaidRenderer.altText(source: sql, format: .sqlDDL))
        XCTAssertTrue(er.lowercased().contains("entity"), "SQL DDL → ER narration; got: \(er)")
        let flow = try XCTUnwrap(MermaidRenderer.altText(source: dot, format: .dot))
        XCTAssertTrue(flow.lowercased().contains("flowchart"), "DOT → flowchart narration; got: \(flow)")
    }

    /// `.mermaid` is exactly the existing source-only behavior.
    func testMermaidFormatMatchesDirect() {
        XCTAssertEqual(MermaidRenderer.altText(source: mermaid, format: .mermaid),
                       MermaidRenderer.altText(source: mermaid))
    }

    /// A source that doesn't parse in its format returns nil (never traps).
    func testInvalidSourceReturnsNil() {
        XCTAssertNil(MermaidRenderer.altText(source: "not a diagram", format: .dot))
        XCTAssertNil(MermaidRenderer.pngData(source: "}{ nonsense", format: .sqlDDL, theme: theme))
        XCTAssertNil(MermaidRenderer.altText(source: "", format: .gitLog))
    }

    #if canImport(AppKit) || canImport(UIKit)
    /// Every format yields a single-attachment string carrying a sized image with
    /// the narration as its accessibility description — the same shape Mermaid gets.
    func testAttachmentStringForEachFormat() throws {
        for (format, src) in allFormats {
            let attr = try XCTUnwrap(
                MermaidRenderer.attachmentString(source: src, format: format, theme: theme),
                "\(format) attachment nil")
            XCTAssertGreaterThan(attr.length, 0)
            let attachment = attr.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
            let image = try XCTUnwrap(attachment?.image, "\(format) attachment has no image")
            XCTAssertGreaterThan(image.size.width, 0)
        }
    }

    /// The already-parsed diagram overload (parse it yourself).
    func testAttachmentFromDiagram() throws {
        let chart = try XCTUnwrap(DOTParser.parse(dot))
        let attr = try XCTUnwrap(
            MermaidRenderer.attachmentString(diagram: .flowchart(chart), theme: theme))
        XCTAssertGreaterThan(attr.length, 0)
    }
    #endif
}
#endif
