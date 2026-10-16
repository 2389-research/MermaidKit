import Foundation

// The inverse of `DOTParser`: emits a `Flowchart` as Graphviz DOT text. Together
// they make MermaidKit a Mermaid⇄DOT converter — parse a `flowchart` (or a `.dot`
// source) into the `Flowchart` IR, then emit DOT that Graphviz can render.
//
// Round-trip contract: for a **flat** chart (no subgraphs) the output re-parses
// via `DOTParser` to an *equal* `Flowchart` — `DOT → Flowchart → DOT` is a fixed
// point. Clustered charts round-trip *structurally* (same nodes, membership, and
// edges) but not necessarily in node order, because Graphviz assigns a node to
// the cluster it is first mentioned in, so cluster members must be emitted inside
// the cluster block rather than in original chart order.
//
// Lossy shapes: `subroutine`, `asymmetric` and the state pseudo-nodes
// (`stateStart`/`stateEnd`) have no DOT shape `DOTParser` recognizes, and
// `parallelogramAlt` has no mirrored one, so they emit their nearest DOT shape
// (`box` / `circle` / `parallelogram`) and re-parse to that — they do not
// round-trip to themselves. Every other shape does. Of the edges, only a cross
// head (`--x`) is lossy: DOT has no cross arrowhead, so it re-parses as an arrow.
// (Importing is lossy the other way: every dot-family DOT arrow reads as a
// circle head, and a `dir=both` edge with different head and tail takes its
// head's kind for both ends.)
public enum DOTExporter {

    /// Emits `chart` as a Graphviz `digraph`.
    public static func export(_ chart: Flowchart) -> String {
        // Each node belongs to at most one subgraph (the parser assigns a node to
        // its innermost cluster and removes it from any outer one), so a single
        // owner map is enough to decide root vs. cluster placement.
        var owner: [String: String] = [:]
        for sg in chart.subgraphs {
            for nid in sg.nodeIDs where owner[nid] == nil { owner[nid] = sg.id }
        }
        let byID = Dictionary(chart.subgraphs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let childSet = Set(chart.subgraphs.flatMap { $0.childIDs })

        var out = "digraph G {\n"
        out += "  rankdir=\(rankdir(chart.direction));\n"

        // Root-level nodes, in chart order.
        for node in chart.nodes where owner[node.id] == nil {
            out += "  " + nodeDecl(node) + "\n"
        }
        // Top-level clusters (those not nested under another), recursively.
        for sg in chart.subgraphs where !childSet.contains(sg.id) {
            out += emitCluster(sg, chart: chart, byID: byID, indent: "  ")
        }
        // Edges last, once every node is declared, so re-parsing never mints a
        // node at edge time and node order is preserved for flat charts.
        for edge in chart.edges {
            out += "  " + edgeDecl(edge) + "\n"
        }
        out += "}\n"
        return out
    }

    /// Convenience for the diagram union: emits DOT for a `.flowchart`, `nil` for
    /// any other diagram type (only flowcharts map onto DOT's node/edge model).
    public static func export(_ diagram: MermaidDiagram) -> String? {
        guard case .flowchart(let chart) = diagram else { return nil }
        return export(chart)
    }

    // MARK: - Nodes

    private static func nodeDecl(_ n: Flowchart.Node) -> String {
        var attrs: [String] = []
        // The label defaults to the id on re-parse, so only emit it when it differs.
        if n.label != n.id { attrs.append("label=\(quote(n.label))") }
        attrs.append("shape=\(shapeName(n.shape))")
        return "\(ident(n.id)) [\(attrs.joined(separator: ", "))];"
    }

    /// DOT shape whose `DOTParser` mapping restores the same `NodeShape` — except
    /// the documented lossy cases.
    private static func shapeName(_ shape: Flowchart.NodeShape) -> String {
        switch shape {
        case .rectangle:            return "box"        // box → rectangle
        case .rounded:              return "ellipse"    // ellipse → rounded
        case .stadium:              return "stadium"
        case .diamond:              return "diamond"
        case .circle:               return "circle"
        case .doubleCircle:         return "doublecircle"
        case .cylinder:             return "cylinder"
        case .hexagon:              return "hexagon"
        case .parallelogram:        return "parallelogram"
        case .parallelogramAlt:     return "parallelogram" // lossy → parallelogram
        case .trapezoid:            return "trapezium"
        case .trapezoidAlt:         return "invtrapezium"
        case .subroutine:           return "box"        // lossy → rectangle
        case .asymmetric:           return "box"        // lossy → rectangle
        case .stateStart, .stateEnd: return "circle"    // lossy → circle
        }
    }

    // MARK: - Edges

    private static func edgeDecl(_ e: Flowchart.Edge) -> String {
        var attrs: [String] = []
        if let label = e.label, !label.isEmpty { attrs.append("label=\(quote(label))") }
        let styles = [(e.dashed, "dashed"), (e.thick, "bold"), (e.invisible, "invis")]
            .filter(\.0).map(\.1)
        if styles.count == 1 {
            attrs.append("style=\(styles[0])")
        } else if !styles.isEmpty {
            attrs.append("style=\(quote(styles.joined(separator: ",")))")
        }
        // A circle head is DOT's `dot`; a cross has no DOT arrowhead (lossy).
        if e.head == .circle {
            if e.hasArrow { attrs.append("arrowhead=dot") }
            if e.backArrow { attrs.append("arrowtail=dot") }
        }
        if e.length > 1 { attrs.append("minlen=\(e.length)") }
        // In a `digraph`, an edge with no `dir` is a forward arrow; only the other
        // three arrow configurations need an explicit `dir`.
        switch (e.hasArrow, e.backArrow) {
        case (true, false):  break                       // forward (default)
        case (false, false): attrs.append("dir=none")
        case (false, true):  attrs.append("dir=back")
        case (true, true):   attrs.append("dir=both")
        }
        let suffix = attrs.isEmpty ? "" : " [\(attrs.joined(separator: ", "))]"
        return "\(ident(e.from)) -> \(ident(e.to))\(suffix);"
    }

    // MARK: - Subgraphs

    private static func emitCluster(_ sg: Flowchart.Subgraph, chart: Flowchart,
                                    byID: [String: Flowchart.Subgraph], indent: String) -> String {
        // `DOTParser` only treats a subgraph as a cluster when its id begins with
        // "cluster"; keep an already-cluster-prefixed id verbatim so it round-trips.
        let cid = sg.id.lowercased().hasPrefix("cluster") ? sg.id : "cluster_\(sg.id)"
        let inner = indent + "  "
        var out = "\(indent)subgraph \(ident(cid)) {\n"
        if !sg.label.isEmpty { out += "\(inner)label=\(quote(sg.label));\n" }
        for node in chart.nodes where sg.nodeIDs.contains(node.id) {
            out += inner + nodeDecl(node) + "\n"
        }
        for childID in sg.childIDs {
            if let child = byID[childID] {
                out += emitCluster(child, chart: chart, byID: byID, indent: inner)
            }
        }
        out += "\(indent)}\n"
        return out
    }

    // MARK: - Lexical helpers

    private static func rankdir(_ d: Flowchart.Direction) -> String {
        switch d {
        case .topDown:   return "TB"
        case .leftRight: return "LR"
        case .rightLeft: return "RL"
        case .bottomTop: return "BT"
        }
    }

    /// A DOT id emitted bare when it's a plain identifier and not a reserved word;
    /// otherwise quoted (a quoted id is never matched as a keyword by the lexer).
    private static func ident(_ s: String) -> String {
        isBareID(s) ? s : quote(s)
    }

    private static let reserved: Set<String> = ["node", "edge", "graph", "subgraph", "strict", "digraph"]

    private static func isBareID(_ s: String) -> Bool {
        guard let first = s.first, first == "_" || first.isLetter else { return false }
        guard s.allSatisfy({ $0 == "_" || $0.isLetter || $0.isNumber }) else { return false }
        return !reserved.contains(s.lowercased())
    }

    /// Wraps a string as a DOT double-quoted id/label, escaping `"` and turning a
    /// real newline into `\n` (which `DOTParser.mapLabel` restores to a newline).
    private static func quote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
