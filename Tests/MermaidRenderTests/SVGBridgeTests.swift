#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// The end-to-end path: Mermaid source → `RenderScene` → SVG, proving the
/// `DiagramTheme.resolved` → `RenderTheme` mapping and the family lowerings wire
/// up. Phase 0a: flowchart; Phase 0b: + state, ER, class, sequence. Families
/// not yet lowered return nil.
final class SVGBridgeTests: XCTestCase {

    private let theme = DiagramTheme(prefersDark: false)

    func testFlowchartSourceRendersSVG() throws {
        let svg = try XCTUnwrap(MermaidRenderer.svg(
            source: "flowchart TD\n A[Start] --> B{Choice}\n B -->|yes| C[(Store)]",
            theme: theme))
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.contains("</svg>"))
        #if canImport(Darwin)
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(),
                      "bridged SVG must be XML-parseable")
        #endif
        // Node fill uses the theme's resolved accent at 6% — a translucent rgba.
        XCTAssertTrue(svg.contains("rgba("))
    }

    func testRenderSceneCanvasMatchesResolvedTheme() throws {
        let scene = try XCTUnwrap(MermaidRenderer.renderScene(
            source: "flowchart LR\n A[One] --> B[Two]", theme: theme))
        XCTAssertEqual(scene.background, theme.resolved.canvas)
        XCTAssertGreaterThan(scene.elements.count, 0)
    }

    func testPhase0bFamiliesRenderSVG() throws {
        // state, ER, class, sequence all lower now (Phase 0b).
        let sources = [
            "stateDiagram-v2\n    [*] --> Idle\n    Idle --> [*]",
            "erDiagram\n    ORG ||--o{ USER : has",
            "classDiagram\n    Animal <|-- Dog\n    Animal : +move() void",
            "sequenceDiagram\n    Alice->>Bob: Hi\n    Bob-->>Alice: Bye",
        ]
        for source in sources {
            let svg = try XCTUnwrap(MermaidRenderer.svg(source: source, theme: theme),
                                    "expected an SVG for:\n\(source)")
            XCTAssertTrue(svg.hasPrefix("<svg"))
            XCTAssertTrue(svg.contains("</svg>"))
            #if canImport(Darwin)
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(),
                          "bridged SVG must be XML-parseable for:\n\(source)")
            #endif
        }
    }

    func testPhase0b2FamiliesRenderSVG() throws {
        // c4, architecture, block, swimlane, sankey, requirement all lower now.
        let sources = [
            "C4Context\n    Person(u, \"User\")\n    System(s, \"App\")\n    Rel(u, s, \"Uses\")",
            "architecture-beta\n    group g(cloud)[G]\n    service a(server)[A] in g\n" +
                "    service b(database)[B] in g\n    a:R --> L:b",
            "block-beta\n    columns 2\n    a[\"One\"] b((\"Two\"))\n    a --> b",
            "swimlane-beta LR\n    subgraph l[Lane]\n        A[Start] --> B[End]\n    end",
            "sankey-beta\n\nA,B,10\nB,C,5",
            "requirementDiagram\n    requirement r { id: R1\n text: works\n }\n" +
                "    element e { type: module\n }\n    e - satisfies -> r",
        ]
        for source in sources {
            let svg = try XCTUnwrap(MermaidRenderer.svg(source: source, theme: theme),
                                    "expected an SVG for:\n\(source)")
            XCTAssertTrue(svg.hasPrefix("<svg"))
            XCTAssertTrue(svg.contains("</svg>"))
            #if canImport(Darwin)
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(),
                          "bridged SVG must be XML-parseable for:\n\(source)")
            #endif
        }
    }

    func testPhase0b3aChartFamiliesRenderSVG() throws {
        // pie, gantt, timeline, journey, quadrant, xychart, radar, packet,
        // kanban all lower now (Phase 0b-3a).
        let sources = [
            "pie title Pets\n    \"Dogs\" : 40\n    \"Cats\" : 60",
            "gantt\n    dateFormat YYYY-MM-DD\n    section A\n    T1 :t1, 2026-01-01, 3d\n" +
                "    M :milestone, m1, 2026-01-04, 0d",
            "timeline\n    title T\n    section S\n        2020 : Alpha\n        2021 : Beta",
            "journey\n    title J\n    section Work\n      Code : 5: Me\n      Email : 2: Me",
            "quadrantChart\n    x-axis Low --> High\n    y-axis Bad --> Good\n" +
                "    quadrant-1 Do\n    Alpha: [0.3, 0.6]",
            "xychart-beta\n    x-axis [jan, feb, mar]\n    y-axis \"Rev\" 0 --> 30\n" +
                "    bar [10, 20, 30]\n    line [5, 15, 25]",
            "radar-beta\n    axis a[\"A\"], b[\"B\"], c[\"C\"]\n" +
                "    curve x[\"X\"]{a: 3, b: 4, c: 2}\n    max 5\n    ticks 4",
            "packet-beta\n    0-15: \"Source\"\n    16-31: \"Dest\"",
            "kanban\n  todo[To Do]\n    c1[Do a thing]@{ ticket: MK-1 }",
        ]
        for source in sources {
            let svg = try XCTUnwrap(MermaidRenderer.svg(source: source, theme: theme),
                                    "expected an SVG for:\n\(source)")
            XCTAssertTrue(svg.hasPrefix("<svg"))
            XCTAssertTrue(svg.contains("</svg>"))
            #if canImport(Darwin)
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(),
                          "bridged SVG must be XML-parseable for:\n\(source)")
            #endif
        }
    }

    func testPhase0b3bFinalFamiliesRenderSVG() throws {
        // mindmap, treemap, treeView, venn, cynefin, wardley, ishikawa,
        // eventModeling, zenuml, gitGraph all lower now (Phase 0b-3b) — the
        // final families, completing full ~30-family coverage.
        let sources = [
            "mindmap\n  root((Root))\n    A\n      A1\n    B",
            "treemap\n    \"Root\"\n        \"Group\"\n            \"Leaf\": 10\n        \"Other\": 20",
            "treeView-beta\n    Root/\n        File.swift ## a leaf\n        Sub/\n            Deep.swift",
            "venn-beta\n    set a [\"Alpha\"] : 3\n    set b [\"Beta\"] : 3\n    union a, b [\"both\"]",
            "cynefin-beta\n    title F\n    clear\n        \"item\"\n    complicated\n        \"analyze\"\n" +
                "    complex\n        \"probe\"\n    chaotic\n        \"act\"\n    chaotic --> clear : \"go\"",
            "wardley-beta\n    title M\n    anchor User [0.95, 0.6]\n    component Site [0.7, 0.5]\n" +
                "    User -> Site\n    evolve Site 0.8",
            "ishikawa-beta\n    Effect\n        Cause A\n            Sub\n        Cause B",
            "eventmodeling\n    tf 1 ui View\n    tf 2 command Request\n    tf 3 event Parsed",
            "zenuml\n    title Flow\n    @Actor User\n    @Control Service\n    User->Service: go\n" +
                "    Service->Service: work\n    Service->User: done",
            "gitGraph\n    commit id: \"first\"\n    commit id: \"tagged\" tag: \"v1.0.0\"\n" +
                "    branch feat\n    commit id: \"work\"\n    checkout main\n    merge feat",
        ]
        for source in sources {
            let svg = try XCTUnwrap(MermaidRenderer.svg(source: source, theme: theme),
                                    "expected an SVG for:\n\(source)")
            XCTAssertTrue(svg.hasPrefix("<svg"))
            XCTAssertTrue(svg.contains("</svg>"))
            #if canImport(Darwin)
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(),
                          "bridged SVG must be XML-parseable for:\n\(source)")
            #endif
        }
    }

    func testEveryFixtureFamilyRendersSVG() throws {
        // Full coverage: every diagram family now lowers end-to-end, so the
        // bridge produces an SVG for each fixture — none returns nil.
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
        XCTAssertGreaterThanOrEqual(files.count, 30, "expected the full fixture corpus")
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let svg = try XCTUnwrap(MermaidRenderer.svg(source: source, theme: theme),
                                    "every family must render: \(file.lastPathComponent)")
            XCTAssertTrue(svg.hasPrefix("<svg"), "SVG for \(file.lastPathComponent)")
            XCTAssertTrue(svg.contains("</svg>"), "SVG close for \(file.lastPathComponent)")
        }
    }

    func testUnparseableReturnsNil() {
        XCTAssertNil(MermaidRenderer.svg(source: "not a diagram", theme: theme))
    }
}
#endif
