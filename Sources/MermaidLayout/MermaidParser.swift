import Foundation

/// Parsed Mermaid diagrams: flowcharts, sequence diagrams, pie charts
/// (D1), plus state, class, and ER diagrams (D2). State diagrams reuse the
/// flowchart model — they are nodes and labeled transitions with two extra
/// shapes. Anything else returns nil and the renderer keeps the
/// styled-source fallback.
public enum MermaidDiagram: Hashable, Sendable {
    case flowchart(Flowchart)
    case sequence(SequenceDiagram)
    case pie(PieChart)
    case classDiagram(ClassDiagram)
    case er(ERDiagram)
    case state(StateDiagram)
    case gantt(GanttChart)
    case timeline(Timeline)
    case mindmap(Mindmap)
    case journey(UserJourney)
    case quadrant(QuadrantChart)
    case packet(PacketDiagram)
    case xychart(XYChart)
    case kanban(KanbanBoard)
    case radar(RadarChart)
    case treemap(Treemap)
    case treeView(TreeViewDiagram)
    case venn(VennDiagram)
    case cynefin(CynefinDiagram)
    case wardley(WardleyMap)
    case ishikawa(IshikawaDiagram)
    case eventModeling(EventModelingDiagram)
    case swimlane(SwimlaneDiagram)
    case gitGraph(GitGraph)
    case sankey(SankeyDiagram)
    case requirement(RequirementDiagram)
    case zenuml(ZenUML)
    case c4(C4Diagram)
    case architecture(ArchitectureDiagram)
    case block(BlockDiagram)

    /// A human-readable name for the diagram's type ("flowchart",
    /// "sequence", …) — for accessibility labels, telemetry, and captions.
    public var typeName: String {
        switch self {
        case .flowchart: return "flowchart"
        case .sequence: return "sequence"
        case .pie: return "pie chart"
        case .classDiagram: return "class"
        case .er: return "entity relationship"
        case .state: return "state"
        case .gantt: return "gantt"
        case .timeline: return "timeline"
        case .mindmap: return "mind map"
        case .journey: return "user journey"
        case .quadrant: return "quadrant chart"
        case .packet: return "packet"
        case .xychart: return "xy chart"
        case .kanban: return "kanban"
        case .radar: return "radar chart"
        case .treemap: return "treemap"
        case .treeView: return "treeView"
        case .venn: return "venn"
        case .cynefin: return "cynefin"
        case .wardley: return "wardley"
        case .ishikawa: return "ishikawa"
        case .eventModeling: return "eventmodeling"
        case .swimlane: return "swimlane"
        case .gitGraph: return "git graph"
        case .sankey: return "sankey"
        case .requirement: return "requirement"
        case .zenuml: return "zenuml sequence"
        case .c4: return "C4"
        case .architecture: return "architecture"
        case .block: return "block"
        }
    }

    /// The diagram's title, when its dialect has one — used by the scene
    /// lowering so titles are visible to the geometry linter.
    public var titleText: String? {
        switch self {
        case .pie(let d): return d.title
        case .gantt(let d): return d.title
        case .timeline(let d): return d.title
        case .journey(let d): return d.title
        case .quadrant(let d): return d.title
        case .packet(let d): return d.title
        case .xychart(let d): return d.title
        case .radar(let d): return d.title
        case .wardley(let d): return d.title
        case .cynefin(let d): return d.title
        case .zenuml(let d): return d.title
        case .c4(let d): return d.title
        default: return nil
        }
    }
}

// MARK: - Parser

public enum MermaidParser {

    /// Parses a number that is safe to lay out. `Double.init` happily accepts
    /// "NaN"/"inf", and astronomically large finite values (1e308) overflow to
    /// infinity in span arithmetic — either poisons layout geometry and traps
    /// in Int conversions. Rejects non-finite input and clamps magnitude.
    static func finiteDouble(_ text: some StringProtocol) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return min(max(value, -1e12), 1e12)
    }

    /// Input bounds, mirroring mermaid.js's own defaults (`maxTextSize`,
    /// `maxEdges`). Oversized sources return nil FAST instead of feeding a
    /// quadratic layout for tens of seconds; hosts fall back to showing the
    /// fenced source.
    public static let maxTextSize = 50_000
    public static let maxEdges = 500

    /// Parses D1 diagram types; nil for unsupported types or unparseable
    /// input (the caller falls back to styled source).
    public static func parse(_ source: String) -> MermaidDiagram? {
        parseWithMetadata(source)?.diagram
    }

    /// Parses a diagram AND returns the front-matter/accessibility metadata the
    /// same pass extracted — so a caller that needs both (the render pipeline
    /// caption path) pays a single `stripMetadata` scan instead of parsing and
    /// then re-scanning the whole source with `metadata(in:)`. `parse` is this
    /// with the metadata discarded.
    public static func parseWithMetadata(
        _ source: String
    ) -> (diagram: MermaidDiagram, metadata: DiagramMetadata)? {
        guard source.count <= maxTextSize else { return nil }
        // YAML front-matter (`---\ntitle: ...\n---`) precedes the header in
        // doc examples; without stripping it, `---` became the header and
        // every config-bearing example fell back to styled source. The same
        // pass removes `accTitle:`/`accDescr:` statements so no dialect ever
        // sees them as content (they read back via the returned metadata).
        let (body, metadata) = stripMetadata(from: source)
        guard let diagram = parseBody(body) else { return nil }
        return (diagram, metadata)
    }

    /// Dispatches an already-metadata-stripped body to the per-dialect parsers.
    private static func parseBody(_ source: String) -> MermaidDiagram? {
        let lines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
        guard let header = lines.first else { return nil }

        if header.hasPrefix("graph") || header.hasPrefix("flowchart") {
            return parseFlowchart(header: header, body: Array(lines.dropFirst()))
                .flatMap { $0.edges.count <= maxEdges ? .flowchart($0) : nil }
        }
        if header.hasPrefix("sequenceDiagram") {
            return parseSequence(body: Array(lines.dropFirst())).map { .sequence($0) }
        }
        if header.hasPrefix("pie") {
            return parsePie(header: header, body: Array(lines.dropFirst())).map { .pie($0) }
        }
        if header.hasPrefix("stateDiagram") {
            return parseState(body: Array(lines.dropFirst())).map { .state($0) }
        }
        if header.hasPrefix("classDiagram") {
            return parseClass(body: Array(lines.dropFirst())).map { .classDiagram($0) }
        }
        if header.hasPrefix("erDiagram") {
            return parseER(body: Array(lines.dropFirst())).map { .er($0) }
        }
        if header.hasPrefix("gantt") {
            return parseGantt(body: Array(lines.dropFirst())).map { .gantt($0) }
        }
        if header.hasPrefix("timeline") {
            return parseTimeline(body: Array(lines.dropFirst())).map { .timeline($0) }
        }
        if header.hasPrefix("mindmap") {
            // Indentation is significant, so re-read the raw (untrimmed) source.
            return parseMindmap(source: source).map { .mindmap($0) }
        }
        if header.hasPrefix("journey") {
            return parseJourney(body: Array(lines.dropFirst())).map { .journey($0) }
        }
        if header.hasPrefix("quadrantChart") {
            return parseQuadrant(body: Array(lines.dropFirst())).map { .quadrant($0) }
        }
        if header.hasPrefix("packet") {
            return parsePacket(body: Array(lines.dropFirst())).map { .packet($0) }
        }
        if header.hasPrefix("xychart") {
            return parseXYChart(body: Array(lines.dropFirst())).map { .xychart($0) }
        }
        if header.hasPrefix("kanban") {
            // Indentation is significant, so re-read the raw (untrimmed) source.
            return parseKanban(source: source).map { .kanban($0) }
        }
        if header.hasPrefix("radar") {
            return parseRadar(body: Array(lines.dropFirst())).map { .radar($0) }
        }
        if header.hasPrefix("treeView") {
            // Indentation is significant, so re-read the raw source.
            return parseTreeView(source: source).map { .treeView($0) }
        }
        if header.hasPrefix("venn") {
            return parseVenn(body: Array(lines.dropFirst())).map { .venn($0) }
        }
        if header.hasPrefix("cynefin") {
            return parseCynefin(body: Array(lines.dropFirst())).map { .cynefin($0) }
        }
        if header.hasPrefix("ishikawa") {
            // Indentation is significant, so re-read the raw source.
            return parseIshikawa(source: source).map { .ishikawa($0) }
        }
        if header.hasPrefix("eventmodeling") {
            return parseEventModeling(body: Array(lines.dropFirst())).map { .eventModeling($0) }
        }
        if header.hasPrefix("swimlane") {
            return parseSwimlane(header: header, body: Array(lines.dropFirst())).map { .swimlane($0) }
        }
        if header.hasPrefix("wardley") {
            return parseWardley(body: Array(lines.dropFirst())).map { .wardley($0) }
        }
        if header.hasPrefix("treemap") {
            // Indentation is significant, so re-read the raw (untrimmed) source.
            return parseTreemap(source: source).map { .treemap($0) }
        }
        if header.hasPrefix("gitGraph") {
            return parseGitGraph(body: Array(lines.dropFirst())).map { .gitGraph($0) }
        }
        if header.hasPrefix("sankey") {
            return parseSankey(body: Array(lines.dropFirst())).map { .sankey($0) }
        }
        if header.hasPrefix("requirementDiagram") {
            return parseRequirement(body: Array(lines.dropFirst())).map { .requirement($0) }
        }
        if header.hasPrefix("zenuml") {
            return parseZenUML(body: Array(lines.dropFirst())).map { .zenuml($0) }
        }
        if header.hasPrefix("C4") {
            return parseC4(body: Array(lines.dropFirst())).map { .c4($0) }
        }
        if header.hasPrefix("architecture") {
            return parseArchitecture(body: Array(lines.dropFirst())).map { .architecture($0) }
        }
        if header.hasPrefix("block-beta") {
            return parseBlock(body: Array(lines.dropFirst())).map { .block($0) }
        }
        return nil
    }

    // MARK: Flowchart

    static func parseFlowchart(header: String, body: [String]) -> Flowchart? {
        let parts = header.split(separator: " ")
        let direction = parts.count > 1
            ? Flowchart.Direction(rawValue: String(parts[1]).uppercased()) ?? .topDown
            : .topDown

        var nodes: [String: Flowchart.Node] = [:]
        var order: [String] = []
        var edges: [Flowchart.Edge] = []

        // Subgraph nesting: a stack of open subgraph ids, plus the accumulated
        // definitions. Membership is recorded when a node is FIRST noted while
        // a subgraph is open, so a node belongs to the innermost block it
        // appears in — matching mermaid.
        var subgraphs: [String: Flowchart.Subgraph] = [:]
        var subgraphOrder: [String] = []
        var stack: [String] = []
        var membership: [String: String] = [:]
        var anonCount = 0

        func note(_ node: Flowchart.Node) {
            if let existing = nodes[node.id] {
                // A later declaration with an explicit label wins over a bare id.
                if node.label != node.id || existing.label == existing.id {
                    if node.label != node.id { nodes[node.id] = node }
                }
            } else {
                nodes[node.id] = node
                order.append(node.id)
            }
            // Membership: the first subgraph block a node textually appears in
            // claims it (an inside reference wins over an earlier outside one;
            // an inner block wins over its outer). Nodes only ever seen at the
            // top level stay unclaimed.
            if let top = stack.last, subgraphs[top] != nil, membership[node.id] == nil {
                membership[node.id] = top
                subgraphs[top]!.nodeIDs.append(node.id)
            }
        }

        for line in body {
            if line.hasPrefix("subgraph") {
                let id = openSubgraph(line, into: &subgraphs, order: &subgraphOrder,
                                      stack: stack, anonCount: &anonCount)
                if let parent = stack.last, subgraphs[parent] != nil {
                    subgraphs[parent]!.childIDs.append(id)
                }
                stack.append(id)
                continue
            }
            if line == "end" { if !stack.isEmpty { stack.removeLast() }; continue }
            if line.hasPrefix("direction ") {
                // Scoped to the innermost open subgraph. A top-level direction
                // line is dropped (the header token already set the chart's
                // flow); either way it never leaks in as a phantom node.
                if let top = stack.last, subgraphs[top] != nil {
                    subgraphs[top]!.direction = Flowchart.Direction(
                        rawValue: normalizedDirectionToken(line.dropFirst("direction".count)))
                }
                continue
            }
            if line.hasPrefix("classDef") || line.hasPrefix("class ") || line.hasPrefix("style") { continue }

            // Split on edge connectors, keeping the connector kind.
            // Supported: --> , --- , -.-> , ==> , with optional |label|.
            if let parsed = parseEdgeLine(line), !parsed.isEmpty {
                for edge in parsed {
                    note(edge.fromNode)
                    note(edge.toNode)
                    edges.append(edge.edge)
                }
                continue
            }

            // Standalone node declaration.
            if let node = parseNodeToken(Substring(line)) {
                note(node)
            }
        }

        // An edge endpoint naming a subgraph id minted a phantom node above;
        // drop those — the layout resolves the id to the group's box. Also
        // scrub them from any membership list they slipped into.
        let subgraphIDs = Set(subgraphOrder)
        for id in subgraphIDs {
            nodes.removeValue(forKey: id)
            order.removeAll { $0 == id }
        }
        for key in subgraphs.keys {
            subgraphs[key]!.nodeIDs.removeAll { subgraphIDs.contains($0) }
        }

        guard !nodes.isEmpty else { return nil }
        return Flowchart(
            direction: direction,
            nodes: order.compactMap { nodes[$0] },
            edges: edges,
            subgraphs: subgraphOrder.compactMap { subgraphs[$0] }
        )
    }

    /// Normalizes a `direction` token (`TB` is mermaid's alias for `TD`).
    private static func normalizedDirectionToken(_ raw: Substring) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return t == "TB" ? "TD" : t
    }

    /// Parses a `subgraph …` header into a fresh subgraph definition and
    /// registers it. Accepts `subgraph id[Label]`, `subgraph id`, a bare
    /// `subgraph "Title"`, and an anonymous `subgraph` (synthesized id).
    private static func openSubgraph(
        _ line: String,
        into subgraphs: inout [String: Flowchart.Subgraph],
        order: inout [String],
        stack: [String],
        anonCount: inout Int
    ) -> String {
        let rest = String(line.dropFirst("subgraph".count)).trimmingCharacters(in: .whitespaces)
        var id: String
        var label: String
        if rest.isEmpty {
            id = "\u{a7}sub\(anonCount)"; anonCount += 1
            label = ""
        } else if let open = rest.firstIndex(of: "["), let close = rest.lastIndex(of: "]"), open < close {
            id = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
            label = String(rest[rest.index(after: open)..<close])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if id.isEmpty { id = "\u{a7}sub\(anonCount)"; anonCount += 1 }
        } else if rest.hasPrefix("\"") {
            label = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            id = "\u{a7}sub\(anonCount)"; anonCount += 1
        } else {
            id = rest; label = rest
        }
        // Guard against a duplicate/reused id clobbering an open block.
        if subgraphs[id] != nil { id = "\u{a7}sub\(anonCount)"; anonCount += 1 }
        subgraphs[id] = Flowchart.Subgraph(id: id, label: label)
        order.append(id)
        return id
    }

    private struct ParsedEdge {
        let fromNode: Flowchart.Node
        let toNode: Flowchart.Node
        let edge: Flowchart.Edge
    }

    /// Normalizes edge-syntax variants onto the five canonical connectors so
    /// one scanner handles them all: inline labels (`-- text -->` becomes
    /// `-->|text|`), min-length stretches (`---->`), circle/cross heads
    /// (`--o`/`--x`, drawn as plain arrows — an honest degradation), and edge
    /// IDs (`e1@-->`), which are animation targets we drop.
    private static func normalizeEdgeSyntax(_ line: String) -> String {
        func sub(_ pattern: String, _ template: String, _ s: String) -> String {
            (try? NSRegularExpression(pattern: pattern))
                .map { $0.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                                   withTemplate: template) } ?? s
        }
        var s = line
        s = sub(#"\s\w+@(?=[-=<])"#, " ", s)                         // edge IDs
        s = sub(#"--\s+([^-|>][^-]*?)\s+-->"#, "-->|$1|", s)         // -- text -->
        s = sub(#"-\.\s+([^.|]+?)\s+\.->"#, "-.->|$1|", s)          // -. text .->
        s = sub(#"==\s+([^=|>][^=]*?)\s+==>"#, "==>|$1|", s)         // == text ==>
        s = sub(#"o--o"#, "<-->", s)                                  // circle both ends
        s = sub(#"x--x"#, "<-->", s)                                  // cross both ends
        s = sub(#"--[ox](\s|$)"#, "-->$1", s)                         // --o / --x heads
        s = sub(#"-{3,}>"#, "-->", s)                                 // ---->
        s = sub(#"={3,}>"#, "==>", s)                                 // ====>
        s = sub(#"-\.{2,}-(?![->])"#, "-.-", s)                       // -..-
        s = sub(#"(?<![-.>])-{4,}(?![->])"#, "---", s)                 // -----
        return s
    }

    /// Splits an endpoint list on `&` at bracket depth 0 only, so labels
    /// like `A[Tom & Jerry]` stay intact.
    private static func splitEndpoints(_ text: String) -> [Substring] {
        var parts: [Substring] = []
        var depth = 0
        var start = text.startIndex
        for i in text.indices {
            switch text[i] {
            case "[", "(", "{": depth += 1
            case "]", ")", "}": depth -= 1
            case "&" where depth == 0:
                parts.append(text[start..<i])
                start = text.index(after: i)
            default: break
            }
        }
        parts.append(text[start...])
        return parts
    }

    /// Parses one line's worth of edges — chained (`A --> B --> C`) and
    /// fanned (`A & B --> C`) forms yield several. The old single-edge parser
    /// silently erased any line it couldn't fully tokenize, which killed the
    /// most common idioms in real flowcharts.
    private static func parseEdgeLine(_ raw: String) -> [ParsedEdge]? {
        let line = normalizeEdgeSyntax(raw)
        let connectors: [(token: String, dashed: Bool, arrow: Bool)] = [
            ("-.->", true, true), ("==>", false, true), ("-->", false, true),
            ("-.-", true, false), ("---", false, false),
        ]
        var segments: [String] = []
        var joins: [(dashed: Bool, arrow: Bool, back: Bool, label: String?)] = []
        var rest = Substring(line)
        while true {
            var best: (range: Range<Substring.Index>, connector: (token: String, dashed: Bool, arrow: Bool))?
            for connector in connectors {
                if let r = rest.range(of: connector.token),
                   best == nil || r.lowerBound < best!.range.lowerBound {
                    best = (r, connector)
                }
            }
            guard let found = best else {
                segments.append(String(rest))
                break
            }
            var left = String(rest[..<found.range.lowerBound]).trimmingCharacters(in: .whitespaces)
            var back = false
            if left.hasSuffix("<") { back = true; left = String(left.dropLast()) }
            segments.append(left)
            var after = rest[found.range.upperBound...].drop(while: { $0 == " " })
            var label: String?
            if after.hasPrefix("|"), let close = after.dropFirst().firstIndex(of: "|") {
                label = String(after[after.index(after: after.startIndex)..<close])
                after = after[after.index(after: close)...]
            }
            joins.append((found.connector.dashed, found.connector.arrow, back, label))
            rest = after
        }
        guard !joins.isEmpty, segments.count == joins.count + 1 else { return nil }

        var out: [ParsedEdge] = []
        for (i, join) in joins.enumerated() {
            let lefts = splitEndpoints(segments[i]).compactMap(parseNodeToken)
            let rights = splitEndpoints(segments[i + 1]).compactMap(parseNodeToken)
            guard !lefts.isEmpty, !rights.isEmpty else { return nil }
            for l in lefts {
                for r in rights {
                    out.append(ParsedEdge(
                        fromNode: l, toNode: r,
                        edge: Flowchart.Edge(from: l.id, to: r.id, label: join.label,
                                             dashed: join.dashed, hasArrow: join.arrow,
                                             backArrow: join.back)))
                }
            }
        }
        return out
    }

    /// Parses `id`, `id[Label]`, `id(Label)`, `id([Label])`, `id{Label}`,
    /// `id((Label))`.
    static func parseNodeToken(_ token: Substring) -> Flowchart.Node? {
        var trimmed = token.trimmingCharacters(in: .whitespaces)
        // `:::className` binds a style class — styling we ignore; without
        // this strip the tokenizer rejected the node and the line vanished.
        if let styleClass = trimmed.range(of: ":::") {
            trimmed = String(trimmed[..<styleClass.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        guard !trimmed.isEmpty else { return nil }

        var id = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex,
              trimmed[index].isLetter || trimmed[index].isNumber || trimmed[index] == "_" {
            id.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !id.isEmpty else { return nil }
        let rest = String(trimmed[index...])

        func stripped(_ open: String, _ close: String) -> String? {
            guard rest.hasPrefix(open), rest.hasSuffix(close),
                  rest.count >= open.count + close.count else { return nil }
            return String(rest.dropFirst(open.count).dropLast(close.count))
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        if rest.isEmpty {
            return Flowchart.Node(id: id, label: id, shape: .rectangle)
        }
        if let label = stripped("((", "))") {
            return Flowchart.Node(id: id, label: label, shape: .circle)
        }
        if let label = stripped("([", "])") {
            return Flowchart.Node(id: id, label: label, shape: .stadium)
        }
        if let label = stripped("[(", ")]") {
            return Flowchart.Node(id: id, label: label, shape: .cylinder)
        }
        if let label = stripped("[", "]") {
            return Flowchart.Node(id: id, label: label, shape: .rectangle)
        }
        if let label = stripped("(", ")") {
            return Flowchart.Node(id: id, label: label, shape: .rounded)
        }
        if let label = stripped("{", "}") {
            return Flowchart.Node(id: id, label: label, shape: .diamond)
        }
        return nil
    }

    // MARK: State

    /// stateDiagram / stateDiagram-v2 → a nested StateDiagram. `state X { … }`
    /// blocks recurse into composites (each with its own `[*]` entry/exit);
    /// `<<choice>>` / `<<fork>>` / `<<join>>` annotations mark special shapes;
    /// transitions are arrows with an optional `: label`.
    static func parseState(body: [String]) -> StateDiagram? {
        // Composite parsing (and the layout that mirrors it) recurses once per
        // `state X {` nesting level. A linear pre-scan bounds that depth so
        // adversarial input can't overflow the stack — past the cap the block
        // degrades to the tidy styled-source card.
        var depth = 0, maxDepth = 0
        for line in body {
            if line.hasPrefix("state "), line.hasSuffix("{") { depth += 1; maxDepth = max(maxDepth, depth) }
            if line == "}" { depth = max(0, depth - 1) }
        }
        guard maxDepth <= 32 else { return nil }

        var index = 0
        var scopeCounter = 0
        let direction = detectStateDirection(body)

        // Recursively parses one brace scope, consuming lines until its
        // closing `}` (or end of input for the root). `scopeID` disambiguates
        // this scope's synthetic `[*]` terminals from every other scope's.
        func parseScope(scopeID: String) -> StateDiagram {
            var nodes: [String: StateDiagram.Node] = [:]
            var order: [String] = []
            var edges: [StateDiagram.Edge] = []
            var annotations: [String: StateDiagram.Kind] = [:]  // id → choice/fork/join

            func note(id: String, label: String, kind: StateDiagram.Kind) {
                if let existing = nodes[id] {
                    // Upgrade a bare reference to a labelled / composite node.
                    if existing.label == existing.id && (label != id || !isSimple(kind)) {
                        nodes[id] = StateDiagram.Node(id: id, label: label, kind: kind)
                    } else if isComposite(kind) {
                        nodes[id] = StateDiagram.Node(id: id, label: label, kind: kind)
                    }
                } else {
                    nodes[id] = StateDiagram.Node(id: id, label: label, kind: kind)
                    order.append(id)
                }
            }

            // Resolves a transition endpoint token to a node id, minting a
            // scope-local terminal for `[*]`.
            func endpoint(_ token: String, isSource: Bool) -> String? {
                let trimmed = token.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                if trimmed == "[*]" {
                    let id = isSource ? "\(scopeID)__start" : "\(scopeID)__end"
                    note(id: id, label: "", kind: isSource ? .start : .end)
                    return id
                }
                guard trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
                note(id: trimmed, label: trimmed, kind: .simple)
                return trimmed
            }

            while index < body.count {
                let line = body[index]
                index += 1

                if line == "}" { break }                       // close this scope
                if line.hasPrefix("direction") { continue }    // handled globally
                if line.hasPrefix("note") || line.hasPrefix("Note") { continue }

                // `state X { ` opens a composite — recurse.
                if line.hasPrefix("state "), line.hasSuffix("{") {
                    let inner = String(line.dropFirst("state ".count).dropLast())
                        .trimmingCharacters(in: .whitespaces)
                    let (id, label) = stateNameAndLabel(inner)
                    scopeCounter += 1
                    let child = parseScope(scopeID: "s\(scopeCounter)_")
                    nodes[id] = StateDiagram.Node(id: id, label: label, kind: .composite(child))
                    if !order.contains(id) { order.append(id) }
                    continue
                }

                // `state X <<choice>>` / `<<fork>>` / `<<join>>` annotations.
                if line.hasPrefix("state "), let annotationRange = line.range(of: "<<") {
                    let id = String(line[line.index(line.startIndex, offsetBy: "state ".count)..<annotationRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    let annotation = line[annotationRange.lowerBound...]
                    let kind: StateDiagram.Kind? = annotation.contains("choice") ? .choice
                        : annotation.contains("fork") ? .fork
                        : annotation.contains("join") ? .join : nil
                    if let kind, !id.isEmpty {
                        annotations[id] = kind
                        note(id: id, label: id, kind: kind)
                    }
                    continue
                }

                // `state "Long description" as s2`
                if line.hasPrefix("state ") {
                    let declaration = String(line.dropFirst("state ".count))
                    if let asRange = declaration.range(of: " as ") {
                        let label = String(declaration[..<asRange.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        let id = String(declaration[asRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if !id.isEmpty { note(id: id, label: label, kind: .simple) }
                    } else {
                        let (id, label) = stateNameAndLabel(declaration.trimmingCharacters(in: .whitespaces))
                        if !id.isEmpty { note(id: id, label: label, kind: .simple) }
                    }
                    continue
                }

                if let arrowRange = line.range(of: "-->") {
                    let left = String(line[..<arrowRange.lowerBound])
                    var right = String(line[arrowRange.upperBound...])
                    var label: String?
                    if let colon = right.firstIndex(of: ":") {
                        label = String(right[right.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        right = String(right[..<colon])
                    }
                    guard let from = endpoint(left, isSource: true),
                          let to = endpoint(right, isSource: false) else { continue }
                    edges.append(StateDiagram.Edge(from: from, to: to, label: label))
                    continue
                }

                // Bare state id on its own line.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    note(id: trimmed, label: trimmed, kind: .simple)
                }
            }

            // Apply any annotations that arrived after a node was first seen.
            for (id, kind) in annotations where nodes[id] != nil {
                nodes[id] = StateDiagram.Node(id: id, label: nodes[id]!.label == id ? id : nodes[id]!.label, kind: kind)
            }

            return StateDiagram(
                direction: direction,
                nodes: order.compactMap { nodes[$0] },
                edges: edges
            )
        }

        let root = parseScope(scopeID: "root_")
        guard !root.nodes.isEmpty else { return nil }
        return root
    }

    private static func detectStateDirection(_ body: [String]) -> Flowchart.Direction {
        for line in body where line.hasPrefix("direction") {
            let value = line.dropFirst("direction".count).trimmingCharacters(in: .whitespaces)
            return Flowchart.Direction(rawValue: value.uppercased()) ?? .topDown
        }
        return .topDown
    }

    /// `Foo` → (Foo, Foo); `Foo : Nice Label` → (Foo, "Nice Label").
    private static func stateNameAndLabel(_ text: String) -> (String, String) {
        if let colon = text.firstIndex(of: ":") {
            let id = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let label = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return (id, label.isEmpty ? id : label)
        }
        let id = text.trimmingCharacters(in: .whitespaces)
        return (id, id)
    }

    private static func isSimple(_ kind: StateDiagram.Kind) -> Bool {
        if case .simple = kind { return true }
        return false
    }
    private static func isComposite(_ kind: StateDiagram.Kind) -> Bool {
        if case .composite = kind { return true }
        return false
    }

    // MARK: Class

    static func parseClass(body: [String]) -> ClassDiagram? {
        var classes: [String: ClassDiagram.Class] = [:]
        var order: [String] = []
        var relations: [ClassDiagram.Relation] = []
        var openClass: String? // inside `class X { … }`

        func note(_ name: String) {
            guard !name.isEmpty, classes[name] == nil else { return }
            classes[name] = ClassDiagram.Class(name: name, attributes: [], methods: [])
            order.append(name)
        }

        func addMember(_ raw: String, to name: String) {
            let member = raw.trimmingCharacters(in: .whitespaces)
            guard !member.isEmpty else { return }
            note(name)
            if member.contains("(") {
                classes[name]?.methods.append(member)
            } else {
                classes[name]?.attributes.append(member)
            }
        }

        // Mermaid multiplicity labels sit as a quoted token next to the
        // connector: `ClassA "1" *-- "many" ClassB`. Strip them so the
        // endpoint names still match the declared classes.
        func stripMultiplicity(_ text: String, trailing: Bool) -> String {
            let pattern = trailing ? #"\s*"[^"]*"$"# : #"^"[^"]*"\s*"#
            guard let range = text.range(of: pattern, options: .regularExpression) else { return text }
            let stripped = trailing ? text[..<range.lowerBound] : text[range.upperBound...]
            return stripped.trimmingCharacters(in: .whitespaces)
        }

        // Relation connectors, longest first. Reversed forms flip from/to
        // so the marker is always at the `to` end.
        let connectors: [(token: String, kind: ClassDiagram.RelationKind, reversed: Bool)] = [
            ("<|--", .inheritance, true), ("--|>", .inheritance, false),
            ("<|..", .realization, true), ("..|>", .realization, false),
            ("*--", .composition, true), ("--*", .composition, false),
            ("o--", .aggregation, true), ("--o", .aggregation, false),
            ("<--", .association, true), ("-->", .association, false),
            ("<..", .dependency, true), ("..>", .dependency, false),
            ("--", .link, false), ("..", .link, false),
        ]

        for line in body {
            if let current = openClass {
                if line == "}" { openClass = nil; continue }
                addMember(line, to: current)
                continue
            }
            if line.hasPrefix("class ") {
                var declaration = String(line.dropFirst("class ".count)).trimmingCharacters(in: .whitespaces)
                if declaration.hasSuffix("{") {
                    declaration = String(declaration.dropLast()).trimmingCharacters(in: .whitespaces)
                    openClass = declaration
                }
                note(declaration)
                continue
            }
            if line.hasPrefix("<<") || line.hasPrefix("note") { continue }

            // Member via colon shorthand: `Animal : +int age` — but only
            // when no relation connector is present on the line.
            if !connectors.contains(where: { line.contains($0.token) }),
               let colon = line.firstIndex(of: ":") {
                let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    addMember(String(line[line.index(after: colon)...]), to: name)
                }
                continue
            }

            for connector in connectors {
                guard let range = line.range(of: connector.token) else { continue }
                let left = stripMultiplicity(
                    String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    trailing: true
                )
                var right = String(line[range.upperBound...])
                var label: String?
                if let colon = right.firstIndex(of: ":") {
                    label = String(right[right.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    right = String(right[..<colon])
                }
                let rightName = stripMultiplicity(right.trimmingCharacters(in: .whitespaces), trailing: false)
                guard !left.isEmpty, !rightName.isEmpty else { break }
                let from = connector.reversed ? rightName : left
                let to = connector.reversed ? left : rightName
                note(left)
                note(rightName)
                relations.append(ClassDiagram.Relation(from: from, to: to, kind: connector.kind, label: label))
                break
            }
        }

        guard !classes.isEmpty else { return nil }
        return ClassDiagram(classes: order.compactMap { classes[$0] }, relations: relations)
    }

    // MARK: ER

    static func parseER(body: [String]) -> ERDiagram? {
        var entities: [String: ERDiagram.Entity] = [:]
        var order: [String] = []
        var relations: [ERDiagram.Relation] = []
        var openEntity: String?

        func note(_ name: String) {
            guard !name.isEmpty, entities[name] == nil else { return }
            entities[name] = ERDiagram.Entity(name: name, attributes: [])
            order.append(name)
        }

        func cardinality(_ token: String) -> ERDiagram.Cardinality? {
            // Left-side tokens read outward (||, |o, }o, }|); right-side
            // tokens are mirrored (||, o|, o{, |{). Normalize both.
            switch token {
            case "||": return .one
            case "|o", "o|": return .zeroOrOne
            case "}|", "|{": return .oneOrMore
            case "}o", "o{": return .zeroOrMore
            default: return nil
            }
        }

        for line in body {
            if let current = openEntity {
                if line == "}" { openEntity = nil; continue }
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    entities[current]?.attributes.append(
                        ERDiagram.Attribute(type: String(parts[0]), name: String(parts[1]))
                    )
                }
                continue
            }
            if line.hasSuffix("{"), !line.contains("--"), !line.contains("..") {
                let name = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    note(name)
                    openEntity = name
                }
                continue
            }

            // A ||--o{ B : label   (also `..` for non-identifying)
            for separator in ["--", ".."] {
                guard let range = line.range(of: separator) else { continue }
                let left = String(line[..<range.lowerBound])
                var right = String(line[range.upperBound...])
                guard left.count >= 2, right.count >= 2 else { continue }
                let leftCardToken = String(left.suffix(2))
                let rightCardToken = String(right.prefix(2))
                guard let fromCard = cardinality(leftCardToken),
                      let toCard = cardinality(rightCardToken)
                else { continue }
                let from = String(left.dropLast(2)).trimmingCharacters(in: .whitespaces)
                right = String(right.dropFirst(2))
                var label = ""
                if let colon = right.firstIndex(of: ":") {
                    label = String(right[right.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    right = String(right[..<colon])
                }
                let to = right.trimmingCharacters(in: .whitespaces)
                guard !from.isEmpty, !to.isEmpty else { continue }
                note(from)
                note(to)
                relations.append(ERDiagram.Relation(
                    from: from, to: to,
                    fromCard: fromCard, toCard: toCard,
                    label: label, identifying: separator == "--"
                ))
                break
            }
        }

        guard !entities.isEmpty else { return nil }
        return ERDiagram(entities: order.compactMap { entities[$0] }, relations: relations)
    }

    // MARK: Sequence

    static func parseSequence(body: [String]) -> SequenceDiagram? {
        var participants: [String: SequenceDiagram.Participant] = [:]
        var order: [String] = []
        var messages: [SequenceDiagram.Message] = []

        var notes: [SequenceDiagram.Note] = []
        var declaredKind: [String: SequenceDiagram.Participant.Kind] = [:]
        var fragments: [SequenceDiagram.Fragment] = []
        var boxes: [SequenceDiagram.Box] = []
        var openBox: (label: String?, members: [String])?
        var events: [SequenceDiagram.Event] = []
        var openFragments: [Int] = []   // stack of fragment indices
        func note(_ id: String, label: String? = nil, isActor: Bool = false) {
            if participants[id] == nil {
                participants[id] = SequenceDiagram.Participant(id: id, label: label ?? id, isActor: isActor)
                order.append(id)
            } else if let label {
                participants[id] = SequenceDiagram.Participant(
                    id: id, label: label, isActor: participants[id]?.isActor == true || isActor)
            }
        }

        var autonumber = 0   // 0 = off; >0 = next number to stamp
        var autonumberStep = 1
        for line in body {
            if line == "autonumber" || line.hasPrefix("autonumber ") {
                // `autonumber` / `autonumber 10` / `autonumber 10 5` /
                // `autonumber off`.
                let parts = line.split(separator: " ").dropFirst().map(String.init)
                if parts.first == "off" { autonumber = 0 }
                else {
                    autonumber = parts.first.flatMap(Int.init) ?? 1
                    autonumberStep = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
                }
                continue
            }
            if line.hasPrefix("participant") || line.hasPrefix("actor") {
                // Strip only the leading keyword — a global replace once
                // corrupted labels containing the word "actor ".
                var declaration = line
                var isActor = false
                if declaration.hasPrefix("participant ") { declaration = String(declaration.dropFirst(12)) }
                else if declaration.hasPrefix("actor ") { declaration = String(declaration.dropFirst(6)); isActor = true }
                // Typed heads: `participant B@{ "type": "database" }`.
                var kind: SequenceDiagram.Participant.Kind? = isActor ? .actor : nil
                if let at = declaration.range(of: "@{") {
                    let spec = String(declaration[at.upperBound...])
                    if let typeRange = spec.range(of: "type") {
                        let value = spec[typeRange.upperBound...]
                            .trimmingCharacters(in: CharacterSet(charactersIn: " :\"'}"))
                        if let parsed = SequenceDiagram.Participant.Kind(
                            rawValue: value.lowercased()) { kind = parsed }
                    }
                    declaration = String(declaration[..<at.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                let id: String
                if let asRange = declaration.range(of: " as ") {
                    id = String(declaration[..<asRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let label = String(declaration[asRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    note(id, label: label, isActor: kind == .actor)
                } else {
                    id = declaration.trimmingCharacters(in: .whitespaces)
                    note(id, isActor: kind == .actor)
                }
                if let kind { declaredKind[id] = kind }
                openBox?.members.append(id)
                continue
            }
            // `Note right of A: text` / `Note left of A: text` /
            // `Note over A,B: text` — author content that used to vanish.
            if line.lowercased().hasPrefix("note ") {
                let rest = String(line.dropFirst(5))
                let lower = rest.lowercased()
                var position: SequenceDiagram.Note.Position?
                var idText = ""
                if lower.hasPrefix("right of ") { position = .rightOf; idText = String(rest.dropFirst(9)) }
                else if lower.hasPrefix("left of ") { position = .leftOf; idText = String(rest.dropFirst(8)) }
                else if lower.hasPrefix("over ") { position = .over; idText = String(rest.dropFirst(5)) }
                if let position, let colon = idText.firstIndex(of: ":") {
                    let ids = idText[..<colon].split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let text = String(idText[idText.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    if !ids.isEmpty, !text.isEmpty {
                        ids.forEach { note($0) }
                        notes.append(.init(position: position, ids: ids, text: text,
                                           afterMessage: messages.count))
                        events.append(.note(notes.count - 1))
                        continue
                    }
                }
                continue // malformed note: skip, never a phantom message
            }
            // Combined fragments: a tolerant stack machine. Unclosed frames
            // close at end-of-diagram; a stray `end` is ignored.
            let keyword = line.split(separator: " ").first.map(String.init) ?? line
            if let kind = SequenceDiagram.Fragment.Kind(rawValue: keyword) {
                let label = line.count > keyword.count
                    ? String(line.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                    : nil
                fragments.append(.init(kind: kind, label: label?.isEmpty == true ? nil : label))
                openFragments.append(fragments.count - 1)
                events.append(.open(fragments.count - 1))
                continue
            }
            if keyword == "else" || keyword == "and" || keyword == "option" {
                if let top = openFragments.last {
                    let label = line.count > keyword.count
                        ? String(line.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                        : nil
                    events.append(.divider(fragment: top, label: label?.isEmpty == true ? nil : label))
                }
                continue
            }
            if line == "end" {
                if openBox != nil {
                    // `end` closes the innermost construct: an open box wins
                    // (boxes can't contain messages, so no ambiguity).
                    boxes.append(.init(label: openBox!.label, memberIDs: openBox!.members))
                    openBox = nil
                } else if let top = openFragments.popLast() {
                    events.append(.close(top))
                }
                continue
            }
            if line.hasPrefix("create participant ") || line.hasPrefix("create actor ") {
                let isActor = line.hasPrefix("create actor ")
                let declaration = String(line.dropFirst(isActor ? 13 : 19))
                let id: String
                if let asRange = declaration.range(of: " as ") {
                    id = String(declaration[..<asRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    note(id, label: String(declaration[asRange.upperBound...]).trimmingCharacters(in: .whitespaces),
                         isActor: isActor)
                } else {
                    id = declaration.trimmingCharacters(in: .whitespaces)
                    note(id, isActor: isActor)
                }
                if !id.isEmpty { events.append(.create(id)) }
                continue
            }
            if line.hasPrefix("destroy ") {
                let id = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { note(id); events.append(.destroy(id)) }
                continue
            }
            if line.hasPrefix("activate ") {
                let id = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { note(id); events.append(.activate(id)) }
                continue
            }
            if line.hasPrefix("deactivate ") {
                let id = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { events.append(.deactivate(id)) }
                continue
            }
            if line.hasPrefix("box ") || line == "box" {
                // `box [color] Label` — the first token may be a CSS color or
                // rgb(...)/transparent; everything else is the label.
                var label: String? = line == "box" ? nil : String(line.dropFirst(4))
                if let text = label {
                    let tokens = text.split(separator: " ").map(String.init)
                    let colorish = tokens.first.map { token in
                        token.lowercased() == "transparent" || token.hasPrefix("rgb(")
                            || token.hasPrefix("#")
                            || ["aqua", "aliceblue", "lightblue", "lightgrey", "lightgreen",
                                "lightyellow", "mistyrose", "lavender", "beige"].contains(token.lowercased())
                    } ?? false
                    label = colorish ? tokens.dropFirst().joined(separator: " ") : text
                    if label?.isEmpty == true { label = nil }
                }
                openBox = (label, [])
                continue
            }

            // Messages. Longest token first so `-->>` never part-matches as
            // `-->`. Every mermaid arrow token maps to its true head style.
            typealias Head = SequenceDiagram.Message.ArrowHead
            let arrowTokens: [(token: String, dashed: Bool, head: Head)] = [
                ("<<-->>", true, .both), ("<<->>", false, .both),
                ("--)", true, .open), ("-->>", true, .filled), ("->>", false, .filled),
                ("-->", true, .none), ("--x", true, .cross), ("-)", false, .open),
                ("-x", false, .cross), ("->", false, .none),
            ]
            for (token, dashed, head) in arrowTokens {
                guard let range = line.range(of: token) else { continue }
                var from = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let remainder = String(line[range.upperBound...])
                let pieces = remainder.split(separator: ":", maxSplits: 1)
                var to = pieces.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                let text = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
                // Activation shorthand: `A->>+B:` / `B->>-A:` — the +/- binds
                // activation, it is NOT part of the participant name. The old
                // parser minted phantom "+B"/"-B" lifelines from the docs'
                // very first example.
                var activates = false
                var deactivates = false
                if to.hasPrefix("+") { activates = true }
                if to.hasPrefix("-") { deactivates = true }   // `->>-A:` deactivates the RECEIVER-side sender form below
                if to.hasPrefix("+") || to.hasPrefix("-") { to = String(to.dropFirst()).trimmingCharacters(in: .whitespaces) }
                if from.hasSuffix("+") || from.hasSuffix("-") { from = String(from.dropLast()).trimmingCharacters(in: .whitespaces) }
                guard !from.isEmpty, !to.isEmpty else { break }
                var number: Int?
                if autonumber > 0 {
                    number = autonumber
                    autonumber += autonumberStep
                }
                note(from)
                note(to)
                messages.append(SequenceDiagram.Message(
                    from: from, to: to, text: text, dashed: dashed,
                    head: head, number: number,
                    activatesTarget: activates, deactivatesSender: deactivates))
                events.append(.message(messages.count - 1))
                break
            }
        }

        guard !participants.isEmpty else { return nil }
        // Close any unclosed frames (author forgot `end`): tolerant, not fatal.
        while let top = openFragments.popLast() { events.append(.close(top)) }
        if let box = openBox { boxes.append(.init(label: box.label, memberIDs: box.members)) }
        return SequenceDiagram(
            participants: order.compactMap { id -> SequenceDiagram.Participant? in
                guard var participant = participants[id] else { return nil }
                if let kind = declaredKind[id] { participant.kind = kind }
                return participant
            },
            boxes: boxes,
            notes: notes,
            fragments: fragments,
            events: events,
            messages: messages
        )
    }

}
