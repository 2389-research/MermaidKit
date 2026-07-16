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

    // MARK: flowchart subgraphs

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
