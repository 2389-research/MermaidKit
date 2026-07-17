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
