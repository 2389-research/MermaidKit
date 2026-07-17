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
        secondaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.55))

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
