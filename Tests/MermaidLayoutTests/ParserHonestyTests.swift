import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The honesty sprint's contract: syntax that used to be silently dropped or
/// — worse — corrupted into confident phantom content now parses to what the
/// author wrote. Each test uses the exact form that failed before.
final class ParserHonestyTests: XCTestCase {

    func testFrontMatterIsStripped() throws {
        let d = MermaidParser.parse("---\ntitle: Hello\nconfig:\n  theme: base\n---\nflowchart TD\n  A --> B")
        guard case .flowchart(let chart)? = d else { return XCTFail("front-matter killed the parse") }
        XCTAssertEqual(chart.edges.count, 1)
    }

    // MARK: flowchart

    private func flow(_ body: String) throws -> Flowchart {
        guard case .flowchart(let c)? = MermaidParser.parse("flowchart TD\n" + body) else {
            throw XCTSkip("parse failed: \(body)")
        }
        return c
    }

    func testChainedEdges() throws {
        let c = try flow("A --> B --> C")
        XCTAssertEqual(c.edges.count, 2, "chain must yield both edges")
        XCTAssertEqual(c.nodes.count, 3)
    }

    func testAmpersandFanOut() throws {
        let c = try flow("A & B --> C & D")
        XCTAssertEqual(c.edges.count, 4, "2x2 fan-out")
        XCTAssertEqual(c.nodes.map(\.id).sorted(), ["A", "B", "C", "D"])
    }

    func testAmpersandInsideLabelIsNotASplit() throws {
        let c = try flow("A[Tom & Jerry] --> B")
        XCTAssertEqual(c.edges.count, 1)
        XCTAssertEqual(c.nodes.first(where: { $0.id == "A" })?.label, "Tom & Jerry")
    }

    func testInlineEdgeLabel() throws {
        let c = try flow("A-- hello -->B")
        XCTAssertEqual(c.edges.first?.label, "hello")
    }

    /// Node re-declaration (issue #1, symptom 3): a later EXPLICIT declaration
    /// overrides both shape and label — mermaid.js's `addVertex` assigns
    /// `vertex.type = type` unconditionally when a shape is given and likewise
    /// overwrites the text. So `B{Decision}` then `B[Figga]` is a rectangle
    /// labelled "Figga", not a diamond. Deliberate and mermaid-faithful, not
    /// incidental.
    func testExplicitRedeclarationOverridesShapeAndLabel() throws {
        let c = try flow("A --> B{Decision}\nD -->|who| B[Figga]")
        let b = c.nodes.first { $0.id == "B" }
        XCTAssertEqual(b?.shape, .rectangle, "last explicit shape wins (mermaid parity)")
        XCTAssertEqual(b?.label, "Figga", "last explicit label wins")
    }

    /// A BARE back-reference (`... B`, no brackets) carries no shape or label,
    /// so it must NOT clobber an earlier `B{Decision}` — the diamond and its
    /// text survive. (This is why the reported cycle renders cleanly when B is
    /// left as a bare reference.)
    func testBareReferenceKeepsEarlierShape() throws {
        let c = try flow("A --> B{Decision}\nD -->|who| B")
        let b = c.nodes.first { $0.id == "B" }
        XCTAssertEqual(b?.shape, .diamond, "bare reference must not reshape")
        XCTAssertEqual(b?.label, "Decision", "bare reference must not relabel")
    }

    func testMinLengthLinksNormalize() throws {
        let c = try flow("A ----> B")
        XCTAssertEqual(c.edges.count, 1)
        XCTAssertEqual(c.edges.first?.hasArrow, true)
    }

    func testBidirectionalArrow() throws {
        let c = try flow("A <--> B")
        XCTAssertEqual(c.edges.first?.backArrow, true)
        XCTAssertEqual(c.nodes.map(\.id).sorted(), ["A", "B"], "no phantom 'A<' node")
    }

    func testCircleAndCrossHeadsDoNotMintPhantomNodes() throws {
        let c = try flow("A --o B\nC --x D")
        XCTAssertEqual(c.nodes.map(\.id).sorted(), ["A", "B", "C", "D"],
                       "'oB'/'xD' phantoms must not exist")
        XCTAssertEqual(c.edges.count, 2)
    }

    func testStyleClassSuffixTolerated() throws {
        let c = try flow("A:::hot --> B[Cool]:::cold")
        XCTAssertEqual(c.edges.count, 1)
        XCTAssertEqual(c.nodes.first(where: { $0.id == "B" })?.label, "Cool")
    }

    func testEdgeIDDropped() throws {
        let c = try flow("A e1@--> B")
        XCTAssertEqual(c.edges.count, 1, "edge id must not kill the line")
    }

    /// Ids with `-` and `.` between word characters. The whole line used to
    /// vanish: `api-gateway` stopped at `api`, failing the endpoint.
    func testIdsWithDashesAndDots() throws {
        let c = try flow("api-gateway[API gateway] --> auth.service[Auth] --> db[(Postgres)]")
        XCTAssertEqual(c.nodes.map(\.id), ["api-gateway", "auth.service", "db"])
        XCTAssertEqual(c.nodes.first?.label, "API gateway")
        XCTAssertEqual(c.edges.count, 2)
    }

    /// `{{…}}` and `[[…]]`. `{{Redis}}` was a diamond labelled "{Redis}", and
    /// `[[Worker]]` a rectangle labelled "[Worker]".
    func testHexagonAndSubroutine() throws {
        let c = try flow("cache{{Redis}} --> sub[[Worker]]")
        XCTAssertEqual(c.nodes.first { $0.id == "cache" }?.shape, .hexagon)
        XCTAssertEqual(c.nodes.first { $0.id == "cache" }?.label, "Redis")
        XCTAssertEqual(c.nodes.first { $0.id == "sub" }?.shape, .subroutine)
        XCTAssertEqual(c.nodes.first { $0.id == "sub" }?.label, "Worker")
    }

    /// Mermaid's `id@{ shape: …, label: … }` form. The `@{…}` endpoint used to
    /// drop the whole edge line.
    func testShapeDataSyntax() throws {
        let c = try flow("A[Start] --> B@{ shape: diam, label: \"Decide, then go\" }\nC@{ shape: cyl }\nD@{ label: \"Plain\" }")
        let b = c.nodes.first { $0.id == "B" }
        XCTAssertEqual(b?.shape, .diamond)
        XCTAssertEqual(b?.label, "Decide, then go", "a quoted comma isn't a field separator")
        XCTAssertEqual(c.edges.count, 1)
        XCTAssertEqual(c.nodes.first { $0.id == "C" }?.shape, .cylinder)
        XCTAssertEqual(c.nodes.first { $0.id == "C" }?.label, "C", "no label: the id")
        XCTAssertEqual(c.nodes.first { $0.id == "D" }?.shape, .rectangle)
        XCTAssertEqual(c.nodes.first { $0.id == "D" }?.label, "Plain")
    }

    /// Double circles, the slanted shapes and the asymmetric flag. They were
    /// a circle and rectangles.
    func testDoubleCircleSlantedAndFlagShapes() throws {
        let c = try flow("a(((Done))) --> b>Flag] --> c[/In/] --> d[\\Out\\] --> e[/Wide\\] --> f[\\Narrow/]")
        XCTAssertEqual(c.edges.count, 5)
        XCTAssertEqual(c.nodes.map(\.label), ["Done", "Flag", "In", "Out", "Wide", "Narrow"])
        XCTAssertEqual(c.nodes.map(\.shape),
                       [.doubleCircle, .asymmetric, .parallelogram, .parallelogramAlt, .trapezoid, .trapezoidAlt])
    }

    /// The same shapes by their `@{ shape: … }` names and aliases.
    func testShapeDataNamesForTheNewShapes() throws {
        let c = try flow("""
            a@{ shape: dbl-circ }
            b@{ shape: lean-r }
            c@{ shape: out-in }
            d@{ shape: priority }
            e@{ shape: trap-t }
            f@{ shape: odd }
            """)
        XCTAssertEqual(c.nodes.map(\.shape),
                       [.doubleCircle, .parallelogram, .parallelogramAlt, .trapezoid, .trapezoidAlt, .asymmetric])
    }

    /// Thick, dotted and invisible links. `===` and `~~~` used to drop their
    /// line, and `==>` drew like `-->`.
    func testLinkStrokes() throws {
        let c = try flow("A ==> B\nB === C\nC ~~~ D\nD -.- E\nE --> F")
        XCTAssertEqual(c.edges.count, 5)
        let e = c.edges
        XCTAssertTrue(e[0].thick && e[0].hasArrow && !e[0].dashed)
        XCTAssertTrue(e[1].thick && !e[1].hasArrow)
        XCTAssertTrue(e[2].invisible && !e[2].hasArrow && !e[2].thick)
        XCTAssertTrue(e[3].dashed && !e[3].hasArrow && !e[3].thick)
        XCTAssertFalse(e[4].thick || e[4].invisible || e[4].dashed)
    }

    /// Circle and cross heads, at one end or both, on every stroke and with
    /// inline text. They were plain arrows, and `-.-x`, `==o` dropped the line.
    func testCircleAndCrossHeads() throws {
        let c = try flow("""
            A --o B
            B --x C
            C o--o D
            D x--x E
            E <--> F
            F -.-x G
            G ==o H
            H -- yes --o I
            """)
        XCTAssertEqual(c.edges.count, 8)
        let heads = c.edges.map { "\($0.head) \($0.hasArrow) \($0.backArrow)" }
        XCTAssertEqual(heads, [
            "circle true false", "cross true false", "circle true true", "cross true true",
            "arrow true true", "cross true false", "circle true false", "circle true false",
        ])
        XCTAssertTrue(c.edges[5].dashed)
        XCTAssertTrue(c.edges[6].thick)
        XCTAssertEqual(c.edges[7].label, "yes")
    }

    /// An `o` or `x` that's an id stays one: a head needs a link right after
    /// it (or before it), and a start head must match the end's.
    func testNodesNamedOAndX() throws {
        let c = try flow("o --> x\nx-->o\nq --o o")
        XCTAssertEqual(c.nodes.map(\.id), ["o", "x", "q"])
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to) \($0.head) \($0.backArrow)" },
                       ["o>x arrow false", "x>o arrow false", "q>o circle false"])
    }

    /// A chain of open links is two links, not one with the middle node as
    /// inline text: the `-- text ---` reading once matched from the second
    /// dash of the first `---` and swallowed `B`.
    func testOpenLinkChainsKeepTheirMiddleNode() throws {
        for (source, thick) in [("A --- B --- C", false), ("A === B === C", true),
                                ("A --- B --> C", false), ("A ---- B --- C", false)] {
            let c = try flow(source)
            XCTAssertEqual(c.nodes.map(\.id), ["A", "B", "C"], source)
            XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["A>B", "B>C"], source)
            XCTAssertEqual(c.edges.map(\.label), [nil, nil], source)
            XCTAssertEqual(c.edges[0].thick, thick, source)
        }
        // Inline text on an open link still reads as text.
        let text = try flow("A -- yes --- B")
        XCTAssertEqual(text.edges.map(\.label), ["yes"])
    }

    /// An `@` in a label is text; only `id@` directly before a link is an
    /// edge id. Stripping once ate `ops@` before `xmail`.
    func testAtSignsInLabelsAreText() throws {
        let c = try flow("A -->|ping ops@xmail.com| B\nC[mail joe@outlook.com] --> D\nE e1@--> F\nG e2@--o H\nI e3@~~~ J")
        XCTAssertEqual(c.edges.map(\.label), ["ping ops@xmail.com", nil, nil, nil, nil])
        XCTAssertEqual(c.nodes.first { $0.id == "C" }?.label, "mail joe@outlook.com")
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["A>B", "C>D", "E>F", "G>H", "I>J"])
        XCTAssertEqual(c.edges[3].head, .circle)
        XCTAssertTrue(c.edges[4].invisible)
    }

    /// A start head that doesn't match the end (`<---`, `<--o`, `o-->`) is one
    /// mermaid rejects; we degrade to the link without it rather than drop
    /// the line.
    func testMismatchedStartHeadDegradesToTheLink() throws {
        let c = try flow("A <--- B\nC <--o D\nE o--> F\nG x--o H")
        XCTAssertEqual(c.nodes.map(\.id), ["A", "B", "C", "D", "E", "F", "G", "H"])
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to) \($0.hasArrow) \($0.backArrow) \($0.head)" },
                       ["A>B false false arrow", "C>D true false circle",
                        "E>F true false arrow", "G>H true false circle"])
    }

    /// Extra `-`, `=`, `.` or `~` make a longer link, as in mermaid. They used
    /// to be normalized away.
    func testLinkLengths() throws {
        let c = try flow("""
            A --> B
            A ---> C
            A ----> D
            A ---- E
            A -..-> F
            A ===> G
            A ~~~~ H
            A -- text ---> I
            A \(String(repeating: "-", count: 50))> J
            """)
        XCTAssertEqual(c.edges.map(\.length), [1, 2, 3, 2, 2, 2, 2, 2, MermaidParser.maxLinkLength])
        XCTAssertEqual(c.edges[7].label, "text")
    }

    /// A longer link puts its target that many ranks down.
    func testLongerLinkSpansMoreRanks() throws {
        let c = try flow("A --> B\nA ---> C\nA ----> D")
        let layout = DiagramLayoutEngine.layout(c, measure: measure)
        let frame = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame) })
        let a = try XCTUnwrap(frame["A"]), b = try XCTUnwrap(frame["B"])
        let cc = try XCTUnwrap(frame["C"]), d = try XCTUnwrap(frame["D"])
        XCTAssertLessThan(a.maxY, b.minY)
        XCTAssertLessThan(b.maxY, cc.minY, "C is a rank below B")
        XCTAssertLessThan(cc.maxY, d.minY, "D is a rank below C")
    }

    /// `~~~` positions its nodes but draws nothing, so the linter and the alt
    /// text don't see it either. (The drawing is in `RenderSceneTests`.)
    func testInvisibleLinkPositionsButIsntDrawn() throws {
        let c = try flow("A ~~~ B\nB --> C")
        let layout = DiagramLayoutEngine.layout(c, measure: measure)
        let frame = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame) })
        XCTAssertLessThan(try XCTUnwrap(frame["A"]).maxY, try XCTUnwrap(frame["B"]).minY)
        XCTAssertEqual(DiagramScene.from(layout, measure: measure).edges.count, 1)
        XCTAssertTrue(MermaidAltText.describe(.flowchart(c)).contains("1 connection:"))
    }

    /// An invisible link ranks its nodes but never moves a drawn one: no face
    /// port spread for it, no run nudged aside, no label steered around it.
    /// Here it ranks nothing new, so the visible edge must match the chart
    /// without it exactly.
    func testInvisibleLinkDoesNotMoveVisibleEdges() throws {
        for direction in ["TD", "LR"] {
            let alone = DiagramLayoutEngine.layout(
                try flowIn(direction, "A -->|yes| B\nA --> C"), measure: measure)
            let with = DiagramLayoutEngine.layout(
                try flowIn(direction, "A -->|yes| B\nA --> C\nA ~~~ B"), measure: measure)
            XCTAssertEqual(with.nodes.map(\.frame), alone.nodes.map(\.frame), direction)
            for i in 0..<2 {
                XCTAssertEqual(with.edges[i].points, alone.edges[i].points, "\(direction) edge \(i)")
                XCTAssertEqual(with.edges[i].labelPoint, alone.edges[i].labelPoint, "\(direction) edge \(i)")
            }
        }
    }

    private func flowIn(_ direction: String, _ body: String) throws -> Flowchart {
        guard case .flowchart(let c)? = MermaidParser.parse("flowchart \(direction)\n" + body) else {
            throw XCTSkip("parse failed: \(body)")
        }
        return c
    }

    /// `>…]` closes a bracket it never opened; inside an `&` fan that once
    /// drove the splitter's depth negative, so the next `&` was swallowed
    /// into the flag's label and its endpoint dropped.
    func testFlagShapeInsideAFan() throws {
        let c = try flow("a --> odd>Flag] & lean[/Input/]\nodd>Flag] & b --> c")
        XCTAssertEqual(c.edges.count, 4)
        XCTAssertEqual(Set(c.nodes.map(\.label)), ["a", "Flag", "Input", "b", "c"])
    }

    /// `;` ends a statement, as in mermaid. A one-line chart parsed to
    /// nothing (its direction read as `LR;`), and `graph LR;` alone was laid
    /// out top-down.
    func testSemicolonsSeparateStatements() throws {
        guard case .flowchart(let c)? = MermaidParser.parse("graph LR; A --> B; B --> C") else {
            return XCTFail("a one-line chart should parse")
        }
        XCTAssertEqual(c.direction, .leftRight)
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["A>B", "B>C"])

        guard case .flowchart(let d)? = MermaidParser.parse("graph LR;\n  A --> B") else { return XCTFail() }
        XCTAssertEqual(d.direction, .leftRight)
    }

    /// A `;` in quotes, in brackets or ending an entity stays in the text.
    func testSemicolonsInLabelsAndEntitiesStay() throws {
        let c = try flow("A[\"a; b\"] --> B(c;d); B --> C{e;f}; C --> D[\"#quot;q#quot;\"]")
        XCTAssertEqual(c.nodes.map(\.label), ["a; b", "c;d", "e;f", "\"q\""])
        XCTAssertEqual(c.edges.count, 3)
    }

    /// Entities in labels, mermaid's and HTML's. They were drawn as written.
    func testEntitiesAreDecoded() throws {
        let c = try flow("""
            A["Say #quot;hi#quot; &amp; wave"] --> B["x #35; y #9829; &#x2665; &#169; &lt;tag&gt;"]
            subgraph S [Tom &amp; Jerry]
              C -->|a &lt; b| D
            end
            C -- #quot;quoted#quot; --> E
            """)
        XCTAssertEqual(c.nodes.first { $0.id == "A" }?.label, "Say \"hi\" & wave")
        XCTAssertEqual(c.nodes.first { $0.id == "B" }?.label, "x # y ♥ ♥ © <tag>")
        XCTAssertEqual(c.subgraphs.first?.label, "Tom & Jerry")
        XCTAssertEqual(c.edges.map(\.label), [nil, "a < b", "\"quoted\""])
    }

    /// Control characters and unknown HTML names stay as written; an
    /// unknown `#name;` reads `&name;`, as mermaid shows it.
    func testUnknownEntitiesStay() throws {
        let c = try flow("A[\"#nosuch; and #12; and &bogus;\"]")
        XCTAssertEqual(c.nodes.first?.label, "&nosuch; and #12; and &bogus;")
    }

    /// Character references read as a browser reads them (HTML's
    /// named-reference algorithm, over the full WHATWG table): the longest
    /// name that matches wins, a legacy name (`&amp`, `&copy`, `&lt`…) needs
    /// no `;`, and neither does a numeric one. Mermaid's `#name;` is
    /// `&name;`, read the same way. Each expectation is mermaid 12.2.0's.
    func testCharacterReferencesReadAsBrowsersDo() {
        let cases: [(String, String)] = [
            ("&amp more", "& more"), ("&copy 2024", "© 2024"), ("&lt", "<"), ("&LT", "<"),
            ("x &amp", "x &"), ("&ampfoo", "&foo"), ("&notit; x", "¬it; x"), ("&AMP;", "&"),
            ("&#169 x", "© x"), ("&#x41B", "Л"), ("&#128512", "😀"),
            ("&Aacute;", "Á"), ("&ccedil;a", "ça"), ("&NotEqualTilde;", "≂̸"),
            ("#copyx;", "©x;"), ("#notin;", "∉"), ("#amp;", "&"),
            ("&unknown; y", "&unknown; y"), ("a&b", "a&b"), ("&amp;amp;", "&amp;"), ("#35;35;", "#35;"),
        ]
        for (raw, shown) in cases {
            XCTAssertEqual(MermaidParser.labelText(raw), shown, raw)
        }
    }

    /// `&#169;` reads "©", as its author meant. (mermaid 12.2.0 shows "&©":
    /// its `#169;` rewrite strands the `&`. A deliberate leniency, as with
    /// tag-like text.)
    func testANumericReferenceWithItsAmpersandIsOneReference() {
        XCTAssertEqual(MermaidParser.labelText("&#169; and &#xA9"), "© and ©")
    }

    /// Numeric references read as a browser reads them: 0x80–0x9F as
    /// Windows-1252. A C1 control, a noncharacter or a non-scalar stays as
    /// written, never reaching SVG or a terminal.
    func testNumericReferencesReadAsBrowsersDo() throws {
        let c = try oneLine("flowchart LR; A[\"#133; #150; &#x80; | #129; #65535; &#xFDD0; &#xD800; #1114112;\"]")
        XCTAssertEqual(c.nodes.first?.label, "… – € | #129; #65535; &#xFDD0; &#xD800; #1114112;")
    }

    /// Every label form keeps its `;`, as mermaid's lexer does: pipes, the
    /// flag shape, each inline link text, `{{…}}`, `((…))` and
    /// `@{ label }`. Splitting them broke charts that read before.
    func testSemicolonsInEveryLabelFormStay() throws {
        let c = try oneLine("""
            flowchart LR; A -->|wait; retry| B; B>Flag; here] --> C; C -- wait; then --> D; \
            D == heavy; load ==> E; E -. maybe; later .-> F; F --> G; \
            G{{a; b}} --> H((c; d)); H@{ shape: rect, label: "e; f" } --> I
            """)
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to) \($0.label ?? "")" },
                       ["A>B wait; retry", "B>C ", "C>D wait; then", "D>E heavy; load", "E>F maybe; later",
                        "F>G ", "G>H ", "H>I "])
        XCTAssertEqual(c.nodes.first { $0.id == "B" }?.label, "Flag; here")
        XCTAssertEqual(c.nodes.first { $0.id == "H" }?.label, "e; f")
        XCTAssertEqual(c.nodes.first { $0.id == "G" }?.label, "a; b")
    }

    /// Arrowless links (`---`, `===`) are whole links, so they neither open
    /// inline text nor fail to close it.
    func testArrowlessLinksBetweenStatements() throws {
        let c = try oneLine("graph LR; A --- B; C === D; E -- solid; text --- F; G == thick; text === H; I --> J")
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to) \($0.label ?? "")" },
                       ["A>B ", "C>D ", "E>F solid; text", "G>H thick; text", "I>J "])
    }

    /// A node's text ends at its shape's own closer, the first one, as
    /// mermaid's lexer reads it: `)`, `(` or another `[` inside `[…]` is
    /// text, so its `;` is too; `[[…]]` ends at `]]`, `[(…)]` at `)]`.
    func testOnlyTheShapesOwnDelimiterEndsNodeText() throws {
        let c = try oneLine("graph LR; A[option A); retry] --> B; B{a] b; c} --> C; C[Status (pending; retry] --> D; D[[x; y]] --> E((p; q)); E --> F[Array[index; retry]; F --> G[(db; x)]")
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["A>B", "B>C", "C>D", "D>E", "E>F", "F>G"])
        XCTAssertEqual(c.nodes.first { $0.id == "A" }?.label, "option A); retry")
        XCTAssertEqual(c.nodes.first { $0.id == "C" }?.label, "Status (pending; retry")
    }

    /// Deciding whether an entity spells a break never recurses: a run of
    /// `&lt;` once made decoding exponential (40 never finished).
    func testManyEscapedAngleBracketsDecodeQuickly() throws {
        let start = Date()
        let run = String(repeating: "&lt;#lt;#60;&#60;", count: 1_000)
        let c = try flow("A[\"\(run)br&gt;\"]")
        // Every `<` decodes but the last, which spells `<br>` and stays as written.
        XCTAssertEqual(c.nodes.first?.label, String(repeating: "<", count: 3_999) + "&#60;br>")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "decoding a long run of < entities should be linear")
    }

    /// A long run of dots in dotted link text splits in linear time (each
    /// dot once rescanned the rest of the run).
    func testLongDottedLinkTextSplitsQuickly() {
        let start = Date()
        _ = MermaidParser.parse("graph LR\nA -. " + String(repeating: ".", count: 45_000))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "dotted link text should split in linear time")
    }

    /// `direction` is a statement only before one word, as mermaid lexes it:
    /// `direction --> B` is an edge from a node named `direction`.
    func testDirectionBeforeALinkIsANode() throws {
        let c = try oneLine("flowchart LR\n  direction --> B")
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["direction>B"])
    }

    /// A flag after a Unicode id is still a flag, as any id is.
    func testFlagAfterAUnicodeID() throws {
        let c = try oneLine("flowchart LR; café>Flag; retry] --> B; C --> D")
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["café>B", "C>D"])
    }

    /// An entity spelling a line break (`&lt;br&gt;`, `#92;n`) shows as
    /// written instead of breaking the label: layout reads `<br>` and `\n` as
    /// breaks. A real `<br>` still breaks.
    func testEscapedLineBreaksDontBreak() throws {
        let c = try flow("A[\"show &lt;br&gt; and #lt;BR/#gt; and #92;n literally\"] --> B[\"a<br>b\"] --> C[\"&lt;brilliant&gt;\"]")
        let label = try XCTUnwrap(c.nodes.first { $0.id == "A" }?.label)
        XCTAssertEqual(DiagramLayoutEngine.brLines(label).count, 1, label)
        XCTAssertEqual(c.nodes.first { $0.id == "C" }?.label, "<brilliant>", "only a break tag stays encoded")
        XCTAssertEqual(DiagramLayoutEngine.brLines(c.nodes.first { $0.id == "B" }?.label ?? "").count, 2)
        // Decoding never makes a break the text as written doesn't have,
        // whichever character a reference supplies (`<`, `b`, `r`, the
        // closing `>`, either half of `\n`), however far the `>`.
        let far = "&ltbr " + String(repeating: "x", count: 300) + ">"
        for spelled in ["&ltbr&gt", "&LT;BR>", "&lt;b&#114;>", "&#60br>", "&bsol;&#110;", "&bsol;n",
                        "<b&#114;>", "<B&#82;>", "<br&#62;", "\\&#110;", far] {
            let shown = MermaidParser.labelText("a \(spelled) b")
            XCTAssertEqual(DiagramLayoutEngine.brLines(shown).count, 1, "\(spelled) → \(shown)")
            XCTAssertFalse(shown.contains("\\n"), "\(spelled) → \(shown)")
        }
        // A break the author wrote still breaks, entities inside it or not.
        for written in ["a<br>b", "a <br &amp; x> b", "a <BR/> b"] {
            XCTAssertEqual(DiagramLayoutEngine.brLines(MermaidParser.labelText(written)).count, 2, written)
        }
    }

    /// Reading a label never spells a line break its text doesn't have as
    /// written: not by decoding a reference, not by dropping a formatting tag
    /// between two halves (`\<i>n`), not by both. Labels built from every
    /// fragment a break is made of, from a fixed seed. (A reference to a line
    /// separator, `&#8232;`, is a break as written; see SceneLineBreakTests.)
    func testReadingALabelNeverMakesALineBreak() {
        let breakTag = try! NSRegularExpression(pattern: "<br\\b[^>]*>", options: .caseInsensitive)
        func breaks(_ t: String) -> Int {
            breakTag.numberOfMatches(in: t, range: NSRange(t.startIndex..., in: t))
                + t.components(separatedBy: "\\n").count - 1
        }
        let parts = ["<", ">", "b", "r", "B", "R", "\\", "n", " ", "x", "/", "&lt;", "&gt;", "&lt", "&gt", "&#114;", "&#98;",
                     "&#60", "&#62;", "#92;", "&bsol;", "&#110;", "#lt;", "#gt;", "<b>", "</b>", "<i>", "<span x>",
                     "&amp;", "&am", "p;", ";", "#", "&", "<br>"]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(parts.count))
        }
        var failures: [String] = []
        for _ in 0..<40_000 {
            let raw = (0..<(2 + next() % 6)).map { _ in parts[next()] }.joined()
            let shown = MermaidParser.labelText(raw)
            if breaks(shown) > breaks(raw), failures.count < 5 { failures.append("\(raw.debugDescription) → \(shown.debugDescription)") }
        }
        XCTAssertEqual(failures, [])
        XCTAssertEqual(MermaidParser.labelText("&am<b></b>p;"), "&amp;", "a reference is read as written, not assembled")
    }

    /// A label is text to every step of reading a line, not only to
    /// splitting it into statements: a `>`, `&` or `-` in an asymmetric
    /// node's text, or in inline link text, is never syntax. Each
    /// expectation is mermaid 12.2.0's.
    func testSyntaxIsNeverReadInsideALabel() throws {
        func edges(_ c: Flowchart) -> [String] { c.edges.map { "\($0.from)→\($0.to) \($0.label ?? "")" } }
        func label(_ c: Flowchart, _ id: String) -> String? { c.nodes.first { $0.id == id }?.label }
        let fan = try oneLine("flowchart LR; B --- S>\"a & b\"]")
        XCTAssertEqual(edges(fan), ["B→S "])
        XCTAssertEqual(label(fan, "S"), "a & b")
        XCTAssertEqual(fan.nodes.first { $0.id == "S" }?.shape, .asymmetric)
        let flag = try oneLine("flowchart LR; x>a & b] -..-> Y[(\"u\")]")
        XCTAssertEqual(edges(flag), ["x→Y "])
        XCTAssertEqual(label(flag, "x"), "a & b")
        XCTAssertEqual(label(flag, "Y"), "u")
        let both = try oneLine("flowchart LR; P>a & b] --x Q>\"a & b\"]")
        XCTAssertEqual(edges(both), ["P→Q "])
        XCTAssertEqual([label(both, "P"), label(both, "Q")], ["a & b", "a & b"])
        XCTAssertEqual(edges(try oneLine("flowchart LR; A -- a-b --> B")), ["A→B a-b"])
        XCTAssertEqual(edges(try oneLine("flowchart LR; A -- a & b --> B")), ["A→B a & b"])
        XCTAssertEqual(edges(try oneLine("flowchart LR; A -- x --> B -- y --> C")), ["A→B x", "B→C y"])
    }

    /// `&` joins a fan only between whitespace (mermaid's `\s&\s`): written
    /// between two id characters it's part of the id (`B&C`).
    func testAnAmpersandInsideAnIdIsTheId() throws {
        let c = try oneLine("graph LR; A-->B&C; C-->D")
        XCTAssertEqual(c.nodes.map(\.id), ["A", "B&C", "C", "D"])
        XCTAssertEqual(try oneLine("flowchart LR; A & B --> C").edges.map(\.from), ["A", "B"])
    }

    /// A start head that doesn't match the end isn't a head: mermaid reads it
    /// as part of the link, so it counts toward the length (`<---` is
    /// `----`, two ranks).
    func testAnUnmatchedStartHeadCountsTowardTheLength() throws {
        let c = try oneLine("flowchart LR; A <--- B; C <--o D; E o--> F; G x---> H")
        XCTAssertEqual(c.edges.map(\.length), [2, 2, 2, 3])
        XCTAssertEqual(c.edges.map(\.hasArrow), [false, true, true, true])
        XCTAssertEqual(c.edges.map(\.backArrow), [false, false, false, false])
    }

    /// `style X …` names a node, and mermaid draws it even if nothing else
    /// does; the styling itself is still ignored. (`class` and `click` lines
    /// don't make one.)
    func testAStyleLineNamesItsNode() throws {
        let c = try oneLine("flowchart LR; A --> B; style Z fill:#f96,stroke:#333; class Q hot; click R cb")
        XCTAssertEqual(c.nodes.map(\.id), ["A", "B", "Z"])
        XCTAssertEqual(c.nodes.last?.label, "Z")
    }

    /// Splitting is linear: a long run of blanks after a `;` once rescanned
    /// itself at every character (quadratic within `maxTextSize`).
    func testLongBlankRunsSplitInLinearTime() throws {
        let start = Date()
        // Blanks, then a statement of `#word;` entities: each `;` once
        // rescanned the blanks too.
        let c = try oneLine("graph LR; A --> B;" + String(repeating: " ", count: 30_000) + String(repeating: "#a;", count: 5_000))
        XCTAssertEqual(c.edges.count, 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "a long blank run should split in well under 2s")
    }

    /// In `style`, `classDef` and `linkStyle` a `;` ends the statement, so a
    /// color (`#f96;`) isn't read as an entity that swallows the next one.
    func testStylingSemicolonsEndStatements() throws {
        for source in ["graph LR; classDef hot fill:#f96; A:::hot --> B",
                       "graph LR; style A fill:#f96; A --> B",
                       "graph LR; linkStyle 0 stroke:#f00; A --> B"] {
            XCTAssertEqual(try oneLine(source).edges.map { "\($0.from)>\($0.to)" }, ["A>B"], source)
        }
    }

    /// A `%%` comment after a `;` runs to the end of the line, as one on a
    /// line of its own does; what follows it isn't drawn.
    func testCommentAfterASemicolonEndsTheLine() throws {
        let c = try oneLine("graph LR; A --> B; %% disabled; C --> D")
        XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["A>B"])
    }

    /// Keywords are whole words, as in mermaid: `styleguide`, `subgraphs`,
    /// `ending`… are node ids. `styleguide --> B` was skipped as styling.
    func testKeywordsAreWholeWords() throws {
        for id in ["styleguide", "subgraphs", "classDefault", "classy", "linkStyles", "clicks", "directions", "ending"] {
            let c = try oneLine("flowchart LR\n  \(id) --> B")
            XCTAssertEqual(c.edges.map { "\($0.from)>\($0.to)" }, ["\(id)>B"], id)
        }
    }

    private func oneLine(_ source: String) throws -> Flowchart {
        guard case .flowchart(let c)? = MermaidParser.parse(source) else {
            XCTFail("should parse: \(source)")
            throw CancellationError()
        }
        return c
    }

    /// Inline formatting tags give way to their text (the renderers can't
    /// style it). `<br>` breaks and angle brackets that aren't formatting
    /// stay.
    func testFormattingTagsAreDropped() throws {
        let c = try flow("""
            A["<b>bold</b> <i>it</i> <code>x</code> <span style='c'>s</span>"] --> B["p<0.05, List<String>, a<br/>b"]
            """)
        XCTAssertEqual(c.nodes.map(\.label), ["bold it x s", "p<0.05, List<String>, a<br/>b"])
    }

    // MARK: flowchart subgraphs

    /// A subgraph id used again after its block closed is the same subgraph,
    /// as in mermaid: the first title and direction stand and the second block
    /// adds its members. It used to mint an anonymous second box that took
    /// them.
    func testAReusedSubgraphIdReopensIt() throws {
        let c = try flow("""
            subgraph two [First]
              direction LR
              A --> B
            end
            subgraph two [Second]
              direction RL
              C --> D
            end
            """)
        XCTAssertEqual(c.subgraphs.map(\.id), ["two"])
        let two = try XCTUnwrap(c.subgraphs.first)
        XCTAssertEqual(two.label, "First")
        XCTAssertEqual(two.direction, .leftRight)
        XCTAssertEqual(two.nodeIDs, ["A", "B", "C", "D"])
    }

    /// A synthesized subgraph id never collides with one the source named in
    /// the same spelling, so an untitled block is its own box, not a reopening.
    func testSynthesizedSubgraphIdsAreAlwaysNew() throws {
        for source in ["subgraph \u{a7}sub0 [Named]\n  A\nend\nsubgraph\n  B\nend",
                       "subgraph\n  B\nend\nsubgraph \u{a7}sub0 [Named]\n  A\nend"] {
            let c = try flow(source)
            XCTAssertEqual(c.subgraphs.count, 2, source)
            XCTAssertEqual(c.subgraphs.first { $0.label == "Named" }?.nodeIDs, ["A"], source)
            XCTAssertEqual(c.subgraphs.first { $0.label == "" }?.nodeIDs, ["B"], source)
        }
    }

    /// A quoted subgraph title without whitespace is its id, as in mermaid,
    /// so an edge can target the box; one with whitespace gets a synthesized
    /// id.
    func testAQuotedOneWordSubgraphTitleIsItsId() throws {
        let c = try flow("""
            subgraph "Anon"
              B
            end
            subgraph "two words"
              D
            end
            Anon --> C
            """)
        XCTAssertEqual(c.subgraphs.first?.id, "Anon")
        XCTAssertEqual(c.subgraphs.first?.label, "Anon")
        XCTAssertTrue(c.subgraphs.last?.id.hasPrefix("\u{a7}sub") == true)
        XCTAssertEqual(c.subgraphs.last?.label, "two words")
        XCTAssertFalse(c.nodes.contains { $0.id == "Anon" }, "the edge targets the box, not a phantom node")
    }

    /// A title with whitespace that is also the header's id gives no id, as
    /// in mermaid, quoted or bare: two `subgraph My Group` blocks are two
    /// boxes. `subgraph My Group[T]` names its id apart from the title, so it
    /// keeps it, and a second one reopens the first.
    func testASpacedTitleIsNeverAnId() throws {
        let c = try flow("""
            subgraph My Group
              A
            end
            subgraph My Group
              B
            end
            subgraph "x y"
              C
            end
            subgraph "x y"
              D
            end
            subgraph Named Box[T]
              E
            end
            subgraph Named Box[T]
              F
            end
            """)
        XCTAssertEqual(c.subgraphs.map(\.label), ["My Group", "My Group", "x y", "x y", "T"])
        XCTAssertEqual(c.subgraphs.filter { $0.id.hasPrefix("\u{a7}sub") }.count, 4)
        XCTAssertEqual(c.subgraphs.last?.id, "Named Box")
        XCTAssertEqual(c.subgraphs.last?.nodeIDs, ["E", "F"])
    }

    /// A header that is one quoted string is a title, brackets and all, as
    /// in mermaid; brackets name an id only outside quotes.
    func testAQuotedTitleKeepsItsBrackets() throws {
        let c = try flow("""
            subgraph "Cache [Redis] tier"
              A
            end
            subgraph "Cache [Redis] tier"
              B
            end
            subgraph "[x]"
              C
            end
            subgraph id["a [b] c"]
              D
            end
            """)
        XCTAssertEqual(c.subgraphs.map(\.label), ["Cache [Redis] tier", "Cache [Redis] tier", "[x]", "a [b] c"])
        XCTAssertEqual(c.subgraphs.filter { $0.id.hasPrefix("\u{a7}sub") }.count, 2)
        XCTAssertEqual(c.subgraphs[2].id, "[x]")
        XCTAssertEqual(c.subgraphs[3].id, "id")
    }

    /// Reopening subgraphs in reverse nesting order keeps each one's first
    /// parent: no cycle (`B` inside `A` inside `B`), which layout would
    /// recurse on until it crashed.
    func testReopeningSubgraphsNeverMakesACycle() throws {
        let c = try flow("""
            subgraph C
              subgraph A
                subgraph B
                  x
                end
              end
            end
            subgraph B
              subgraph A
                y
              end
            end
            """)
        let children = Dictionary(uniqueKeysWithValues: c.subgraphs.map { ($0.id, $0.childIDs) })
        XCTAssertEqual(children["C"], ["A"])
        XCTAssertEqual(children["A"], ["B"])
        XCTAssertEqual(children["B"], [])
        XCTAssertNotNil(DiagramLayoutEngine.layout(c, measure: { t, s in CGSize(width: CGFloat(t.count) * s * 0.6, height: s + 4) }))
    }

    /// Deterministic fake measurer for the layout-geometry assertions below.
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    func testSubgraphIsGroupedNotFlattened() throws {
        let c = try flow("""
            A --> B
            subgraph G [Group]
              B --> C
              C --> D
            end
            D --> E
            """)
        XCTAssertEqual(c.subgraphs.count, 1)
        let g = try XCTUnwrap(c.subgraphs.first)
        XCTAssertEqual(g.id, "G")
        XCTAssertEqual(g.label, "Group")
        // B, C, D first appear inside the block → members; A and E do not.
        XCTAssertEqual(g.nodeIDs, ["B", "C", "D"])
        // A group box is laid out that contains exactly its members.
        let layout = DiagramLayoutEngine.layout(c, measure: measure)
        XCTAssertEqual(layout.containers.count, 1)
        let box = try XCTUnwrap(layout.containers.first).frame.insetBy(dx: -1, dy: -1)
        let inside = Set(layout.nodes.filter { box.contains($0.frame) }.map(\.id))
        XCTAssertEqual(inside, ["B", "C", "D"])
        XCTAssertFalse(inside.contains("A"))
        XCTAssertFalse(inside.contains("E"))
    }

    func testEdgeToSubgraphIdMintsNoPhantomNode() throws {
        let c = try flow("""
            subgraph SG [Sub]
              X --> Y
            end
            Z --> SG
            """)
        // "SG" is a subgraph id, never a node — the edge resolves to its box.
        XCTAssertFalse(c.nodes.contains { $0.id == "SG" }, "no phantom SG node")
        XCTAssertEqual(c.nodes.map(\.id).sorted(), ["X", "Y", "Z"])
        XCTAssertTrue(c.edges.contains { $0.from == "Z" && $0.to == "SG" })
        // The layout is clean and the edge terminates on the group box.
        let scene = DiagramScene.lower(.flowchart(c), measure: measure)
        XCTAssertTrue(DiagramLayoutLinter.lint(scene).allSatisfy { $0.severity == .warning },
                      "edge-to-subgraph must not produce layout errors")
    }

    func testNestedSubgraphs() throws {
        let c = try flow("""
            subgraph Outer [Outer]
              A --> B
              subgraph Inner [Inner]
                B --> C
              end
            end
            """)
        XCTAssertEqual(c.subgraphs.count, 2)
        let outer = try XCTUnwrap(c.subgraphs.first { $0.id == "Outer" })
        let inner = try XCTUnwrap(c.subgraphs.first { $0.id == "Inner" })
        XCTAssertEqual(outer.childIDs, ["Inner"], "Inner nests under Outer")
        XCTAssertEqual(inner.nodeIDs, ["C"], "C belongs to Inner, not Outer")
        XCTAssertFalse(outer.nodeIDs.contains("C"))
        // Two boxes, and Inner sits strictly inside Outer.
        let layout = DiagramLayoutEngine.layout(c, measure: measure)
        XCTAssertEqual(layout.containers.count, 2)
        let outerBox = try XCTUnwrap(layout.containers.first { $0.id == "Outer" })
        let innerBox = try XCTUnwrap(layout.containers.first { $0.id == "Inner" })
        XCTAssertEqual(outerBox.depth, 0)
        XCTAssertEqual(innerBox.depth, 1)
        XCTAssertTrue(outerBox.frame.insetBy(dx: -1, dy: -1).contains(innerBox.frame),
                      "Inner box must nest within Outer box")
    }

    func testSubgraphInnerDirection() throws {
        let c = try flow("""
            subgraph G [Group]
              direction LR
              A --> B
            end
            """)
        XCTAssertEqual(c.subgraphs.first?.direction, .leftRight)
    }

    func testBareAndQuotedSubgraphTitles() throws {
        let bare = try flow("subgraph one\n  A --> B\nend")
        XCTAssertEqual(bare.subgraphs.first?.id, "one")
        XCTAssertEqual(bare.subgraphs.first?.label, "one")
    }

    // MARK: sequence

    private func seq(_ body: String) throws -> SequenceDiagram {
        guard case .sequence(let s)? = MermaidParser.parse("sequenceDiagram\n" + body) else {
            throw XCTSkip("parse failed")
        }
        return s
    }

    func testActivationShorthandMintsNoPhantomLifelines() throws {
        let s = try seq("Alice->>+John: Hello\nJohn->>-Alice: Hi")
        XCTAssertEqual(s.participants.map(\.id).sorted(), ["Alice", "John"],
                       "the docs' first example: no '+John'/'-John' lifelines")
        XCTAssertEqual(s.messages.count, 2)
    }

    func testCrossAndAsyncArrowsParse() throws {
        let s = try seq("A-x B: dies\nC-) D: async\nE--) F: dashed async")
        XCTAssertEqual(s.messages.count, 3, "message text must survive head-style degradation")
        XCTAssertEqual(s.messages[0].text, "dies")
    }

    func testAutonumberStampsMessages() throws {
        let s = try seq("autonumber\nA->>B: first\nB->>A: second")
        XCTAssertEqual(s.messages.map(\.number), [1, 2],
                       "numbers ride as badge metadata, not text mutations")
        XCTAssertEqual(s.messages[0].text, "first")
    }

    func testActorAliasKeepsItsLabel() throws {
        let s = try seq("participant P as an actor guy\nP->>P: hi")
        XCTAssertEqual(s.participants.first?.label, "an actor guy",
                       "global 'actor ' strip once corrupted this label")
    }

    // MARK: gantt

    func testColonDirectivesAreNotPhantomTasks() throws {
        guard case .gantt(let g)? = MermaidParser.parse("""
        gantt
            dateFormat YYYY-MM-DD
            axisFormat %H:%M
            todayMarker stroke-width:5px,opacity:0.5
            tickInterval 1week
            click t1 href "https://example.com"
            section S
            Real task : t1, 2026-01-01, 3d
        """) else { return XCTFail() }
        XCTAssertEqual(g.tasks.count, 1, "directives with colons must not become bars")
        XCTAssertEqual(g.tasks.first?.label, "Real task")
    }

    func testLongDurationUnits() throws {
        guard case .gantt(let g)? = MermaidParser.parse("""
        gantt
            section S
            Year : t1, 2026-01-01, 1y
        """) else { return XCTFail() }
        XCTAssertEqual(g.tasks.first?.length ?? 0, 365, accuracy: 0.1)
    }

    // MARK: radar

    func testRadarPositionalValues() throws {
        guard case .radar(let r)? = MermaidParser.parse("""
        radar-beta
            axis a["A"], b["B"], c["C"]
            curve x["X"]{10, 20, 30}
        """) else { return XCTFail() }
        XCTAssertEqual(r.curves.first?.values, [10, 20, 30],
                       "the docs' primary form once rendered flat at min")
    }

    func testRadarMultipleAxisLinesAppend() throws {
        guard case .radar(let r)? = MermaidParser.parse("""
        radar-beta
            axis a["A"], b["B"]
            axis c["C"]
            curve x{1, 2, 3}
        """) else { return XCTFail() }
        XCTAssertEqual(r.axes.count, 3, "second axis line once replaced the first")
    }

    // MARK: packet

    func testPacketRelativeWidths() throws {
        guard case .packet(let p)? = MermaidParser.parse("""
        packet-beta
            0-15: "Source"
            +16: "Destination"
            +8: "Flags"
        """) else { return XCTFail() }
        XCTAssertEqual(p.fields[1].startBit, 16)
        XCTAssertEqual(p.fields[1].endBit, 31, "+16 is a WIDTH after the previous field")
        XCTAssertEqual(p.fields[2].startBit, 32)
        XCTAssertEqual(p.fields[2].endBit, 39)
    }

    // MARK: treemap

    func testTreemapStyleClassKeepsValue() throws {
        guard case .treemap(let t)? = MermaidParser.parse("""
        treemap-beta
            "Products"
                "Phones": 50:::urgent
                "Laptops": 30
            classDef urgent fill:#f00
        """) else { return XCTFail() }
        let products = t.root.label == "Products" ? t.root : t.root.children[0]
        let phones = products.children.first(where: { $0.label == "Phones" })
        XCTAssertEqual(phones?.value ?? 0, 50, accuracy: 0.1, ":::class once destroyed the value")
        XCTAssertNil(findNode(products, labelContains: "classDef"), "CSS is not a tree node")
    }

    private func findNode(_ node: TreemapNode, labelContains text: String) -> TreemapNode? {
        if node.label.contains(text) { return node }
        for child in node.children {
            if let found = findNode(child, labelContains: text) { return found }
        }
        return nil
    }

    // MARK: zenuml

    func testZenUMLFabricatesNothing() throws {
        guard case .zenuml(let z)? = MermaidParser.parse("""
        zenuml
            // this is a comment
            result = Service.fetch()
        """) else { return XCTFail() }
        XCTAssertFalse(z.participants.contains(where: { $0.name.contains("//") }),
                       "comments are not participants")
        XCTAssertFalse(z.participants.contains(where: { $0.name == "result" }),
                       "assignment targets are not participants")
    }

    // MARK: c4

    func testC4RelIndexDoesNotShiftArguments() throws {
        guard case .c4(let c)? = MermaidParser.parse("""
        C4Context
            Person(a, "A")
            System(b, "B")
            RelIndex(1, a, b, "uses")
        """) else { return XCTFail() }
        XCTAssertEqual(c.relations.first?.from, "a", "the index arg once became 'from'")
        XCTAssertEqual(c.relations.first?.label, "uses")
    }

    /// Every word of a C4 title and description reaches the box, each line
    /// within the box's text width (a lone over-wide word aside): the box grows
    /// taller instead of the wrap cutting text after its last line (#70).
    func testC4WrapKeepsEveryWord() throws {
        let title = "A rather long container title that needs several lines to show"
        let descr = "Drop-in diagram view following the color scheme of the host app, "
            + "re-rendering whenever the theme, spacing or source text changes underneath it"
        guard case .c4(let c)? = MermaidParser.parse("""
        C4Container
            Container(v, "\(title)", "SwiftUI", "\(descr)")
            Container(w, "Short", "Swift", "Images keyed by source, theme, spacing")
        """) else { return XCTFail() }
        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(c, measure: measure)
        XCTAssertEqual(layout.boxes.count, 2)
        let v = layout.boxes[0], w = layout.boxes[1]

        XCTAssertEqual(v.titleLines.joined(separator: " "), title, "title words were dropped")
        XCTAssertEqual(v.detailLines.first, "[SwiftUI]")
        XCTAssertEqual(v.detailLines.dropFirst().joined(separator: " "), descr,
                       "description words past the last line were dropped")
        XCTAssertEqual(w.detailLines.dropFirst().joined(separator: " "),
                       "Images keyed by source, theme, spacing")

        let textWidth = v.frame.width - 20          // the layout's 10pt side pads
        for line in v.titleLines where line.contains(" ") {
            XCTAssertLessThanOrEqual(measure(line, 12).width, textWidth, "over-wide title line: \(line)")
        }
        for line in v.detailLines.dropFirst() where line.contains(" ") {
            XCTAssertLessThanOrEqual(measure(line, 10).width, textWidth, "over-wide detail line: \(line)")
        }
        // The box is tall enough for every line it carries.
        let pitches = DiagramLayoutEngine.c4LinePitches(measure)
        let needed = 10 + pitches.stereotype + 3 + CGFloat(v.titleLines.count) * pitches.title
            + 4 + CGFloat(v.detailLines.count) * pitches.detail + 10
        XCTAssertGreaterThanOrEqual(v.frame.height, needed)
    }

    /// A label too long for any box is cut at a generous line cap with "…",
    /// never silently: the kept lines are the text's first words, in order,
    /// and the box stays within the canvas instead of being clipped by it.
    func testC4OverlongDescriptionIsCutVisibly() throws {
        let words = (1...600).map { "word\($0)" }
        guard case .c4(let c)? = MermaidParser.parse("""
        C4Container
            Container(v, "\(words.prefix(60).joined(separator: " "))", "", "\(words.joined(separator: " "))")
        """) else { return XCTFail() }
        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(c, measure: measure)
        let box = try XCTUnwrap(layout.boxes.first)
        XCTAssertEqual(box.detailLines.count, 12)
        XCTAssertEqual(box.titleLines.count, 4)
        for lines in [box.titleLines, box.detailLines] {
            XCTAssertTrue(lines.last?.hasSuffix("…") == true, "a cut is marked")
            let kept = lines.joined(separator: " ").dropLast().split(separator: " ").map(String.init)
            XCTAssertEqual(kept, Array(words.prefix(kept.count)), "the kept words are the first ones, in order")
        }
        XCTAssertLessThanOrEqual(box.frame.maxY, layout.size.height, "the box fits the canvas")
    }

    /// Many boxes at the line caps would run the chart past the 3999pt canvas,
    /// which clips whole rows; the layout tightens its caps instead, so every
    /// box stays on the canvas and every cut still ends in "…".
    func testManyLongC4BoxesStayOnTheCanvas() throws {
        // Past both caps (4 title lines of ~21 chars, 12 description lines of
        // ~26), within MermaidParser.maxTextSize.
        let title = (1...25).map { "t\($0)" }.joined(separator: " ")
        let descr = (1...80).map { "w\($0)" }.joined(separator: " ")
        // 73 boxes past both caps, then 140 with a technology line and a few
        // description lines (each group alone outgrows the canvas).
        let tech = (1...30).map { "w\($0)" }.joined(separator: " ")
        let sources = [(0..<73).map { "    Container(c\($0), \"\(title)\", \"\", \"\(descr)\")" },
                       (0..<140).map { "    Container(d\($0), \"T\", \"Swift\", \"\(tech)\")" }]
        for elements in sources.map({ $0.joined(separator: "\n") }) {
            guard case .c4(let c)? = MermaidParser.parse("C4Container\n" + elements) else { return XCTFail("parse") }
            let measure: DiagramTextMeasurer = { t, size in
                CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
            }
            let layout = DiagramLayoutEngine.layout(c, measure: measure)
            XCTAssertGreaterThanOrEqual(layout.boxes.count, 73)
            for box in layout.boxes {
                XCTAssertLessThanOrEqual(box.frame.maxY, layout.size.height, "a box runs off the canvas")
                XCTAssertTrue(box.detailLines.last?.hasSuffix("…") == true)
            }
        }
    }

    /// Wrapping stops at the line cap: a description near the input limit
    /// costs a few lines of measuring, not one per word.
    func testC4WrapStopsMeasuringAtTheCap() throws {
        let descr = (1...8_000).map { "w\($0)" }.joined(separator: " ")
        guard case .c4(let c)? = MermaidParser.parse("C4Container\n    Container(v, \"T\", \"\", \"\(descr)\")") else {
            return XCTFail("parse")
        }
        var measured = 0
        let measure: DiagramTextMeasurer = { t, size in
            measured += 1
            return CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let box = try XCTUnwrap(DiagramLayoutEngine.layout(c, measure: measure).boxes.first)
        XCTAssertEqual(box.detailLines.count, 12)
        XCTAssertLessThan(measured, 1_000, "measured \(measured) times for 12 lines")
    }

    // MARK: gitGraph

    func testCherryPickAppearsOnTheTimeline() throws {
        guard case .gitGraph(let g)? = MermaidParser.parse("""
        gitGraph
            commit id: "one"
            branch dev
            commit id: "two"
            checkout main
            cherry-pick id: "two"
        """) else { return XCTFail() }
        XCTAssertTrue(g.commits.contains(where: { $0.id.contains("cherry-pick") && $0.branch == "main" }),
                      "cherry-pick once vanished from the timeline")
    }
}

extension ParserHonestyTests {
    func testNotesSurviveAndInterleave() throws {
        guard case .sequence(let s)? = MermaidParser.parse("""
        sequenceDiagram
            A->>B: first
            Note over A,B: between the two
            B->>A: second
            Note right of A: at the end
        """) else { return XCTFail() }
        XCTAssertEqual(s.notes.count, 2, "note text is author content; it must survive")
        XCTAssertEqual(s.notes[0].afterMessage, 1)
        XCTAssertEqual(s.notes[1].afterMessage, 2)
        XCTAssertEqual(s.notes[0].text, "between the two")

        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(s, measure: measure)
        XCTAssertEqual(layout.notes.count, 2)
        // The over-note's row sits strictly between the two message rows.
        XCTAssertGreaterThan(layout.notes[0].frame.minY, layout.arrows[0].y)
        XCTAssertLessThan(layout.notes[0].frame.maxY, layout.arrows[1].y + 1)
    }

    func testActorDeclarationsFlagTheParticipant() throws {
        guard case .sequence(let s)? = MermaidParser.parse("""
        sequenceDiagram
            actor Alice
            participant Bob
            Alice->>Bob: hi
        """) else { return XCTFail() }
        XCTAssertEqual(s.participants.first(where: { $0.id == "Alice" })?.isActor, true)
        XCTAssertEqual(s.participants.first(where: { $0.id == "Bob" })?.isActor, false)
    }
}

extension ParserHonestyTests {
    func testArrowHeadIdentity() throws {
        let s = try seqPub("""
        A->B: bare
        A->>B: filled
        A-x B: cross
        A-) B: async
        A<<->>B: both
        """)
        let heads = s.messages.map(\.head)
        XCTAssertEqual(heads, [.none, .filled, .cross, .open, .both],
                       "all eight tokens once collapsed into one dashed bool")
    }

    func testAutonumberVariants() throws {
        let s = try seqPub("""
        autonumber 10 5
        A->>B: first
        B->>A: second
        autonumber off
        A->>B: unnumbered
        """)
        XCTAssertEqual(s.messages.map(\.number), [10, 15, nil])
        XCTAssertEqual(s.messages[0].text, "first", "numbers are badges, not text prefixes")
    }

    private func seqPub(_ body: String) throws -> SequenceDiagram {
        guard case .sequence(let s)? = MermaidParser.parse("sequenceDiagram\n" + body) else {
            throw XCTSkip("parse failed")
        }
        return s
    }
}

extension ParserHonestyTests {
    func testFragmentsParseAsFrames() throws {
        let s = try seqPub("""
        A->>B: start
        alt cache hit
            B-->>A: cached
        else miss
            loop each row
                B->>B: compute
            end
            B-->>A: fresh
        end
        """)
        XCTAssertEqual(s.fragments.count, 2)
        XCTAssertEqual(s.fragments[0].kind, .alt)
        XCTAssertEqual(s.fragments[0].label, "cache hit")
        XCTAssertEqual(s.fragments[1].kind, .loop)
        // Event stream: message, open(alt), message, divider, open(loop),
        // message, close(loop), message, close(alt).
        XCTAssertEqual(s.events.count, 9)

        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(s, measure: measure)
        XCTAssertEqual(layout.frames.count, 2)
        // Nesting: the loop frame sits strictly inside the alt frame.
        let alt = layout.frames.first(where: { $0.kind == "alt" })!
        let loop = layout.frames.first(where: { $0.kind == "loop" })!
        XCTAssertTrue(alt.rect.contains(loop.rect), "inner frame must nest inside outer")
        XCTAssertEqual(alt.dividers.count, 1)
        // Divider sits between the frame's top and bottom.
        XCTAssertGreaterThan(alt.dividers[0].y, alt.rect.minY)
        XCTAssertLessThan(alt.dividers[0].y, alt.rect.maxY)
    }

    func testUnclosedFragmentIsTolerated() throws {
        let s = try seqPub("A->>B: x\nloop forever\nB->>A: y")
        XCTAssertEqual(s.fragments.count, 1)
        XCTAssertEqual(s.events.filter { if case .close = $0 { return true }; return false }.count, 1,
                       "missing 'end' closes at end-of-diagram")
    }
}

extension ParserHonestyTests {
    func testActivationBarsFromShorthandAndStatements() throws {
        let s = try seqPub("""
        A->>+B: work
        B->>B: think
        B-->>-A: done
        activate A
        A->>A: reflect
        deactivate A
        """)
        XCTAssertEqual(s.messages[0].activatesTarget, true)
        XCTAssertEqual(s.messages[2].deactivatesSender, true)

        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(s, measure: measure)
        XCTAssertEqual(layout.bars.count, 2, "one bar per activation interval")
        let bBar = layout.bars.min(by: { $0.top < $1.top })!
        XCTAssertLessThan(bBar.top, bBar.bottom, "B's bar spans work...done")
    }
}

extension ParserHonestyTests {
    func testBoxGroupsParticipants() throws {
        let s = try seqPub("""
        box Aqua MermaidKit internals
            participant R as Renderer
            participant C as Cache
        end
        participant H as Host
        H->>R: draw
        R->>C: lookup
        """)
        XCTAssertEqual(s.boxes.count, 1)
        XCTAssertEqual(s.boxes[0].label, "MermaidKit internals", "color token is not part of the label")
        XCTAssertEqual(s.boxes[0].memberIDs, ["R", "C"])
        XCTAssertEqual(s.messages.count, 2, "end closed the box, not a phantom fragment")
    }
}

extension ParserHonestyTests {
    func testCreateAndDestroyLifecycle() throws {
        let s = try seqPub("""
        A->>B: begin
        create participant W as Worker
        B->>W: spawn
        W-->>B: done
        destroy W
        B->>A: finished
        """)
        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(s, measure: measure)
        let worker = layout.heads.first(where: { $0.label == "Worker" })!
        let a = layout.heads.first(where: { $0.label == "A" })!
        XCTAssertGreaterThan(worker.frame.minY, a.frame.maxY,
                             "created head appears mid-diagram, not at the top")
        XCTAssertNotNil(worker.lifelineEndY, "destroyed lifeline ends early")
        XCTAssertTrue(worker.showsDestroyCross)
        XCTAssertLessThan(worker.lifelineEndY!, layout.lifelineBottom)
    }
}

extension ParserHonestyTests {
    func testBrLineBreaksGrowRows() throws {
        let s = try seqPub("""
        A->>B: one<br/>two<br/>three
        Note over A,B: first line<br/>second line
        B->>A: done
        """)
        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(s, measure: measure)
        // Three-line message: its row grew, pushing the note and next arrow down.
        XCTAssertGreaterThan(layout.arrows[1].y - layout.arrows[0].y, 34 * 2 - 1,
                             "multiline rows must consume extra height")
        XCTAssertGreaterThan(layout.notes[0].frame.height, 24, "two-line note grows its box")
    }
}

extension ParserHonestyTests {
    func testTypedParticipants() throws {
        let s = try seqPub("""
        participant DB@{ "type": "database" }
        participant Q@{ "type" : "queue" }
        DB->>Q: enqueue
        """)
        XCTAssertEqual(s.participants.first(where: { $0.id == "DB" })?.kind, .database)
        XCTAssertEqual(s.participants.first(where: { $0.id == "Q" })?.kind, .queue)
    }
}

// MARK: class generics

/// mermaid reads `~T~` as a generic: `Box~T~` is the class `Box` (relations
/// to `Box` and `Box~T~` meet the same box) drawn as `Box<T>`, and member
/// text pairs its tildes outside-in, so `List~List~int~~` reads
/// `List<List<int>>`. Tildes that don't pair stay as written.
extension ParserHonestyTests {
    private func classes(_ body: String) throws -> ClassDiagram {
        guard case .classDiagram(let d)? = MermaidParser.parse("classDiagram\n" + body) else {
            throw XCTSkip("parse failed: \(body)")
        }
        return d
    }

    func testGenericClassNamesReadAsAngleBrackets() throws {
        let d = try classes("""
        class Box~T~ {
            +List~int~ items
            +get(i: int) T
            +map~U~(f) Box~U~
        }
        class Map~K, V~
        """)
        XCTAssertEqual(d.classes.map(\.name), ["Box", "Map"], "the class id is the name without its generic")
        XCTAssertEqual(d.classes.map(\.generic), ["T", "K, V"])
        XCTAssertEqual(d.classes.map(\.label), ["Box<T>", "Map<K, V>"])
        XCTAssertEqual(d.classes[0].attributes, ["+List<int> items"])
        XCTAssertEqual(d.classes[0].methods, ["+get(i: int) T", "+map<U>(f) Box<U>"])
    }

    func testGenericAndBareNamesAreOneClass() throws {
        let d = try classes("""
        class Box~T~
        Box~T~ --> Item
        Box --> Item
        Box~T~ : +peek() T
        Box~U~ <|-- Crate
        """)
        XCTAssertEqual(d.classes.map(\.name), ["Box", "Item", "Crate"], "no second `Box~T~` box")
        XCTAssertEqual(d.relations.map(\.from), ["Box", "Box", "Crate"])
        XCTAssertEqual(d.relations.map(\.to), ["Item", "Item", "Box"])
        XCTAssertEqual(d.classes[0].methods, ["+peek() T"], "colon shorthand on a generic name once vanished")
        XCTAssertEqual(d.classes[0].label, "Box<T>", "the first generic written stays")
    }

    func testGenericWrittenAfterABareMentionIsKept() throws {
        let d = try classes("Box --> Item\nclass Box~T~")
        XCTAssertEqual(d.classes.map(\.label), ["Box<T>", "Item"])
        let empty = try classes("class Box~~")
        XCTAssertEqual(empty.classes.map(\.label), ["Box"])
    }

    func testMemberTildesPairAsMermaidPairsThem() throws {
        let d = try classes("""
        class Odd {
            +List~List~int~~ xs
            +Map~K, V~ m
            ~List~int~ pkg
            +a~b
            +c~d~e
            +f~g~h~i~j
            +List~List~int~ ys
            +Map~K,List~V~~ n
            +a~b,c~d,e~f
            +get() List~Map~K~~
            +put(Map~K, V~ m, List~T~ l) Pair~A, B~
        }
        """)
        XCTAssertEqual(d.classes[0].attributes, [
            "+List<List<int>> xs",
            "+Map<K, V> m",
            "~List<int> pkg",       // `~` visibility is not a generic
            "+a~b",                 // a lone tilde stays
            "+c<d>e",
            "+f<g<h>i>j",           // outermost pair first, as mermaid does
            "+List<List~int> ys",   // odd count: the middle one stays
            "+Map~K,List<V~> n",    // mermaid's comma split, kept faithfully
            "+a<b,c>d,e~f",         // never dropped (mermaid loses `a~b,`)
        ])
        XCTAssertEqual(d.classes[0].methods, [
            "+get() List<Map<K>>",
            "+put(Map<K, V> m, List<T> l) Pair<A, B>",
        ])
    }

    func testGenericClassDrawsAndNarratesAsAngleBrackets() throws {
        let source = "classDiagram\nclass Box~T~ {\n +List~int~ items\n}\nBox --> Item"
        guard case .classDiagram(let d)? = MermaidParser.parse(source) else { return XCTFail() }
        let measure: DiagramTextMeasurer = { t, size in
            CGSize(width: CGFloat(max(t.count, 1)) * size * 0.6, height: size + 4)
        }
        let layout = DiagramLayoutEngine.layout(d, measure: measure)
        XCTAssertEqual(layout.boxes.map(\.label), ["Box<T>", "Item"])
        XCTAssertEqual(layout.edges.count, 1)
        let theme = RenderTheme(
            ink: DiagramColor(hex: 0x000000), accent: DiagramColor(hex: 0x5B8FF9),
            canvas: DiagramColor(hex: 0xFFFFFF), hairline: DiagramColor(hex: 0x000000),
            secondaryText: DiagramColor(hex: 0x000000), tertiaryText: DiagramColor(hex: 0x000000),
            palette: [DiagramColor(hex: 0x5B8FF9)])
        let scene = try XCTUnwrap(RenderScene.from(.classDiagram(d), theme: theme, measure: measure))
        let texts = scene.elements.compactMap { element -> String? in
            if case .text(let t) = element { return t.string } else { return nil }
        }
        XCTAssertTrue(texts.contains("Box<T>"), "drawn texts: \(texts)")
        XCTAssertTrue(texts.contains("+List<int> items"), "drawn texts: \(texts)")
        XCTAssertFalse(texts.contains { $0.contains("~") }, "drawn texts: \(texts)")
        let alt = try XCTUnwrap(MermaidAltText.describe(source: source))
        XCTAssertTrue(alt.contains("Box<T>"), alt)
    }

    /// Pairing tildes is linear: each pair once rescanned the whole member.
    func testLongTildeRunsPairQuickly() throws {
        let start = Date()
        let d = try classes("A : +" + String(repeating: "~", count: 30_000) + String(repeating: "~,", count: 9_000))
        XCTAssertEqual(d.classes.first?.attributes.first?.count, 48_001, "every character stays")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "tilde pairing should be linear")
    }
}
