import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Front-matter and accessibility statements are metadata ABOUT the diagram,
/// never content IN it: `title:` / `accTitle:` / `accDescr:` must read back
/// through `MermaidParser.metadata(in:)` and must never leak into layout as
/// stray nodes. The fixture shapes mirror the real-world diagram that
/// motivated the feature (front-matter with config keys + acc lines).
final class DiagramMetadataTests: XCTestCase {

    /// The user's reported diagram, verbatim in shape.
    private let kitchenSink = """
    ---
    title: Flowchart Kitchen Sink
    config:
      layout: dagre
      look: classic
    ---
    flowchart TB
        accTitle: Accessible title text
        accDescr: A longer accessibility description.
        Start --> End
    """

    // MARK: Front-matter

    func testFrontMatterTitleIsExtracted() {
        let metadata = MermaidParser.metadata(in: kitchenSink)
        XCTAssertEqual(metadata.title, "Flowchart Kitchen Sink")
    }

    func testFrontMatterConfigKeysAreToleratedAndIgnored() throws {
        // config/layout/look must be a graceful no-op — the diagram still
        // parses, and none of those keys pollute the metadata.
        let d = MermaidParser.parse(kitchenSink)
        guard case .flowchart(let chart)? = d else { return XCTFail("front-matter killed the parse") }
        XCTAssertEqual(chart.edges.count, 1)
        let metadata = MermaidParser.metadata(in: kitchenSink)
        XCTAssertEqual(metadata.title, "Flowchart Kitchen Sink")
    }

    func testFrontMatterAndAccLinesLeaveNoStrayNodes() throws {
        guard case .flowchart(let chart)? = MermaidParser.parse(kitchenSink) else {
            return XCTFail("parse failed")
        }
        XCTAssertEqual(chart.nodes.map(\.id).sorted(), ["End", "Start"],
                       "title/config/accTitle/accDescr must never become nodes")
    }

    func testNestedConfigTitleIsNotTheDiagramTitle() {
        let source = "---\nconfig:\n  title: nope\n---\nflowchart TD\n  A --> B"
        XCTAssertNil(MermaidParser.metadata(in: source).title,
                     "only a top-level title: key names the diagram")
    }

    func testQuotedFrontMatterTitleIsUnquoted() {
        let source = "---\ntitle: \"Quoted Title\"\n---\nflowchart TD\n  A --> B"
        XCTAssertEqual(MermaidParser.metadata(in: source).title, "Quoted Title")
    }

    // MARK: accTitle / accDescr

    func testAccTitleAndAccDescrAreExtracted() {
        let metadata = MermaidParser.metadata(in: kitchenSink)
        XCTAssertEqual(metadata.accessibilityTitle, "Accessible title text")
        XCTAssertEqual(metadata.accessibilityDescription, "A longer accessibility description.")
    }

    func testAccDescrBlockForm() {
        let source = """
        flowchart TD
            accDescr {
                Spans several
                source lines.
            }
            A --> B
        """
        let metadata = MermaidParser.metadata(in: source)
        XCTAssertEqual(metadata.accessibilityDescription, "Spans several source lines.")
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else {
            return XCTFail("parse failed")
        }
        XCTAssertEqual(chart.nodes.map(\.id).sorted(), ["A", "B"],
                       "block accDescr lines must never become nodes")
    }

    func testAccLinesInSequenceDiagramMintNoPhantomParticipants() throws {
        let source = """
        sequenceDiagram
            accTitle: Login flow
            accDescr: Alice authenticates with Bob.
            Alice->>Bob: Hello
        """
        guard case .sequence(let d)? = MermaidParser.parse(source) else {
            return XCTFail("parse failed")
        }
        XCTAssertEqual(d.participants.map(\.id).sorted(), ["Alice", "Bob"])
        let metadata = MermaidParser.metadata(in: source)
        XCTAssertEqual(metadata.accessibilityTitle, "Login flow")
        XCTAssertEqual(metadata.accessibilityDescription, "Alice authenticates with Bob.")
    }

    func testAccKeywordsMatchCaseInsensitively() {
        // mermaid's lexers accept the keywords case-insensitively.
        let source = "flowchart TD\n  acctitle: lower\n  ACCDESCR: upper\n  A --> B"
        let metadata = MermaidParser.metadata(in: source)
        XCTAssertEqual(metadata.accessibilityTitle, "lower")
        XCTAssertEqual(metadata.accessibilityDescription, "upper")
    }

    func testAccPrefixedNodeIsStillANode() throws {
        // `accTitleX` is an ordinary identifier, not an acc statement.
        guard case .flowchart(let chart)? =
            MermaidParser.parse("flowchart TD\n  accTitleX --> B") else {
            return XCTFail("parse failed")
        }
        XCTAssertEqual(chart.nodes.map(\.id).sorted(), ["B", "accTitleX"])
    }

    // MARK: No-front-matter regression

    func testPlainSourceHasEmptyMetadataAndUnchangedParse() throws {
        let source = "flowchart TD\n  A --> B"
        let metadata = MermaidParser.metadata(in: source)
        XCTAssertTrue(metadata.isEmpty)
        XCTAssertNil(metadata.title)
        XCTAssertNil(metadata.accessibilityTitle)
        XCTAssertNil(metadata.accessibilityDescription)
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else {
            return XCTFail("parse failed")
        }
        XCTAssertEqual(chart.edges.count, 1)
        XCTAssertEqual(chart.nodes.map(\.id).sorted(), ["A", "B"])
    }

    func testIndentationSignificantTypesSurviveStripping() throws {
        // The stripper rewrites the source line-wise; mindmap re-reads it raw,
        // so untouched lines must keep their exact indentation.
        let source = """
        ---
        title: Thoughts
        ---
        mindmap
          root((center))
            leafA
            leafB
        """
        guard case .mindmap(let d)? = MermaidParser.parse(source) else {
            return XCTFail("parse failed")
        }
        XCTAssertEqual(d.root.children.count, 2)
        XCTAssertEqual(MermaidParser.metadata(in: source).title, "Thoughts")
    }

    // MARK: Scene surfacing

    func testLoweredSceneCarriesMetadata() throws {
        let measure: DiagramTextMeasurer = { text, size in
            CGSize(width: CGFloat(text.count) * CGFloat(size) * 0.6, height: CGFloat(size) + 4)
        }
        let diagram = try XCTUnwrap(MermaidParser.parse(kitchenSink))
        let metadata = MermaidParser.metadata(in: kitchenSink)
        let scene = DiagramScene.lower(diagram, metadata: metadata, measure: measure)
        XCTAssertEqual(scene.title, "Flowchart Kitchen Sink")
        XCTAssertEqual(scene.accessibilityTitle, "Accessible title text")
        XCTAssertEqual(scene.accessibilityDescription, "A longer accessibility description.")

        let plain = DiagramScene.lower(diagram, measure: measure)
        XCTAssertNil(plain.title)
        XCTAssertNil(plain.accessibilityTitle)
        XCTAssertNil(plain.accessibilityDescription)
        // Metadata is data, not layout: geometry must be identical.
        XCTAssertEqual(scene.nodes.map(\.frame), plain.nodes.map(\.frame))
    }

    // MARK: Alt text

    func testAltTextLeadsWithAuthorAccessibilityStatements() throws {
        let text = try XCTUnwrap(MermaidAltText.describe(source: kitchenSink))
        XCTAssertTrue(text.hasPrefix("Accessible title text. A longer accessibility description."),
                      "got: \(text)")
        XCTAssertTrue(text.contains("Flowchart with 2 nodes"), "structural summary must follow")
    }

    func testAltTextFallsBackToFrontMatterTitle() throws {
        let source = "---\ntitle: Pipeline\n---\nflowchart TD\n  A --> B"
        let text = try XCTUnwrap(MermaidAltText.describe(source: source))
        XCTAssertTrue(text.hasPrefix("Pipeline."), "got: \(text)")
    }
}
