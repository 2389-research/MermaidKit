import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Every line break the raster path honors — any `<br…>` tag, a literal `\n`,
/// a real newline — must break the line in the ``RenderScene`` too, so SVG,
/// SceneWire and the platform renderers draw the lines the image draws instead
/// of the literal markup (#71). The scene carries one `Text` per visual line,
/// stacked exactly as `DiagramRenderer.drawText` stacks them.
final class SceneLineBreakTests: XCTestCase {

    /// Line height is `size + 4`, so the expected pitch is exact.
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
        palette: [DiagramColor(hex: 0x5B8FF9), DiagramColor(hex: 0x61DDAA)])

    private func texts(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws -> [RenderScene.Text] {
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "failed to parse", file: file, line: line)
        let scene = try XCTUnwrap(RenderScene.from(diagram, theme: theme, measure: measure),
                                  "failed to lower", file: file, line: line)
        let svg = SVGRenderer.svg(scene)
        XCTAssertFalse(svg.lowercased().contains("&lt;br"), "SVG draws a <br> literally", file: file, line: line)
        return scene.elements.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
    }

    /// No scene text still holds a break, and each `group` appears as separate
    /// runs sharing one x and one font size, one line height apart.
    private func assertLines(_ source: String, _ groups: [[String]],
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let all = try texts(source, file: file, line: line)
        for t in all {
            XCTAssertEqual(DiagramLayoutEngine.brLines(t.string), [t.string],
                           "scene text \(t.string.debugDescription) still carries a line break",
                           file: file, line: line)
        }
        for group in groups {
            let runs = group.compactMap { s in all.first { $0.string == s } }
            guard runs.count == group.count else {
                XCTFail("lines \(group) not all in the scene: \(all.map(\.string))", file: file, line: line)
                continue
            }
            for (a, b) in zip(runs, runs.dropFirst()) {
                XCTAssertEqual(a.center.x, b.center.x, accuracy: 0.001, "\(group): lines share x", file: file, line: line)
                XCTAssertEqual(a.fontSize, b.fontSize, "\(group): lines share a size", file: file, line: line)
                XCTAssertEqual(b.center.y - a.center.y, a.fontSize + 4, accuracy: 0.001,
                               "\(group): lines stack one line height apart", file: file, line: line)
            }
        }
    }

    func testFlowchartLabelsBreak() throws {
        try assertLines("""
        flowchart TD
            A[one<br/>two] --> B[three<br>four]
            A -->|five<br/>six| B
            B --> C[seven&#8232;eight]
            C --> D[nine\\nten]
        """, [["one", "two"], ["three", "four"], ["five", "six"], ["seven", "eight"], ["nine", "ten"]])
    }

    func testClassLabelsBreak() throws {
        try assertLines("""
        classDiagram
            class Animal
            Animal : +one<br/>two
            Animal --> Dog : three<br>four
            Dog : +five\\nsix
        """, [["+one", "two"], ["three", "four"], ["+five", "six"]])
    }

    func testStateLabelsBreak() throws {
        try assertLines("""
        stateDiagram-v2
            state "one<br/>two" as s1
            state "five\\nsix" as s3
            s1 --> s2 : three<br>four
            s2 --> s3
        """, [["one", "two"], ["three", "four"], ["five", "six"]])
    }

    /// The three lines of a block center on the block's center, as drawText
    /// centers them: the middle line sits on the node's center.
    func testBlockCentersOnTheLabelCenter() throws {
        let source = "flowchart TD\n    A[one<br/>two<br/>three]"
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else {
            return XCTFail("did not parse as a flowchart")
        }
        let frame = try XCTUnwrap(DiagramLayoutEngine.layout(chart, measure: measure).nodes.first).frame
        let broken = try texts(source)
        let one = try XCTUnwrap(broken.first { $0.string == "one" })
        let two = try XCTUnwrap(broken.first { $0.string == "two" })
        let three = try XCTUnwrap(broken.first { $0.string == "three" })
        XCTAssertEqual(two.center.y, (one.center.y + three.center.y) / 2, accuracy: 0.001)
        XCTAssertEqual(two.center.y, frame.midY, accuracy: 0.001)
        XCTAssertEqual(two.center.x, frame.midX, accuracy: 0.001)
    }

    /// The shared split itself, on what a source can't always spell: real
    /// newlines of every form, and a rotated run (a swimlane title), whose
    /// lines stack along its own turned axis as drawTextRotated stacks them.
    func testSharedSplitHandlesRealNewlinesAndRotation() {
        let base = RenderScene.Text(string: "", center: CGPoint(x: 100, y: 50), fontSize: 10,
                                    color: theme.ink, backing: theme.canvas)
        for string in ["one\ntwo", "one\r\ntwo", "one\u{2028}two", " one <br/>\n two "] {
            var text = base
            text.string = string
            let runs = RenderScene.lines(of: text, measure: measure)
            XCTAssertEqual(runs.map(\.string), ["one", "two"], string.debugDescription)
            XCTAssertEqual(runs.map(\.center), [CGPoint(x: 100, y: 43), CGPoint(x: 100, y: 57)])
            XCTAssertEqual(runs.map(\.backing), [theme.canvas, theme.canvas], "chip kept per line")
        }
        var rotated = base
        rotated.string = "one<br>two"
        rotated.rotation = -.pi / 2
        let runs = RenderScene.lines(of: rotated, measure: measure)
        XCTAssertEqual(runs[0].center.x, 93, accuracy: 0.001)
        XCTAssertEqual(runs[1].center.x, 107, accuracy: 0.001)
        XCTAssertEqual(runs[0].center.y, 50, accuracy: 0.001)
        XCTAssertEqual(runs.map(\.rotation), [-.pi / 2, -.pi / 2])

        var plain = base
        plain.string = "  unbroken  "
        XCTAssertEqual(RenderScene.lines(of: plain, measure: measure).map(\.string), ["  unbroken  "],
                       "a run without a break is untouched, as drawText leaves it")
    }

    /// Breaks alone draw nothing, as in the raster path; no empty run remains.
    /// A chipped label (an edge label on its canvas-colored chip) that breaks
    /// gets ONE chip behind the whole block, as the raster draws it, sized to
    /// the block plus the 3pt pad; its lines carry no chip of their own, which
    /// would paint over the descenders of the line above.
    func testAChippedLabelGetsOneChipForTheBlock() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("flowchart TD\n  A -->|gyp<br/>qjy| B"))
        let scene = try XCTUnwrap(RenderScene.from(diagram, theme: theme, measure: measure))
        let lines = scene.elements.compactMap { e -> RenderScene.Text? in
            if case .text(let t) = e, ["gyp", "qjy"].contains(t.string) { return t } else { return nil }
        }
        XCTAssertEqual(lines.map(\.string), ["gyp", "qjy"])
        XCTAssertTrue(lines.allSatisfy { $0.backing == nil }, "lines carry no chip of their own")
        let first = try XCTUnwrap(scene.elements.firstIndex { if case .text(let t) = $0 { t.string == "gyp" } else { false } })
        guard case .shape(let chip) = scene.elements[first - 1], case .roundedRect(let rect, _) = chip.path else {
            return XCTFail("one chip shape right before the lines")
        }
        XCTAssertEqual(chip.fill, theme.canvas)
        let size = lines[0].fontSize
        XCTAssertEqual(rect.width, 3 * size * 0.6 + 6, accuracy: 0.001)
        XCTAssertEqual(rect.height, 2 * (size + 4) + 6, accuracy: 0.001)
        XCTAssertEqual(rect.midY, (lines[0].center.y + lines[1].center.y) / 2, accuracy: 0.001)
    }

    /// A chipped label that is only breaks draws no text, but still masks
    /// the edge with its chip, as the raster does (one empty line's height).
    func testABreakOnlyChippedLabelKeepsItsChip() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("flowchart TD\n  A -->|<br/>| B"))
        let scene = try XCTUnwrap(RenderScene.from(diagram, theme: theme, measure: measure))
        let chips = scene.elements.compactMap { e -> CGRect? in
            if case .shape(let s) = e, s.fill == theme.canvas, s.stroke == nil, case .roundedRect(let r, _) = s.path { return r }
            return nil
        }
        // One empty line, padded: this measurer gives "" a 0.6em width and a
        // size+4 height, so the chip's size pins its font size.
        XCTAssertEqual(chips.count, 1, "the chip stays: \(chips)")
        let chip = try XCTUnwrap(chips.first)
        let size = (chip.width - 6) / 0.6
        XCTAssertEqual(chip.height, measure("", Double(size)).height + 6, accuracy: 0.001)
    }

    /// `<BR>` and `<Br/>` break too, in the scene as in `brLines` (the quick
    /// test before the split was case-sensitive, so they drew literally).
    func testAnyCaseBreakTagBreaks() throws {
        try assertLines("flowchart TD\n  A[one<BR>two] --> B[three<Br/>four]", [["one", "two"], ["three", "four"]])
        XCTAssertTrue(DiagramLayoutEngine.hasLineBreak("a<BR>b"))
        XCTAssertFalse(DiagramLayoutEngine.hasLineBreak("a brb"))
    }

    func testBreaksOnlyDrawNothing() throws {
        let all = try texts("flowchart TD\n    A --> B\n    A -->|<br/>| B")
        XCTAssertFalse(all.contains { $0.string.isEmpty || $0.string.contains("<br") })
    }
}
