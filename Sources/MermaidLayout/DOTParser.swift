import Foundation

// A Swift front-end for Graphviz DOT (https://graphviz.org/doc/info/lang.html)
// that targets the existing `Flowchart` IR, so a `.dot`/`.gv` source flows
// through the same layered layout → DiagramScene → CoreGraphics/Silica/terminal
// stack as a Mermaid `flowchart`. A real tokenizer + recursive-descent parser
// covers the structural core of the grammar; a useful subset of attributes is
// mapped onto the model and the rest is ignored (never fatal). Like
// `MermaidParser`, it degrades gracefully — malformed, huge, or hostile input
// returns `nil` (the caller falls back to showing the styled source), and the
// same `maxTextSize`/`maxEdges` caps keep pathological input from feeding the
// quadratic layout.
public enum DOTParser {

    /// Parses a DOT `graph`/`digraph` into the `Flowchart` IR; `nil` for a
    /// non-DOT, empty, oversized, or otherwise unparseable source.
    public static func parse(_ source: String) -> Flowchart? {
        guard source.count <= MermaidParser.maxTextSize else { return nil }
        let tokens = DOTLexer.tokenize(Array(source))
        guard !tokens.isEmpty else { return nil }
        return DOTParserImpl(tokens: tokens).run()
    }
}

// MARK: - Tokens

private struct DOTToken {
    enum Kind: Equatable {
        case id            // identifier / quoted string / numeral / HTML label
        case lbrace, rbrace, lbrack, rbrack
        case semi, comma, eq, colon, plus
        case edge          // `->` or `--` (arrowhead decided by graph type)
    }
    let kind: Kind
    let text: String   // meaningful only for `.id`
    let quoted: Bool   // a quoted/HTML id is NEVER matched as a keyword
}

// MARK: - Lexer

private enum DOTLexer {

    static func tokenize(_ s: [Character]) -> [DOTToken] {
        var toks: [DOTToken] = []
        var i = 0
        let n = s.count
        func peek(_ k: Int = 1) -> Character? { i + k < n ? s[i + k] : nil }

        // Guard: `s.count <= maxTextSize`, and every branch advances `i`, so
        // this is a bounded O(n) scan.
        while i < n {
            let c = s[i]

            // Whitespace.
            if c == " " || c == "\t" || c == "\r" || c == "\n" { i += 1; continue }

            // Comments: `//` line, `/* … */` block, `#` preprocessor line.
            if c == "/" && peek() == "/" {
                i += 2
                while i < n && s[i] != "\n" { i += 1 }
                continue
            }
            if c == "/" && peek() == "*" {
                i += 2
                while i < n && !(s[i] == "*" && i + 1 < n && s[i + 1] == "/") { i += 1 }
                if i < n { i += 2 }
                continue
            }
            if c == "#" {
                i += 1
                while i < n && s[i] != "\n" { i += 1 }
                continue
            }

            // Single-char punctuation.
            switch c {
            case "{": toks.append(.init(kind: .lbrace, text: "", quoted: false)); i += 1; continue
            case "}": toks.append(.init(kind: .rbrace, text: "", quoted: false)); i += 1; continue
            case "[": toks.append(.init(kind: .lbrack, text: "", quoted: false)); i += 1; continue
            case "]": toks.append(.init(kind: .rbrack, text: "", quoted: false)); i += 1; continue
            case ";": toks.append(.init(kind: .semi, text: "", quoted: false)); i += 1; continue
            case ",": toks.append(.init(kind: .comma, text: "", quoted: false)); i += 1; continue
            case "=": toks.append(.init(kind: .eq, text: "", quoted: false)); i += 1; continue
            case ":": toks.append(.init(kind: .colon, text: "", quoted: false)); i += 1; continue
            case "+": toks.append(.init(kind: .plus, text: "", quoted: false)); i += 1; continue
            default: break
            }

            // Edge operators and negative numerals both begin with `-`.
            if c == "-" {
                if peek() == ">" || peek() == "-" {
                    toks.append(.init(kind: .edge, text: "", quoted: false)); i += 2; continue
                }
                if let d = peek(), d.isNumber || d == "." {
                    let (text, next) = scanNumeral(s, i)
                    toks.append(.init(kind: .id, text: text, quoted: false)); i = next; continue
                }
                i += 1; continue   // stray `-` → skip
            }

            // Quoted string (with `\"` escape + `\<newline>` continuation).
            if c == "\"" {
                let (text, next) = scanQuoted(s, i)
                toks.append(.init(kind: .id, text: text, quoted: true)); i = next; continue
            }

            // HTML string `<…>` — degraded to its plain text.
            if c == "<" {
                let (text, next) = scanHTML(s, i)
                toks.append(.init(kind: .id, text: text, quoted: true)); i = next; continue
            }

            // Plain identifier.
            if isIDStart(c) {
                var j = i + 1
                while j < n && isIDBody(s[j]) { j += 1 }
                toks.append(.init(kind: .id, text: String(s[i..<j]), quoted: false)); i = j; continue
            }

            // Numeral.
            if c.isNumber || c == "." {
                let (text, next) = scanNumeral(s, i)
                toks.append(.init(kind: .id, text: text, quoted: false)); i = next; continue
            }

            // Anything else (stray `>`, `&`, control chars…) — skip.
            i += 1
        }
        return toks
    }

    private static func isIDStart(_ c: Character) -> Bool {
        c == "_" || c.isLetter || (c.unicodeScalars.first.map { $0.value >= 128 } ?? false)
    }
    private static func isIDBody(_ c: Character) -> Bool {
        isIDStart(c) || c.isNumber
    }

    private static func scanNumeral(_ s: [Character], _ start: Int) -> (String, Int) {
        let n = s.count
        var i = start
        if i < n && s[i] == "-" { i += 1 }
        while i < n && s[i].isNumber { i += 1 }
        if i < n && s[i] == "." { i += 1; while i < n && s[i].isNumber { i += 1 } }
        return (String(s[start..<i]), i)
    }

    /// Scans a `"…"` string. `\"` becomes `"`, a backslash-newline is a line
    /// continuation (both dropped); every other backslash is passed through so
    /// label mapping can later see `\n`/`\l`/`\r`.
    private static func scanQuoted(_ s: [Character], _ start: Int) -> (String, Int) {
        let n = s.count
        var i = start + 1
        var out = ""
        while i < n {
            let c = s[i]
            if c == "\\" {
                if i + 1 < n && s[i + 1] == "\"" { out.append("\""); i += 2; continue }
                if i + 1 < n && s[i + 1] == "\n" { i += 2; continue }         // continuation
                if i + 1 < n && s[i + 1] == "\r" {                            // CRLF continuation
                    i += (i + 2 < n && s[i + 2] == "\n") ? 3 : 2; continue
                }
                out.append(c); i += 1; continue
            }
            if c == "\"" { i += 1; break }
            out.append(c); i += 1
        }
        return (out, i)
    }

    /// Scans a balanced `<…>` HTML string and strips it to plain text: tags are
    /// removed, `<br/>` becomes a newline, runs of whitespace collapse.
    private static func scanHTML(_ s: [Character], _ start: Int) -> (String, Int) {
        let n = s.count
        var i = start
        var depth = 0
        var raw = ""
        while i < n {
            let c = s[i]
            if c == "<" { depth += 1; raw.append(c); i += 1; continue }
            if c == ">" {
                depth -= 1; raw.append(c); i += 1
                if depth == 0 { break }
                continue
            }
            raw.append(c); i += 1
        }
        return (stripTags(raw), i)
    }

    private static func stripTags(_ html: String) -> String {
        var out = ""
        var inTag = false
        var tag = ""
        for ch in html {
            if ch == "<" { inTag = true; tag = ""; continue }
            if ch == ">" {
                inTag = false
                if tag.lowercased().hasPrefix("br") { out.append("\n") }
                continue
            }
            if inTag { tag.append(ch); continue }
            out.append(ch)
        }
        // Collapse whitespace runs; trim.
        let collapsed = out.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Parser

private final class DOTParserImpl {

    private let tokens: [DOTToken]
    private var pos = 0

    private var directed = true

    private var nodes: [String: Flowchart.Node] = [:]
    private var order: [String] = []
    private var edges: [Flowchart.Edge] = []

    private var subgraphs: [String: Flowchart.Subgraph] = [:]
    private var subgraphOrder: [String] = []
    private var clusterStack: [String] = []
    // Every entered `{ … }` subgraph scope, cluster or not (anonymous / non-
    // cluster scopes push `nil`). `clusterStack` only holds clusters, so it
    // can't tell "root" from "inside an anonymous subgraph"; this can.
    private var scopeStack: [String?] = []
    private var membership: [String: String] = [:]
    private var membershipDepth: [String: Int] = [:]

    private var graphRankdir: String?
    private var anonCount = 0
    private var aborted = false

    private let maxDepth = 400

    /// Per-scope default attributes (`node[…]`/`edge[…]`), inherited by nested
    /// subgraphs. Passed by value so a subgraph's defaults never leak outward.
    private struct Defaults {
        var node: [String: String] = [:]
        var edge: [String: String] = [:]
    }

    init(tokens: [DOTToken]) { self.tokens = tokens }

    // MARK: token cursor

    private var cur: DOTToken? { pos < tokens.count ? tokens[pos] : nil }
    private func peekTok(_ k: Int) -> DOTToken? { pos + k < tokens.count ? tokens[pos + k] : nil }
    private func advance() { pos += 1 }
    private func isKeyword(_ t: DOTToken?, _ word: String) -> Bool {
        guard let t = t, t.kind == .id, !t.quoted else { return false }
        return t.text.lowercased() == word
    }
    private func isAttrKeyword(_ text: String) -> Bool {
        let l = text.lowercased()
        return l == "node" || l == "edge" || l == "graph"
    }

    // MARK: entry

    func run() -> Flowchart? {
        if isKeyword(cur, "strict") { advance() }
        guard let g = cur, g.kind == .id, !g.quoted else { return nil }
        let head = g.text.lowercased()
        guard head == "graph" || head == "digraph" else { return nil }
        directed = (head == "digraph")
        advance()

        // Optional graph name (any id that isn't the opening brace).
        if let t = cur, t.kind == .id { _ = consumeID() }

        guard let b = cur, b.kind == .lbrace else { return nil }
        advance()

        _ = parseStmtList(Defaults(), depth: 0)

        // A well-formed graph closes its outer brace and has nothing after it;
        // `digraph { A` (EOF first) and `digraph { A } garbage` (trailing
        // tokens) both violate the malformed-input contract.
        guard !aborted, cur?.kind == .rbrace else { return nil }
        advance()
        guard cur == nil else { return nil }

        // Edge endpoints that named a subgraph id minted a phantom node; drop
        // those and scrub any membership list they slipped into (mirrors
        // MermaidParser). Fan-out means this is rare, but stay defensive.
        let subgraphIDs = Set(subgraphOrder)
        for id in subgraphIDs {
            nodes.removeValue(forKey: id)
            order.removeAll { $0 == id }
        }
        for key in subgraphs.keys {
            subgraphs[key]!.nodeIDs.removeAll { subgraphIDs.contains($0) }
        }

        guard !nodes.isEmpty, edges.count <= MermaidParser.maxEdges else { return nil }
        return Flowchart(
            direction: directionFrom(graphRankdir),
            nodes: order.compactMap { nodes[$0] },
            edges: edges,
            subgraphs: subgraphOrder.compactMap { subgraphs[$0] }
        )
    }

    // MARK: statement list

    /// Parses statements up to the matching `}` / end of input, returning the
    /// node ids referenced at this level (including nested) so an enclosing
    /// subgraph can use them as edge fan-out endpoints. Default-attr statements
    /// mutate a local copy of `inherited`, applying to *subsequent* statements.
    private func parseStmtList(_ inherited: Defaults, depth: Int) -> [String] {
        if depth > maxDepth { aborted = true; return [] }
        var defs = inherited
        var members: [String] = []
        while let t = cur, t.kind != .rbrace, !aborted {
            if t.kind == .semi || t.kind == .comma { advance(); continue }
            let before = pos
            parseStmt(&defs, &members, depth: depth)
            if pos == before { advance() }   // guarantee forward progress
        }
        // Endpoints of a `{ … } -> x` fan are a node *set*: dedupe (order-
        // preserving) so `{ a a } -> b` doesn't emit the edge twice.
        var seen = Set<String>()
        return members.filter { seen.insert($0).inserted }
    }

    private func parseStmt(_ defs: inout Defaults, _ members: inout [String], depth: Int) {
        guard let t = cur else { return }

        // subgraph … / anonymous { … } — possibly the LHS of an edge chain.
        if isKeyword(t, "subgraph") || t.kind == .lbrace {
            let pts = parseSubgraph(&defs, depth: depth)
            members.append(contentsOf: pts)
            if let e = cur, e.kind == .edge {
                parseEdgeRHS(from: pts, defs, &members, depth: depth)
            }
            return
        }

        // attr_stmt: (node|edge|graph) [ … ] default attributes.
        if t.kind == .id, !t.quoted, isAttrKeyword(t.text),
           let nx = peekTok(1), nx.kind == .lbrack {
            let which = t.text.lowercased()
            advance()
            let attrs = parseAttrList()
            applyDefault(which, attrs, &defs)
            return
        }

        guard t.kind == .id else { advance(); return }
        guard let id = consumeNodeID() else { return }

        // `ID = ID` graph attribute (rankdir=LR, label="…", …).
        if let e = cur, e.kind == .eq {
            advance()
            let value = consumeID()?.0 ?? ""
            applyGraphAttr(key: id, value: value)
            return
        }

        // edge_stmt.
        if let e = cur, e.kind == .edge {
            noteNodeRef(id, [:], defs)
            members.append(id)
            parseEdgeRHS(from: [id], defs, &members, depth: depth)
            return
        }

        // node_stmt with an optional attr_list.
        var attrs: [String: String] = [:]
        if let b = cur, b.kind == .lbrack { attrs = parseAttrList() }
        noteNodeRef(id, attrs, defs)
        members.append(id)
    }

    // MARK: subgraphs

    private func parseSubgraph(_ defs: inout Defaults, depth: Int) -> [String] {
        var subID: String?
        if isKeyword(cur, "subgraph") {
            advance()
            if let t = cur, t.kind == .id { subID = consumeID()?.0 }
        }
        guard let b = cur, b.kind == .lbrace else {
            // `subgraph X` without a body — degrade to a plain node reference.
            if let s = subID { noteNodeRef(s, [:], defs); return [s] }
            return []
        }
        advance()   // '{'

        var clusterID: String?
        if let sid = subID, sid.lowercased().hasPrefix("cluster") {
            let regID = registerCluster(sid)
            if let parent = clusterStack.last, subgraphs[parent] != nil {
                subgraphs[parent]!.childIDs.append(regID)
            }
            clusterStack.append(regID)
            clusterID = regID
        }
        scopeStack.append(clusterID)   // nil for anonymous / non-cluster scopes

        let members = parseStmtList(defs, depth: depth + 1)

        scopeStack.removeLast()
        if clusterID != nil, !clusterStack.isEmpty { clusterStack.removeLast() }
        if let e = cur, e.kind == .rbrace { advance() }
        return members
    }

    private func registerCluster(_ preferred: String) -> String {
        var id = preferred
        if subgraphs[id] != nil { id = "\u{a7}sub\(anonCount)"; anonCount += 1 }
        subgraphs[id] = Flowchart.Subgraph(id: id, label: "")
        subgraphOrder.append(id)
        return id
    }

    // MARK: edges

    private func parseEdgeRHS(from: [String], _ defs: Defaults,
                             _ members: inout [String], depth: Int) {
        var chain: [[String]] = [from]
        while let e = cur, e.kind == .edge, !aborted {
            advance()   // edge op
            guard let t = cur else { break }
            var pts: [String]
            if isKeyword(t, "subgraph") || t.kind == .lbrace {
                var d = defs
                pts = parseSubgraph(&d, depth: depth)
            } else if t.kind == .id {
                guard let nid = consumeNodeID() else { break }
                noteNodeRef(nid, [:], defs)
                pts = [nid]
            } else { break }
            chain.append(pts)
            members.append(contentsOf: pts)
        }

        var attrs: [String: String] = [:]
        if let b = cur, b.kind == .lbrack { attrs = parseAttrList() }
        let merged = defs.edge.merging(attrs) { _, new in new }

        guard chain.count >= 2 else { return }
        for i in 0..<(chain.count - 1) {
            for a in chain[i] {
                for b in chain[i + 1] {
                    addEdge(a, b, merged)
                    if aborted { return }
                }
            }
        }
    }

    private func addEdge(_ from: String, _ to: String, _ attrs: [String: String]) {
        guard !aborted else { return }
        let label = attrs["label"].map(mapLabel)
        let style = (attrs["style"] ?? "").lowercased()
        let dashed = style.contains("dashed") || style.contains("dotted")
        let dir = (attrs["dir"] ?? (directed ? "forward" : "none")).lowercased()
        // All four DOT directions: `back` points at the tail, `both` at both.
        let hasArrow: Bool
        let backArrow: Bool
        switch dir {
        case "none": hasArrow = false; backArrow = false
        case "back": hasArrow = false; backArrow = true
        case "both": hasArrow = true;  backArrow = true
        default:     hasArrow = true;  backArrow = false   // forward / unknown
        }
        edges.append(Flowchart.Edge(from: from, to: to,
                                    label: (label?.isEmpty == true) ? nil : label,
                                    dashed: dashed, hasArrow: hasArrow, backArrow: backArrow))
        if edges.count > MermaidParser.maxEdges { aborted = true }
    }

    // MARK: attributes

    /// Parses one or more `[ … ]` groups into a merged dict (later keys win).
    private func parseAttrList() -> [String: String] {
        var out: [String: String] = [:]
        while let b = cur, b.kind == .lbrack, !aborted {
            advance()   // '['
            while let t = cur, t.kind != .rbrack {
                if t.kind == .semi || t.kind == .comma { advance(); continue }
                guard t.kind == .id else { advance(); continue }
                let before = pos
                let key = consumeID()?.0 ?? ""
                var value = "true"
                if let e = cur, e.kind == .eq {
                    advance()
                    value = consumeID()?.0 ?? ""
                }
                if !key.isEmpty { out[key.lowercased()] = value }
                if pos == before { advance() }   // progress guard
            }
            if let r = cur, r.kind == .rbrack { advance() }
        }
        return out
    }

    private func applyDefault(_ which: String, _ attrs: [String: String], _ defs: inout Defaults) {
        switch which {
        case "node": defs.node.merge(attrs) { _, new in new }
        case "edge": defs.edge.merge(attrs) { _, new in new }
        case "graph":
            if let rd = attrs["rankdir"] { setRankdirForCurrentScope(rd) }
            if let lbl = attrs["label"] { setLabelForCurrentScope(lbl) }
        default: break
        }
    }

    private func applyGraphAttr(key: String, value: String) {
        switch key.lowercased() {
        case "rankdir": setRankdirForCurrentScope(value)
        case "label":   setLabelForCurrentScope(value)
        default: break
        }
    }

    /// `rankdir` only steers the whole chart when set at root scope; inside any
    /// subgraph (cluster or not) it's local and ignored by this front-end.
    private func setRankdirForCurrentScope(_ value: String) {
        if scopeStack.isEmpty { graphRankdir = value }
    }

    /// `label` names the *immediate* enclosing scope, and only when that scope
    /// is a cluster — a nested scope must not overwrite an outer cluster's label.
    private func setLabelForCurrentScope(_ value: String) {
        if let immediate = scopeStack.last, let cluster = immediate, subgraphs[cluster] != nil {
            subgraphs[cluster]!.label = mapLabel(value)
        }
    }

    // MARK: node bookkeeping

    private func noteNodeRef(_ id: String, _ attrs: [String: String], _ defs: Defaults) {
        let merged = defs.node.merging(attrs) { _, new in new }
        let rawLabel = attrs["label"] ?? defs.node["label"]
        let label = rawLabel.map(mapLabel) ?? id
        let shape = shapeFrom(merged["shape"])

        if var existing = nodes[id] {
            // Only an *explicit* later attr updates an established node; a
            // default in scope (`node[label=…]`) must not overwrite it.
            if let explicit = attrs["label"] { existing.label = mapLabel(explicit) }
            if let explicit = attrs["shape"] { existing.shape = shapeFrom(explicit) }
            nodes[id] = existing
        } else {
            nodes[id] = Flowchart.Node(id: id, label: label, shape: shape)
            order.append(id)
        }
        // A node belongs to the innermost cluster it textually appears in: a
        // reference deeper than the current claim (e.g. `x` in an outer cluster
        // then again in a nested one) reassigns it to the inner cluster.
        if let top = clusterStack.last, subgraphs[top] != nil {
            let depth = clusterStack.count
            if let prev = membership[id] {
                if depth > (membershipDepth[id] ?? 0), prev != top {
                    subgraphs[prev]?.nodeIDs.removeAll { $0 == id }
                    membership[id] = top
                    membershipDepth[id] = depth
                    subgraphs[top]!.nodeIDs.append(id)
                }
            } else {
                membership[id] = top
                membershipDepth[id] = depth
                subgraphs[top]!.nodeIDs.append(id)
            }
        }
    }

    // MARK: id helpers

    /// Reads one id token, folding in `+` string concatenation (`"a" + "b"`).
    private func consumeID() -> (String, Bool)? {
        guard let t = cur, t.kind == .id else { return nil }
        advance()
        var text = t.text
        while let p = cur, p.kind == .plus, let nx = peekTok(1), nx.kind == .id {
            advance(); advance()
            text += nx.text
        }
        return (text, t.quoted)
    }

    /// Reads a `node_id` = `ID [ ':' port [ ':' compass ] ]`, discarding ports.
    private func consumeNodeID() -> String? {
        guard let (text, _) = consumeID() else { return nil }
        var count = 0
        while let c = cur, c.kind == .colon, count < 2 {
            advance()
            guard let p = cur, p.kind == .id else { break }
            advance()
            count += 1
        }
        return text
    }

    // MARK: mapping

    /// Maps DOT line-break escapes (`\n` centered, `\l` left, `\r` right) to
    /// newlines in a label.
    private func mapLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "\\l", with: "\n")
         .replacingOccurrences(of: "\\r", with: "\n")
         .replacingOccurrences(of: "\\n", with: "\n")
    }

    private func shapeFrom(_ raw: String?) -> Flowchart.NodeShape {
        switch (raw ?? "").lowercased() {
        case "diamond", "mdiamond":                     return .diamond
        case "circle", "doublecircle", "point":         return .circle
        case "ellipse", "oval":                         return .rounded
        case "cylinder":                                return .cylinder
        case "stadium":                                 return .stadium
        case "hexagon":                                 return .hexagon
        // box/rect/square/record/Mrecord/plaintext/none and unknowns → rect.
        default:                                        return .rectangle
        }
    }

    private func directionFrom(_ raw: String?) -> Flowchart.Direction {
        switch (raw ?? "TB").uppercased() {
        case "LR": return .leftRight
        case "RL": return .rightLeft
        case "BT": return .bottomTop
        default:   return .topDown   // TB / TD / anything else
        }
    }
}
