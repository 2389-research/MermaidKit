import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Exercises the platform-free ``RenderScene`` IR and its ``SVGRenderer``
/// backend for the flowchart family: that lowering emits sane primitive counts,
/// that the SVG is well-formed and coordinate-faithful, that every node shape
/// lowers to its expected `ShapePath`, and that the whole pipeline is
/// deterministic.
final class RenderSceneTests: XCTestCase {

    /// Deterministic fake measurer — geometry only, no font metrics (matches
    /// the one in LayoutLintTests so counts stay stable across machines).
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    private let theme = RenderTheme(
        ink: DiagramColor(hex: 0x1D1D1F),
        accent: DiagramColor(hex: 0x5B8FF9),
        canvas: DiagramColor(hex: 0xFFFFFF),
        hairline: DiagramColor(hex: 0x000000, alpha: 0.12),
        secondaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.55),
        tertiaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.38),
        palette: [DiagramColor(hex: 0x5B8FF9), DiagramColor(hex: 0x61DDAA),
                  DiagramColor(hex: 0xF6BD16), DiagramColor(hex: 0x7262FD),
                  DiagramColor(hex: 0x78D3F8), DiagramColor(hex: 0xF08BB4)])

    private func layout(_ source: String) throws -> FlowchartLayout {
        guard let diagram = MermaidParser.parse(source),
              case .flowchart(let chart) = diagram else {
            throw XCTSkip("source did not parse as a flowchart")
        }
        return DiagramLayoutEngine.layout(chart, measure: measure)
    }

    private func scene(_ source: String) throws -> RenderScene {
        RenderScene.from(try layout(source), theme: theme, measure: measure)
    }

    // MARK: Element counts

    func testSceneElementCountsMatchLayout() throws {
        let source = """
        flowchart TD
            A[Start] --> B{Choice}
            B -->|yes| C[(Store)]
            B -->|no| D[End]
            subgraph G [Group]
                C --> E[Inside]
            end
        """
        let layout = try layout(source)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size, "scene canvas must equal the layout size")

        var shapes = 0, polylines = 0, texts = 0
        for element in scene.elements {
            switch element {
            case .shape: shapes += 1
            case .polyline: polylines += 1
            case .text: texts += 1
            }
        }

        // One polyline per edge.
        XCTAssertEqual(polylines, layout.edges.count)

        // At least one shape per node (cylinder/stateEnd emit two) plus one per
        // container box.
        XCTAssertGreaterThanOrEqual(shapes, layout.nodes.count + layout.containers.count)

        // A text per labeled node, per labeled edge, and per labeled container.
        let labeledNodes = layout.nodes.filter {
            !$0.label.isEmpty && $0.shape != .stateStart && $0.shape != .stateEnd
        }.count
        let labeledEdges = layout.edges.filter { ($0.label?.isEmpty == false) }.count
        let labeledContainers = layout.containers.filter { !$0.label.isEmpty }.count
        XCTAssertEqual(texts, labeledNodes + labeledEdges + labeledContainers)
    }

    // MARK: SVG well-formedness

    func testSVGIsWellFormedAndSized() throws {
        let source = """
        flowchart LR
            A[One] --> B[Two]
            B --> C[Three]
        """
        let scene = try scene(source)
        let svg = SVGRenderer.svg(scene)

        XCTAssertTrue(svg.hasPrefix("<svg"), "SVG must start with <svg")
        XCTAssertTrue(svg.contains("</svg>"), "SVG must close")

        let w = SVGRenderer.num(scene.size.width)
        let h = SVGRenderer.num(scene.size.height)
        XCTAssertTrue(svg.contains(#"viewBox="0 0 \#(w) \#(h)""#),
                      "viewBox must match the scene size")

        // One <polyline> per edge; one <text> per drawn label.
        let polylines = countOccurrences(of: "<polyline", in: svg)
        XCTAssertEqual(polylines, 2)
        let texts = countOccurrences(of: "<text", in: svg)
        XCTAssertEqual(texts, 3) // three node labels, no edge labels here

        // XMLParser accepts the document (root <svg> namespaced). Apple only —
        // swift-corelibs-foundation's XMLParser has no accessible initializer.
        #if canImport(Darwin)
        let parser = XMLParser(data: Data(svg.utf8))
        XCTAssertTrue(parser.parse(), "SVG must be XML-parseable: \(parser.parserError as Any)")
        #endif
    }

    func testSVGEscapesText() throws {
        let source = "flowchart TD\n    A[\"a & b < c > d\"] --> B[ok]"
        let svg = SVGRenderer.svg(try scene(source))
        XCTAssertTrue(svg.contains("a &amp; b &lt; c &gt; d"))
        XCTAssertFalse(svg.contains("a & b < c > d"))
        #if canImport(Darwin)
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
        #endif
    }

    // MARK: Shape coverage

    func testShapeCoverage() throws {
        // The Mermaid-parseable shapes each lower to a distinct ShapePath.
        // (hexagon/subroutine come from the DOT/Dippin front-ends, not Mermaid
        // syntax — covered in testHexagonAndSubroutineLower.)
        let source = """
        flowchart TD
            R[Rect] --> D{Diamond}
            D --> Y[(Cylinder)]
            Y --> C((Circle))
            C --> S([Stadium])
        """
        let layout = try layout(source)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        var found: [Flowchart.NodeShape: RenderScene.ShapePath] = [:]
        let byId = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.shape) })
        // Walk shapes in order; pair each node's first shape with its node by
        // matching the frame that lowering used.
        for node in layout.nodes {
            found[node.shape] = firstShapePath(in: scene, matching: node.frame)
        }
        _ = byId

        if case .roundedRect(_, let r)? = found[.rectangle] { XCTAssertEqual(r, 4) }
        else { XCTFail("rectangle should lower to a roundedRect r4") }

        if case .roundedRect(_, let r)? = found[.stadium] {
            let stadiumFrame = layout.nodes.first { $0.shape == .stadium }!.frame
            XCTAssertEqual(r, stadiumFrame.height / 2)
        } else { XCTFail("stadium should lower to a roundedRect r=height/2") }

        if case .polygon(let pts)? = found[.diamond] { XCTAssertEqual(pts.count, 4) }
        else { XCTFail("diamond should lower to a 4-point polygon") }

        if case .ellipse? = found[.circle] {} else { XCTFail("circle should lower to an ellipse") }

        if case .path(let verbs)? = found[.cylinder] {
            XCTAssertTrue(verbs.contains { if case .quad = $0 { return true } else { return false } },
                          "cylinder path should contain quad curves")
        } else { XCTFail("cylinder should lower to an explicit path") }
    }

    /// hexagon/subroutine come from the DOT/Dippin front-ends (no Mermaid
    /// syntax), so build the model directly. Regression guard: an incomplete
    /// shape switch that dropped these to a default would mis-render them.
    func testHexagonAndSubroutineLower() throws {
        let chart = Flowchart(
            direction: .topDown,
            nodes: [Flowchart.Node(id: "H", label: "Hex", shape: .hexagon),
                    Flowchart.Node(id: "U", label: "Sub", shape: .subroutine)],
            edges: [.init(from: "H", to: "U", label: nil, dashed: false, hasArrow: true, backArrow: false)])
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        let hexFrame = layout.nodes.first { $0.shape == .hexagon }!.frame
        if case .polygon(let pts)? = firstShapePath(in: scene, matching: hexFrame) {
            XCTAssertEqual(pts.count, 6, "hexagon → 6-point polygon")
        } else { XCTFail("hexagon should lower to a 6-point polygon") }

        let subFrame = layout.nodes.first { $0.shape == .subroutine }!.frame
        if case .roundedRect(_, let r)? = firstShapePath(in: scene, matching: subFrame) {
            XCTAssertEqual(r, 4, "subroutine → roundedRect r4")
        } else { XCTFail("subroutine should lower to a roundedRect r4") }

        // Subroutine also emits its twin vertical rails.
        let rails = scene.elements.filter {
            if case .polyline(let p) = $0 { return p.points.count == 2 && p.points[0].x == p.points[1].x }
            return false
        }
        XCTAssertGreaterThanOrEqual(rails.count, 2, "subroutine draws twin vertical rails")
    }

    // MARK: Determinism

    func testDeterministicSVG() throws {
        let source = """
        flowchart TD
            A[Start] --> B{Choice}
            B -->|yes| C[(Store)]
            B -->|no| D[End]
        """
        let a = SVGRenderer.svg(try scene(source))
        let b = SVGRenderer.svg(try scene(source))
        XCTAssertEqual(a, b, "same source must yield an identical SVG string")
    }

    func testSceneCodableRoundTrip() throws {
        let scene = try scene("flowchart TD\n A[One] --> B{Two}\n B --> C[(Three)]")
        // Sorted keys so the byte comparison is a value check, not a JSON
        // object-key-order check — and this is the deterministic wire form the
        // scene crosses the JNI boundary in (and the cross-backend golden gate
        // hashes).
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(scene)
        let back = try JSONDecoder().decode(RenderScene.self, from: data)
        XCTAssertEqual(try enc.encode(back), data)
        XCTAssertEqual(SVGRenderer.svg(back), SVGRenderer.svg(scene))
    }

    func testTextDecodesWithoutRotationField() throws {
        // `rotation` is additive on the wire (Android JNI boundary / versioned
        // golden contract), so scene JSON written before it existed must still
        // decode — a missing `rotation` defaults to 0 rather than failing.
        let text = RenderScene.Text(
            string: "Hi", center: CGPoint(x: 4, y: 8), fontSize: 11,
            weight: .semibold, color: DiagramColor(hex: 0x112233), rotation: 1.5)
        let data = try JSONEncoder().encode(text)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Text should encode as a JSON object")
        XCTAssertNotNil(object["rotation"], "sanity: the encoded form still carries rotation")
        object.removeValue(forKey: "rotation")   // emulate a pre-rotation blob
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(RenderScene.Text.self, from: legacy)
        XCTAssertEqual(back.rotation, 0, "a missing rotation must default to 0")
        XCTAssertEqual(back.string, "Hi")
        XCTAssertEqual(back.fontSize, 11)
    }

    // MARK: - Phase 0b families

    /// Counts the three element kinds in a scene.
    private func counts(_ scene: RenderScene) -> (shapes: Int, polylines: Int, texts: Int) {
        var s = 0, p = 0, t = 0
        for element in scene.elements {
            switch element {
            case .shape: s += 1
            case .polyline: p += 1
            case .text: t += 1
            }
        }
        return (s, p, t)
    }

    /// Shared well-formedness assertions for a Phase 0b scene → SVG.
    private func assertWellFormedSVG(_ scene: RenderScene) -> String {
        let svg = SVGRenderer.svg(scene)
        XCTAssertTrue(svg.hasPrefix("<svg"), "SVG must start with <svg")
        XCTAssertTrue(svg.contains("</svg>"), "SVG must close")
        let w = SVGRenderer.num(scene.size.width), h = SVGRenderer.num(scene.size.height)
        XCTAssertTrue(svg.contains(#"viewBox="0 0 \#(w) \#(h)""#), "viewBox must match the scene size")
        #if canImport(Darwin)
        let parser = XMLParser(data: Data(svg.utf8))
        XCTAssertTrue(parser.parse(), "SVG must be XML-parseable: \(parser.parserError as Any)")
        #endif
        // Determinism: a second render is byte-identical.
        XCTAssertEqual(svg, SVGRenderer.svg(scene), "same scene must yield identical SVG")
        return svg
    }

    // MARK: State

    func testStateSceneAndSVG() throws {
        let source = """
        stateDiagram-v2
            [*] --> Idle
            Idle --> Running: start
            Running --> Idle: stop
            Running --> [*]
        """
        guard let diagram = MermaidParser.parse(source), case .state(let s) = diagram else {
            throw XCTSkip("did not parse as a state diagram")
        }
        let layout = DiagramLayoutEngine.layout(s, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // One glyph shape per node (start/end may add a second), plus containers.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.nodes.count)
        // One shaft polyline per transition (containers add separator lines too).
        XCTAssertGreaterThanOrEqual(c.polylines, layout.edges.count)

        let svg = assertWellFormedSVG(scene)
        // A labeled transition ("start") is emitted as a <text>.
        XCTAssertTrue(svg.contains(">start<"), "transition label should appear as text")
        // Every transition draws an arrowhead polygon.
        XCTAssertGreaterThanOrEqual(countOccurrences(of: "<polygon", in: svg), layout.edges.count)
    }

    // MARK: ER

    func testERSceneAndSVG() throws {
        // Mermaid erDiagram leaves key badges empty; build the model directly so
        // the PK/FK badges (populated by the SQL-DDL front-end) are exercised.
        let er = ERDiagram(
            entities: [
                ERDiagram.Entity(name: "USER", attributes: [
                    ERDiagram.Attribute(type: "int", name: "id", keys: [.primary]),
                    ERDiagram.Attribute(type: "int", name: "org_id", keys: [.foreign]),
                ]),
                ERDiagram.Entity(name: "ORG", attributes: [
                    ERDiagram.Attribute(type: "int", name: "id", keys: [.primary]),
                ]),
            ],
            relations: [
                ERDiagram.Relation(from: "ORG", to: "USER", fromCard: .one, toCard: .oneOrMore,
                                   label: "employs", identifying: true),
            ])
        let layout = DiagramLayoutEngine.layout(er, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        XCTAssertGreaterThanOrEqual(c.shapes, layout.boxes.count, "one box shape per entity")
        // Attribute rows produce type/name/badge texts + entity names.
        XCTAssertGreaterThan(c.texts, layout.boxes.count)

        let svg = assertWellFormedSVG(scene)
        // The PK and FK key badges appear as <text> runs.
        XCTAssertTrue(svg.contains(">PK<"), "a PK badge should render")
        XCTAssertTrue(svg.contains(">FK<"), "an FK badge should render")
        // The crow's-foot "many" marker is a stroked path.
        XCTAssertTrue(svg.contains("<path"), "crow's-foot cardinality should render as a path")
        // The relationship verb appears.
        XCTAssertTrue(svg.contains(">employs<"))
    }

    // MARK: Class

    func testClassSceneAndSVG() throws {
        let source = """
        classDiagram
            Animal <|-- Dog
            Animal : +String name
            Animal : +move() void
            Dog : +bark() void
        """
        guard let diagram = MermaidParser.parse(source), case .classDiagram(let cls) = diagram else {
            throw XCTSkip("did not parse as a class diagram")
        }
        let layout = DiagramLayoutEngine.layout(cls, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        XCTAssertGreaterThanOrEqual(c.shapes, layout.boxes.count, "one box shape per class")

        // Compartment separators: a box with members emits at least one hairline
        // polyline spanning its full width.
        let separators = scene.elements.filter {
            guard case .polyline(let p) = $0, p.points.count == 2 else { return false }
            return p.points[0].y == p.points[1].y && p.points[0].x != p.points[1].x
        }
        let boxesWithMembers = layout.boxes.filter { !$0.attributes.isEmpty || !$0.methods.isEmpty }
        XCTAssertGreaterThanOrEqual(separators.count, boxesWithMembers.count,
                                    "each populated class box draws a compartment separator")

        let svg = assertWellFormedSVG(scene)
        // The inheritance relation lowers to a hollow triangle polygon.
        XCTAssertTrue(svg.contains("<polygon"), "inheritance marker should render as a polygon")
        XCTAssertTrue(svg.contains(">Animal<") && svg.contains(">Dog<"))
    }

    // MARK: Sequence

    func testSequenceSceneAndSVG() throws {
        let source = """
        sequenceDiagram
            Alice->>Bob: Hello
            Bob-->>Alice: Hi back
            Alice->>Alice: think
        """
        guard let diagram = MermaidParser.parse(source), case .sequence(let seq) = diagram else {
            throw XCTSkip("did not parse as a sequence diagram")
        }
        let layout = DiagramLayoutEngine.layout(seq, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        XCTAssertGreaterThanOrEqual(layout.arrows.count, 3)

        // One shaft polyline per message, plus one lifeline per participant.
        let c = counts(scene)
        XCTAssertGreaterThanOrEqual(c.polylines, layout.arrows.count + layout.heads.count,
                                    "a shaft per message and a lifeline per head")

        let svg = assertWellFormedSVG(scene)
        // Message shafts: at least one <polyline> per arrow (lifelines add more).
        XCTAssertGreaterThanOrEqual(countOccurrences(of: "<polyline", in: svg), layout.arrows.count)
        // The filled arrowhead of a solid message is a polygon.
        XCTAssertTrue(svg.contains("<polygon"), "a filled message head should render as a polygon")
        // Message captions appear.
        XCTAssertTrue(svg.contains(">Hello<"))
    }

    // MARK: C4

    func testC4SceneAndSVG() throws {
        let source = """
        C4Context
            title System Context
            Person(user, "User", "An end user")
            System(sys, "Web App", "Delivers content")
            System_Ext(ext, "Email System", "Sends notifications")
            Rel(user, sys, "Uses", "HTTPS")
            Rel(sys, ext, "Sends email via")
        """
        guard let diagram = MermaidParser.parse(source) else {
            throw XCTSkip("source did not parse")
        }
        guard case .c4(let c4) = diagram else {
            return XCTFail("a C4 source should lower to a C4 diagram")
        }
        let layout = DiagramLayoutEngine.layout(c4, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // One rounded-rect per box, plus a canvas+color arrowhead pair per edge.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.boxes.count + layout.edges.count)
        XCTAssertGreaterThanOrEqual(c.polylines, layout.edges.count, "a shaft per relation")

        let svg = assertWellFormedSVG(scene)
        // The centered diagram title renders.
        XCTAssertTrue(svg.contains(">System Context<"), "C4 title should render")
        // Each relation draws a filled arrowhead polygon.
        XCTAssertGreaterThanOrEqual(countOccurrences(of: "<polygon", in: svg), layout.edges.count)
        // The external system's dashed border.
        XCTAssertTrue(svg.contains(#"stroke-dasharray="4 3""#), "external box border should dash")
    }

    // MARK: Architecture

    func testArchitectureSceneAndSVG() throws {
        let source = """
        architecture-beta
            group api(cloud)[API]
            service db(database)[Database] in api
            service server(server)[Server] in api
            junction j
            db:R --> L:server
            server:B --> T:j
        """
        guard let diagram = MermaidParser.parse(source) else {
            throw XCTSkip("source did not parse")
        }
        guard case .architecture(let arch) = diagram else {
            return XCTFail("an architecture source should lower to an architecture diagram")
        }
        let layout = DiagramLayoutEngine.layout(arch, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A group box per group, a box (or 3 dot shapes for a junction) per service.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.groups.count + layout.services.count)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains("<ellipse"), "a junction dot should render as an ellipse")
        // Service/group labels appear.
        XCTAssertTrue(svg.contains(">Database<") || svg.contains(">Server<"))
    }

    // MARK: Block

    func testBlockSceneAndSVG() throws {
        let source = """
        block-beta
            columns 3
            a["One"] b(("Two")) c("Three")
            a --> b
            b --> c
        """
        guard let diagram = MermaidParser.parse(source) else {
            throw XCTSkip("source did not parse")
        }
        guard case .block(let block) = diagram else {
            return XCTFail("a block source should lower to a block diagram")
        }
        let layout = DiagramLayoutEngine.layout(block, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let drawn = layout.nodes.filter { $0.shape != .space }
        let c = counts(scene)
        XCTAssertGreaterThanOrEqual(c.shapes, drawn.count, "one (or two, for circles) shapes per block")
        XCTAssertGreaterThanOrEqual(c.polylines, layout.edges.count, "a shaft per edge")

        let svg = assertWellFormedSVG(scene)
        // The `(( ))` circle block lowers to an ellipse.
        XCTAssertTrue(svg.contains("<ellipse"), "a circle block should render as an ellipse")
        XCTAssertGreaterThanOrEqual(countOccurrences(of: "<polygon", in: svg), layout.edges.count)
    }

    // MARK: Swimlane

    func testSwimlaneSceneAndSVG() throws {
        let source = """
        swimlane-beta LR
            subgraph host[Host]
                A[Start] --> B{Choice}
            end
            subgraph work[Work]
                C[Do it]
            end
            B -->|yes| C
            B -.->|no| A
        """
        guard let diagram = MermaidParser.parse(source) else {
            throw XCTSkip("source did not parse")
        }
        guard case .swimlane(let swimlane) = diagram else {
            return XCTFail("a swimlane source should lower to a swimlane diagram")
        }
        let layout = DiagramLayoutEngine.layout(swimlane, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A band per lane and a shape per node.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.lanes.count + layout.nodes.count)
        XCTAssertGreaterThanOrEqual(c.polylines, layout.edges.count)

        let svg = assertWellFormedSVG(scene)
        // Lane titles render rotated (bottom-to-top) via an SVG transform.
        let laneLabeled = layout.lanes.contains { !$0.label.isEmpty }
        if laneLabeled {
            XCTAssertTrue(svg.contains("transform=\"rotate("), "lane title should be rotated")
        }
        // A dashed connector honors the dash flag.
        if layout.edges.contains(where: { $0.dashed }) {
            XCTAssertTrue(svg.contains(#"stroke-dasharray="4 3""#), "dashed connector should dash")
        }
    }

    // MARK: Sankey

    func testSankeySceneAndSVG() throws {
        let source = """
        sankey-beta

        A,B,10
        A,C,5
        B,D,10
        C,D,5
        """
        guard let diagram = MermaidParser.parse(source) else {
            throw XCTSkip("source did not parse")
        }
        guard case .sankey(let sankey) = diagram else {
            return XCTFail("a sankey source should lower to a sankey diagram")
        }
        let layout = DiagramLayoutEngine.layout(sankey, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A ribbon per link + a bar per node.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.links.count + layout.nodes.count)
        // A label per named node.
        XCTAssertGreaterThanOrEqual(c.texts, layout.nodes.filter { !$0.label.isEmpty }.count)

        let svg = assertWellFormedSVG(scene)
        // Flow ribbons lower to filled quad-curve paths.
        XCTAssertTrue(svg.contains("<path"), "sankey ribbon should render as a path")
        XCTAssertTrue(svg.contains(" Q "), "ribbon edges should use quad-curve verbs")
    }

    // MARK: Requirement

    func testRequirementSceneAndSVG() throws {
        let source = """
        requirementDiagram
            requirement r1 {
                id: R1
                text: The system shall work
                risk: high
                verifymethod: test
            }
            element e1 {
                type: module
            }
            e1 - satisfies -> r1
        """
        guard let diagram = MermaidParser.parse(source) else {
            throw XCTSkip("source did not parse")
        }
        guard case .requirement(let req) = diagram else {
            return XCTFail("a requirement source should lower to a requirement diagram")
        }
        let layout = DiagramLayoutEngine.layout(req, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        XCTAssertGreaterThanOrEqual(c.shapes, layout.boxes.count, "one box per requirement/element")
        // Each populated box draws a full-width hairline separator polyline.
        let separators = scene.elements.filter {
            guard case .polyline(let p) = $0, p.points.count == 2 else { return false }
            return p.points[0].y == p.points[1].y && p.points[0].x != p.points[1].x
        }
        XCTAssertGreaterThanOrEqual(separators.count, layout.boxes.count,
                                    "each box draws a compartment separator")

        let svg = assertWellFormedSVG(scene)
        // The typed relation label renders on a chip.
        XCTAssertTrue(svg.contains(">satisfies<"), "relation type should render as text")
        XCTAssertTrue(svg.contains(">«element»<") || svg.contains("element"), "stereotype should render")
    }

    // MARK: - Phase 0b-3a chart families

    // MARK: Pie

    func testPieSceneAndSVG() throws {
        let source = """
        pie title Pets
            "Dogs" : 40
            "Cats" : 35
            "Birds" : 25
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .pie(let pie) = diagram else { return XCTFail("expected a pie diagram") }
        let layout = DiagramLayoutEngine.layout(pie, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A wedge shape and a legend swatch per slice.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.slices.count * 2)
        // A legend label per slice (+ optional title).
        XCTAssertGreaterThanOrEqual(c.texts, layout.slices.count)
        // A canvas-colored separator polyline per slice.
        XCTAssertGreaterThanOrEqual(c.polylines, layout.slices.count)

        let svg = assertWellFormedSVG(scene)
        // Wedges lower to quad-approximated arc paths.
        XCTAssertTrue(svg.contains("<path"), "pie wedge should render as a path")
        XCTAssertTrue(svg.contains(" Q "), "wedge rim should use quad-curve verbs")
        // Legend labels carry a rounded percentage.
        XCTAssertTrue(svg.contains("%)"), "legend should show a percentage")
    }

    // MARK: Gantt

    func testGanttSceneAndSVG() throws {
        let source = """
        gantt
            title Plan
            dateFormat YYYY-MM-DD
            section A
            Task one :done, t1, 2026-01-01, 3d
            Mark :milestone, m1, 2026-01-04, 0d
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .gantt(let gantt) = diagram else { return XCTFail("expected a gantt diagram") }
        let layout = DiagramLayoutEngine.layout(gantt, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A bar/diamond shape per task (section bands add more).
        XCTAssertGreaterThanOrEqual(c.shapes, layout.bars.count)
        XCTAssertGreaterThanOrEqual(c.texts, layout.bars.filter { !$0.label.isEmpty }.count)

        let svg = assertWellFormedSVG(scene)
        // The milestone lowers to a diamond polygon.
        XCTAssertTrue(layout.bars.contains { $0.isMilestone }, "fixture should have a milestone")
        XCTAssertTrue(svg.contains("<polygon"), "milestone should render as a polygon")
        XCTAssertTrue(svg.contains(">Plan<"), "title should render")
    }

    // MARK: Timeline

    func testTimelineSceneAndSVG() throws {
        let source = """
        timeline
            title History
            section One
                2020 : Alpha : Beta
                2021 : Gamma
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .timeline(let timeline) = diagram else { return XCTFail("expected a timeline diagram") }
        let layout = DiagramLayoutEngine.layout(timeline, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        let eventCount = layout.periods.reduce(0) { $0 + $1.events.count }
        // A dot per period + fill/stroke per event card.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.periods.count + eventCount)
        // The spine is at least one polyline.
        XCTAssertGreaterThanOrEqual(c.polylines, 1)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains(">Alpha<"), "an event label should render")
    }

    // MARK: Journey

    func testJourneySceneAndSVG() throws {
        let source = """
        journey
            title My Day
            section Work
              Code : 5: Me
              Email : 2: Me, Boss
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .journey(let journey) = diagram else { return XCTFail("expected a journey diagram") }
        let layout = DiagramLayoutEngine.layout(journey, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A score badge ellipse per task.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.tasks.count)
        // A score digit + label per task.
        XCTAssertGreaterThanOrEqual(c.texts, layout.tasks.count * 2)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains("<ellipse"), "score badge should render as an ellipse")
        XCTAssertTrue(svg.contains(">Code<"), "a task label should render")
    }

    // MARK: Quadrant

    func testQuadrantSceneAndSVG() throws {
        let source = """
        quadrantChart
            title Q
            x-axis Low --> High
            y-axis Bad --> Good
            quadrant-1 Do
            quadrant-2 Plan
            Alpha: [0.3, 0.6]
            Beta: [0.7, 0.8]
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .quadrant(let quadrant) = diagram else { return XCTFail("expected a quadrant diagram") }
        let layout = DiagramLayoutEngine.layout(quadrant, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // Four tint quarters + a plot border + a dot per point.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.quadrantRects.count + 1 + layout.points.count)
        // The center cross is two polylines.
        XCTAssertGreaterThanOrEqual(c.polylines, 2)

        let svg = assertWellFormedSVG(scene)
        // y-axis labels render rotated.
        XCTAssertTrue(svg.contains(#"transform="rotate("#), "y-axis label should be rotated")
        XCTAssertTrue(svg.contains(">Alpha<"), "a point label should render")
    }

    // MARK: XYChart

    func testXYChartSceneAndSVG() throws {
        let source = """
        xychart-beta
            title Sales
            x-axis [jan, feb, mar]
            y-axis "Rev" 0 --> 30
            bar [10, 20, 30]
            line [5, 15, 25]
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .xychart(let xychart) = diagram else { return XCTFail("expected an xychart diagram") }
        let layout = DiagramLayoutEngine.layout(xychart, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A rect per bar + a dot per line vertex.
        let vertexCount = layout.lines.reduce(0) { $0 + $1.points.count }
        XCTAssertGreaterThanOrEqual(c.shapes, layout.bars.count + vertexCount)
        // Gridlines + the axis frame + each line series are polylines.
        XCTAssertGreaterThanOrEqual(c.polylines, layout.yLabels.count + 1)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains("<polyline"), "line series/gridlines should render as polylines")
        XCTAssertFalse(layout.bars.isEmpty, "fixture should have a bar series")
    }

    // MARK: Radar

    func testRadarSceneAndSVG() throws {
        let source = """
        radar-beta
            title Skills
            axis a["A"], b["B"], c["C"]
            curve x["X"]{a: 3, b: 4, c: 2}
            curve y["Y"]{a: 5, b: 1, c: 4}
            max 5
            ticks 4
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .radar(let radar) = diagram else { return XCTFail("expected a radar diagram") }
        let layout = DiagramLayoutEngine.layout(radar, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // Rings + curves lower to polygons; vertex dots + legend swatches add ellipses.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.rings.count + layout.curves.count)
        // A spoke polyline per axis.
        XCTAssertGreaterThanOrEqual(c.polylines, layout.spokes.count)

        let svg = assertWellFormedSVG(scene)
        let polygons = countOccurrences(of: "<polygon", in: svg)
        XCTAssertGreaterThanOrEqual(polygons, layout.rings.count + layout.curves.count,
                                    "rings and curves should render as polygons")
    }

    // MARK: Packet

    func testPacketSceneAndSVG() throws {
        let source = """
        packet-beta
        title Header
        0-15: "Source"
        16-31: "Dest"
        32: "F"
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .packet(let packet) = diagram else { return XCTFail("expected a packet diagram") }
        let layout = DiagramLayoutEngine.layout(packet, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A fill + a border shape per bit-field segment.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.segments.count * 2)
        // A start-bit index per segment (plus labels/end indices).
        XCTAssertGreaterThanOrEqual(c.texts, layout.segments.count)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains(">Source<"), "a field label should render")
    }

    // MARK: Kanban

    func testKanbanSceneAndSVG() throws {
        let source = """
        kanban
          todo[To Do]
            c1[Do a thing]@{ ticket: MK-1 }
          done[Done]
            c2[Finished]@{ ticket: MK-2 }
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .kanban(let kanban) = diagram else { return XCTFail("expected a kanban diagram") }
        let layout = DiagramLayoutEngine.layout(kanban, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A header pill per column + a body and rail per card.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.columns.count + layout.cards.count * 2)
        // A column title per column.
        XCTAssertGreaterThanOrEqual(c.texts, layout.columns.count)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains(">To Do<"), "a column title should render")
    }

    // MARK: Mindmap (Phase 0b-3b)

    func testMindmapSceneAndSVG() throws {
        let source = """
        mindmap
          root((Root))
            Parsing
              Headers
            Layout
              Ordering
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .mindmap(let mindmap) = diagram else { return XCTFail("expected a mindmap") }
        let layout = DiagramLayoutEngine.layout(mindmap, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A node shape per node (deeper nodes add a stroke shape) + a curved
        // connector shape per edge; a label per node.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.nodes.count + layout.edges.count)
        XCTAssertGreaterThanOrEqual(c.texts, layout.nodes.count)
        XCTAssertFalse(layout.edges.isEmpty, "fixture should have branch connectors")

        let svg = assertWellFormedSVG(scene)
        // Curved branch connectors lower to quad-approximated paths.
        XCTAssertTrue(svg.contains("<path"), "a branch connector should render as a path")
        XCTAssertTrue(svg.contains(" Q "), "connector should use quad-curve verbs")
        XCTAssertTrue(svg.contains(">Root<"), "the root label should render")
    }

    // MARK: Treemap

    func testTreemapSceneAndSVG() throws {
        let source = """
        treemap
            "Root"
                "Group"
                    "Leaf A": 30
                    "Leaf B": 20
                "Other": 50
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .treemap(let treemap) = diagram else { return XCTFail("expected a treemap") }
        let layout = DiagramLayoutEngine.layout(treemap, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A rect per cell (leaves fill+stroke in one shape, groups outline).
        XCTAssertGreaterThanOrEqual(c.shapes, layout.cells.count)
        // The fixture nests a group inside the root.
        XCTAssertTrue(layout.cells.contains { !$0.isLeaf }, "fixture should have a group cell")

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains("<rect"), "cells should render as rects")
    }

    // MARK: Tree view

    func testTreeViewSceneAndSVG() throws {
        let source = """
        treeView-beta
            Root/
                File.swift ## a leaf
                Sub/
                    Deep.swift
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .treeView(let tree) = diagram else { return XCTFail("expected a treeView") }
        let layout = DiagramLayoutEngine.layout(tree, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A glyph (1–2 shapes) per row; a label per row.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.rows.count)
        XCTAssertGreaterThanOrEqual(c.texts, layout.rows.count)
        // Elbow guide lines connect children to parents.
        XCTAssertGreaterThanOrEqual(c.polylines, 1)

        let svg = assertWellFormedSVG(scene)
        // The file glyph is a folded-corner path.
        XCTAssertTrue(svg.contains("<path"), "a file glyph should render as a path")
        XCTAssertTrue(svg.contains(">File.swift<"), "a row label should render")
    }

    // MARK: Venn

    func testVennSceneAndSVG() throws {
        let source = """
        venn-beta
            set a ["Alpha"] : 3
            set b ["Beta"] : 3
            union a, b ["both"]
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .venn(let venn) = diagram else { return XCTFail("expected a venn") }
        let layout = DiagramLayoutEngine.layout(venn, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A translucent fill and a rim per circle.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.circles.count * 2)
        // A label per set + per overlap region.
        XCTAssertGreaterThanOrEqual(c.texts, layout.regionLabels.count)

        let svg = assertWellFormedSVG(scene)
        let ellipses = countOccurrences(of: "<ellipse", in: svg)
        XCTAssertGreaterThanOrEqual(ellipses, layout.circles.count * 2,
                                    "each set should render a fill + rim ellipse")
    }

    // MARK: Cynefin

    func testCynefinSceneAndSVG() throws {
        let source = """
        cynefin-beta
            title Framework
            clear
                "Simple item"
            complicated
                "Analyze it"
            complex
                "Probe it"
            chaotic
                "Act now"
            chaotic --> clear : "recover"
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .cynefin(let cynefin) = diagram else { return XCTFail("expected a cynefin") }
        let layout = DiagramLayoutEngine.layout(cynefin, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A tint fill per quadrant.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.quadrants.count)
        // A transition arrow is a polyline.
        XCTAssertGreaterThanOrEqual(c.polylines, layout.transitions.count)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains(">Framework<"), "the title should render")
        // A transition arrow realizes a filled arrowhead polygon.
        if !layout.transitions.isEmpty {
            XCTAssertTrue(svg.contains("<polygon"), "a transition should render an arrowhead")
        }
    }

    // MARK: Wardley

    func testWardleySceneAndSVG() throws {
        let source = """
        wardley-beta
            title Map
            anchor User [0.95, 0.6]
            component Site [0.7, 0.5]
            component Platform [0.4, 0.3] (build)
            User -> Site
            Site -> Platform
            evolve Platform 0.6
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .wardley(let wardley) = diagram else { return XCTFail("expected a wardley") }
        let layout = DiagramLayoutEngine.layout(wardley, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A dot per component + the evolve target dots.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.nodes.count)
        // Links + band dividers are polylines.
        XCTAssertGreaterThanOrEqual(c.polylines, layout.links.count)

        let svg = assertWellFormedSVG(scene)
        // The "Value Chain" y-axis label renders rotated.
        XCTAssertTrue(svg.contains(#"transform="rotate("#), "the value-chain axis should be rotated")
        XCTAssertTrue(svg.contains(">Map<"), "the title should render")
    }

    // MARK: Ishikawa

    func testIshikawaSceneAndSVG() throws {
        let source = """
        ishikawa-beta
            Effect
                Cause A
                    Sub one
                Cause B
                Cause C
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .ishikawa(let ishikawa) = diagram else { return XCTFail("expected an ishikawa") }
        let layout = DiagramLayoutEngine.layout(ishikawa, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // The head problem box is a shape; ribs add labels.
        XCTAssertGreaterThanOrEqual(c.shapes, 1)
        // The spine + a rib per major cause are polylines.
        XCTAssertGreaterThanOrEqual(c.polylines, layout.ribs.count + 1)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains(">Effect<"), "the problem head should render")
        // The spine arrowhead is a filled polygon.
        XCTAssertTrue(svg.contains("<polygon"), "the spine should render an arrowhead")
    }

    // MARK: Event modeling

    func testEventModelingSceneAndSVG() throws {
        let source = """
        eventmodeling
            tf 1 ui View
            tf 2 command Request
            tf 3 event Parsed
            tf 4 readmodel Result
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .eventModeling(let em) = diagram else { return XCTFail("expected event modeling") }
        let layout = DiagramLayoutEngine.layout(em, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A band per lane + a card per frame.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.lanes.count + layout.frames.count)
        // A lane name per lane + an entity per frame.
        XCTAssertGreaterThanOrEqual(c.texts, layout.lanes.count + layout.frames.count)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains(">View<"), "a card entity should render")
    }

    // MARK: ZenUML

    func testZenUMLSceneAndSVG() throws {
        let source = """
        zenuml
            title Flow
            @Actor User
            @Control Service
            User->Service: request
            Service->Service: work
            Service->User: reply
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .zenuml(let zenuml) = diagram else { return XCTFail("expected a zenuml") }
        let layout = DiagramLayoutEngine.layout(zenuml, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A participant box per participant.
        XCTAssertGreaterThanOrEqual(c.shapes, layout.participants.count)
        // A dashed lifeline per participant + an arrow shaft per message.
        XCTAssertGreaterThanOrEqual(c.polylines, layout.participants.count + layout.arrows.count)

        let svg = assertWellFormedSVG(scene)
        XCTAssertTrue(svg.contains(">Flow<"), "the title should render")
        // Dashed lifelines carry a dash pattern.
        XCTAssertTrue(svg.contains("stroke-dasharray"), "lifelines should be dashed")
    }

    // MARK: Git graph

    func testGitGraphSceneAndSVG() throws {
        let source = """
        gitGraph
            commit id: "first"
            commit id: "tagged" tag: "v1.0.0"
            branch feature
            commit id: "work"
            checkout main
            merge feature
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "supported fixture must parse")
        guard case .gitGraph(let git) = diagram else { return XCTFail("expected a git graph") }
        let layout = DiagramLayoutEngine.layout(git, measure: measure)
        let scene = RenderScene.from(layout, theme: theme, measure: measure)

        XCTAssertEqual(scene.size, layout.size)
        let c = counts(scene)
        // A dot per commit (merges add a canvas core).
        XCTAssertGreaterThanOrEqual(c.shapes, layout.commits.count)

        let svg = assertWellFormedSVG(scene)
        let ellipses = countOccurrences(of: "<ellipse", in: svg)
        XCTAssertGreaterThanOrEqual(ellipses, layout.commits.count, "each commit should render a dot")
        XCTAssertTrue(svg.contains(">v1.0.0<"), "a commit tag should render")
    }

    // MARK: Full coverage

    /// Phase 0b-3b completes the ~30-family coverage: the dispatcher must now
    /// return a non-nil scene for EVERY fixture — no diagram type falls through.
    /// Drives every `Fixtures/diagrams/*.mmd`, so a new family added without a
    /// lowering breaks this test.
    func testDispatcherLowersEveryFixture() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
        XCTAssertGreaterThanOrEqual(files.count, 30, "expected the full fixture corpus")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let diagram = try XCTUnwrap(MermaidParser.parse(source),
                                        "fixture must parse: \(file.lastPathComponent)")
            let scene = RenderScene.from(diagram, theme: theme, measure: measure)
            XCTAssertNotNil(scene, "every diagram type must lower: \(file.lastPathComponent)")
            // The scene must actually contain drawn elements, and be a
            // well-formed SVG (an empty scene still emits an <svg> wrapper).
            if let scene {
                XCTAssertFalse(scene.elements.isEmpty,
                               "scene must have rendered elements: \(file.lastPathComponent)")
                let svg = SVGRenderer.svg(scene)
                XCTAssertTrue(svg.hasPrefix("<svg"), "SVG for \(file.lastPathComponent)")
                XCTAssertTrue(svg.contains("</svg>"), "SVG close for \(file.lastPathComponent)")
            }
        }
    }

    // MARK: Helpers

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    /// The first shape whose geometry is bounded by (or equal to) `frame` —
    /// enough to identify which ShapePath a given node produced.
    private func firstShapePath(in scene: RenderScene, matching frame: CGRect) -> RenderScene.ShapePath? {
        for element in scene.elements {
            guard case .shape(let shape) = element else { continue }
            let box = boundingBox(of: shape.path)
            if approxEqual(box, frame) { return shape.path }
        }
        return nil
    }

    private func boundingBox(of path: RenderScene.ShapePath) -> CGRect {
        switch path {
        case .roundedRect(let r, _): return r
        case .ellipse(let r): return r
        case .polygon(let pts):
            let xs = pts.map(\.x), ys = pts.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .path(let verbs):
            var pts: [CGPoint] = []
            for v in verbs {
                switch v {
                case .move(let p), .line(let p): pts.append(p)
                case .quad(let to, _): pts.append(to)
                case .close: break
                }
            }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private func approxEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 2) -> Bool {
        abs(a.midX - b.midX) < tol && abs(a.midY - b.midY) < tol
    }
}
