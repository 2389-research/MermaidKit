import Foundation

// A Swift front-end for Dippin (https://github.com/2389-research/dippin-lang), the
// 2389-research DSL for authoring AI-pipeline workflows (`.dip`). It targets the
// existing `Flowchart` IR, so a `.dip` source flows through the same layered
// layout → DiagramScene → CoreGraphics/Silica/terminal stack as a Mermaid
// `flowchart` or a Graphviz `.dot` (see `DOTParser`).
//
// Dippin is an indentation-significant language (2-space indent, Python/YAML
// style) with a `workflow Name` header, typed node declarations, and an `edges`
// block. This front-end covers the structural core — the eight node kinds, the
// edge grammar (`->`, `when <cond>`, `label:`, `loop`/`restart: true`, the
// `parallel …-> a,b` / `fan_in …<- a,b` fan sugar) — and maps each node kind to
// a distinct `Flowchart.NodeShape` so a pipeline reads as a shaped graph. Raw
// multiline blocks (`prompt:`, `command:`, `system_prompt:`, `params:`, …) are
// skipped by indentation, so their free text (which can contain `->`, `agent`,
// `#`, arbitrary shell/markdown) never pollutes the parse.
//
// Node kind → shape:
//   agent → rectangle   tool → cylinder      human → stadium
//   conditional → diamond   parallel → hexagon (fork)   fan_in → circle (join)
//   subgraph → subroutine `[[ ]]` (a call into a sub-workflow)
//   manager_loop → rounded
//
// Edge mapping: `when <expr>` → the edge label (the condition, quote-stripped);
// an explicit `label:` wins; a bare `loop` / `restart: true` marks a returning
// edge (the layered engine already routes cycle back-edges — a restart edge
// that has no other caption is labelled "restart" so the loop reads).
//
// Like `MermaidParser`/`DOTParser`, it degrades gracefully: a non-Dippin, empty,
// oversized, or otherwise unparseable source returns `nil` (the caller falls
// back to showing the styled source), and the shared `maxTextSize`/`maxEdges`
// caps keep pathological input from feeding the quadratic layout. It never
// crashes or hangs — every scan makes forward progress.
public enum DippinParser {

    /// Parses a Dippin `workflow` into the `Flowchart` IR; `nil` for a non-Dippin,
    /// empty, oversized, or otherwise unparseable source.
    public static func parse(_ source: String) -> Flowchart? {
        guard source.count <= MermaidParser.maxTextSize else { return nil }
        return DippinParserImpl(source: source).run()
    }
}

// MARK: - Implementation

private final class DippinParserImpl {

    /// The eight typed Dippin node kinds.
    private enum Kind {
        case agent, tool, human, conditional, parallel, fanIn, subgraph, managerLoop
    }

    /// One physical line, its indentation (leading spaces; a tab counts as one),
    /// and its trimmed text (leading/trailing whitespace removed, NOT
    /// comment-stripped — comments are stripped only when a line is interpreted
    /// structurally, so a `#` inside a skipped raw block stays literal).
    private struct Line { let indent: Int; let text: String }

    private let lines: [Line]
    private var pos = 0

    // IR accumulators.
    private var nodes: [String: Flowchart.Node] = [:]
    private var order: [String] = []
    private var edges: [Flowchart.Edge] = []

    // Per-node metadata gathered during the walk, applied at finalize.
    private var kinds: [String: Kind] = [:]
    private var models: [String: String] = [:]
    private var refs: [String: String] = [:]
    private var explicitLabels: [String: String] = [:]
    private var defaultModel: String?

    private var sawWorkflow = false
    private var aborted = false

    // Connections synthesized by `parallel`/`fan_in` fan sugar, so a legacy v1
    // file that also spells the same edge out in its `edges` block doesn't emit
    // a duplicate connector (which would also inflate the `maxEdges` count).
    private var fanEdges: Set<String> = []

    init(source: String) {
        var out: [Line] = []
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = raw
            if line.hasSuffix("\r") { line = line.dropLast() }
            var indent = 0
            for ch in line {
                if ch == " " { indent += 1 } else if ch == "\t" { indent += 1 } else { break }
            }
            out.append(Line(indent: indent,
                            text: String(line).trimmingCharacters(in: .whitespaces)))
        }
        self.lines = out
    }

    // MARK: cursor

    private var cur: Line? { pos < lines.count ? lines[pos] : nil }
    private func advance() { pos += 1 }
    private func isBlank(_ l: Line) -> Bool { l.text.isEmpty || l.text.hasPrefix("#") }
    private func skipBlank() { while let l = cur, isBlank(l) { advance() } }

    /// Consumes every following line that belongs *inside* a block opened at
    /// `parentIndent`: blank/comment lines, and any line indented deeper. Used
    /// both to skip raw multiline field blocks and to swallow unknown sub-blocks.
    private func skipChildBlock(parentIndent: Int) {
        while let l = cur {
            if isBlank(l) { advance(); continue }
            if l.indent > parentIndent { advance(); continue }
            break
        }
    }

    // MARK: entry

    func run() -> Flowchart? {
        skipBlank()
        // Optional leading `dip <int>` format-version line.
        if let l = cur, firstWord(l.text).lowercased() == "dip" { advance(); skipBlank() }

        guard let header = cur, firstWord(header.text).lowercased() == "workflow" else { return nil }
        sawWorkflow = true
        let headerIndent = header.indent
        advance()

        parseBody(headerIndent: headerIndent)
        guard !aborted, sawWorkflow, !nodes.isEmpty,
              edges.count <= MermaidParser.maxEdges else { return nil }

        finalizeLabels()
        return Flowchart(direction: .topDown,
                         nodes: order.compactMap { nodes[$0] },
                         edges: edges)
    }

    // MARK: workflow body

    private func parseBody(headerIndent: Int) {
        while true {
            skipBlank()
            guard let l = cur, l.indent > headerIndent, !aborted else { break }
            let before = pos
            let memberIndent = l.indent
            let words = tokens(l.text)
            let kw = bareKeyword(words.first ?? "")

            switch kw {
            case "start", "exit", "goal", "requires":
                // Metadata. Inline value ignored for v1 (start/exit stay ordinary
                // nodes). If the field opened a multiline block, skip it.
                let empty = fieldValue(l.text).isEmpty
                advance()
                if empty { skipChildBlock(parentIndent: memberIndent) }
            case "defaults":
                advance(); parseDefaults(parentIndent: memberIndent)
            case "vars", "stylesheet":
                advance(); skipChildBlock(parentIndent: memberIndent)
            case "agent", "tool", "human", "conditional", "subgraph", "manager_loop":
                parseNode(kindWord: kw, words: words, memberIndent: memberIndent)
            case "parallel":
                parseParallel(line: l.text, words: words, memberIndent: memberIndent)
            case "fan_in":
                parseFanIn(line: l.text, words: words, memberIndent: memberIndent)
            case "edges":
                advance(); parseEdges(parentIndent: memberIndent)
            default:
                // Unknown workflow-level line: skip it and any block it owns.
                let empty = fieldValue(l.text).isEmpty
                advance()
                if empty { skipChildBlock(parentIndent: memberIndent) }
            }

            if pos == before { advance() }   // forward-progress guarantee
        }
    }

    // MARK: defaults

    private func parseDefaults(parentIndent: Int) {
        while let l = cur, l.indent > parentIndent || isBlank(l) {
            if isBlank(l) { advance(); continue }
            let fieldIndent = l.indent
            let key = bareKeyword(firstWord(l.text))
            let value = fieldValue(l.text)
            advance()
            if key == "model", !value.isEmpty { defaultModel = dequote(value) }
            if value.isEmpty { skipChildBlock(parentIndent: fieldIndent) }
        }
    }

    // MARK: nodes

    private func parseNode(kindWord: String, words: [String], memberIndent: Int) {
        advance()
        guard words.count >= 2 else { skipChildBlock(parentIndent: memberIndent); return }
        let id = words[1]
        declare(id, kind: mapKind(kindWord))
        parseNodeFields(id: id, parentIndent: memberIndent)
    }

    private func parseNodeFields(id: String, parentIndent: Int) {
        while let l = cur, l.indent > parentIndent || isBlank(l) {
            if isBlank(l) { advance(); continue }
            let fieldIndent = l.indent
            let key = bareKeyword(firstWord(l.text))
            let value = fieldValue(l.text)
            advance()
            switch key {
            case "label": if !value.isEmpty { explicitLabels[id] = dequote(value) }
            case "model": if !value.isEmpty { models[id] = dequote(value) }
            case "ref", "subgraph_ref": if !value.isEmpty { refs[id] = dequote(value) }
            default: break
            }
            // An empty value means the field opened a raw multiline block (or a
            // nested params/branch block): skip everything indented beneath it.
            if value.isEmpty { skipChildBlock(parentIndent: fieldIndent) }
        }
    }

    // MARK: parallel / fan_in

    private func parseParallel(line rawLine: String, words: [String], memberIndent: Int) {
        advance()
        guard words.count >= 2 else { skipChildBlock(parentIndent: memberIndent); return }
        let id = words[1]
        declare(id, kind: .parallel)
        // Inline form: `parallel Fan -> A, B, C`. Strip any inline comment first
        // so `parallel Fan # -> A` can't inject a phantom edge from a comment.
        let line = stripInlineComment(rawLine)
        if let arrow = line.range(of: "->") {
            for t in commaList(String(line[arrow.upperBound...])) { addFanEdge(from: id, to: t) }
        }
        // Block form: `branch: <NodeID>` lines are fan-out targets; their nested
        // config fields are skipped.
        while let l = cur, l.indent > memberIndent || isBlank(l) {
            if isBlank(l) { advance(); continue }
            let branchIndent = l.indent
            let key = bareKeyword(firstWord(l.text))
            let value = fieldValue(l.text)
            advance()
            if key == "branch", !value.isEmpty { addFanEdge(from: id, to: dequote(value)) }
            if value.isEmpty || key == "branch" { skipChildBlock(parentIndent: branchIndent) }
            if aborted { return }
        }
    }

    private func parseFanIn(line rawLine: String, words: [String], memberIndent: Int) {
        advance()
        guard words.count >= 2 else { skipChildBlock(parentIndent: memberIndent); return }
        let id = words[1]
        declare(id, kind: .fanIn)
        // Strip inline comments before the `<-` scan (see `parseParallel`).
        let line = stripInlineComment(rawLine)
        if let arrow = line.range(of: "<-") {
            for s in commaList(String(line[arrow.upperBound...])) { addFanEdge(from: s, to: id) }
        }
        // fan_in has no block body in the grammar; defensively skip any.
        skipChildBlock(parentIndent: memberIndent)
    }

    // MARK: edges

    private func parseEdges(parentIndent: Int) {
        while let l = cur, l.indent > parentIndent || isBlank(l), !aborted {
            if isBlank(l) { advance(); continue }
            parseEdgeLine(l.text)
            advance()
        }
    }

    private func parseEdgeLine(_ raw: String) {
        let line = stripInlineComment(raw)
        guard let arrow = line.range(of: "->") else { return }
        let from = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, from.lowercased() != "else" else { return }  // `else ->` default: skip

        let rhs = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
        let dst = firstWord(rhs)
        guard !dst.isEmpty else { return }
        let attrText = String(rhs.dropFirst(dst.count)).trimmingCharacters(in: .whitespaces)

        // A plain, attribute-free redeclaration of a fan-generated edge is a
        // no-op (v1 files may repeat the fan targets in `edges`). An attributed
        // edge (`when …`, `label: …`, …) between the same pair stays distinct.
        if attrText.isEmpty, fanEdges.contains(edgeKey(from, dst)) { return }

        let attr = parseEdgeAttrs(attrText)
        var label = attr.label ?? (attr.when.isEmpty ? nil : cleanCondition(attr.when))
        if label == nil, let o = attr.on { label = "on \(o)" }
        if label == nil, attr.restart { label = "restart" }
        addEdge(from, dst, label: label)
    }

    private struct EdgeAttrs {
        var when = ""
        var label: String?
        var on: String?
        var restart = false
    }

    /// Scans the attribute tail of an edge (`when …`, `label: …`, `loop`,
    /// `restart: …`, `on …`, plus the ignored `weight:`/`choice:`/`override:`).
    /// Quoted values are kept atomic so a `label: "a b"` isn't split.
    private func parseEdgeAttrs(_ s: String) -> EdgeAttrs {
        var out = EdgeAttrs()
        let words = quotedTokens(s)
        var i = 0
        while i < words.count {
            let w = words[i]
            let lw = w.lowercased()
            if lw == "when" {
                var cond: [String] = []
                var j = i + 1
                while j < words.count, !isEdgeAttrKeyword(words[j]) { cond.append(words[j]); j += 1 }
                out.when = cond.joined(separator: " ")
                i = j
            } else if lw == "on" {
                if i + 1 < words.count { out.on = dequote(words[i + 1]); i += 2 } else { i += 1 }
            } else if lw == "loop" {
                out.restart = true; i += 1
            } else if let (key, inlineVal) = splitColon(w) {
                let low = key.lowercased()
                var value = inlineVal
                if value.isEmpty, i + 1 < words.count { value = words[i + 1]; i += 1 }
                switch low {
                case "label": out.label = dequote(value)
                case "restart": out.restart = dequote(value).lowercased() == "true"
                default: break   // weight / choice / override — ignored
                }
                i += 1
            } else {
                i += 1
            }
        }
        return out
    }

    private func isEdgeAttrKeyword(_ w: String) -> Bool {
        let lw = w.lowercased()
        if lw == "on" || lw == "loop" { return true }
        if let (key, _) = splitColon(w) {
            switch key.lowercased() {
            case "weight", "label", "choice", "override", "restart": return true
            default: return false
            }
        }
        return false
    }

    // MARK: node bookkeeping

    /// Declares or upgrades a node. A first reference (from an edge) with a nil
    /// kind mints a plain rectangle placeholder; a later typed declaration
    /// upgrades its shape.
    private func declare(_ id: String, kind: Kind?) {
        if var existing = nodes[id] {
            if let k = kind { kinds[id] = k; existing.shape = shape(for: k); nodes[id] = existing }
        } else {
            let shp = kind.map(shape(for:)) ?? .rectangle
            nodes[id] = Flowchart.Node(id: id, label: id, shape: shp)
            order.append(id)
            if let k = kind { kinds[id] = k }
        }
    }

    private func addEdge(_ from: String, _ to: String, label: String?) {
        guard !aborted else { return }
        declare(from, kind: nil)
        declare(to, kind: nil)
        let clean = label?.trimmingCharacters(in: .whitespaces)
        edges.append(Flowchart.Edge(from: from, to: to,
                                    label: (clean?.isEmpty == true) ? nil : clean,
                                    dashed: false, hasArrow: true))
        if edges.count > MermaidParser.maxEdges { aborted = true }
    }

    /// Adds a fan-sugar edge and records the connection so a later plain,
    /// attribute-free redeclaration of the same pair in `edges` is suppressed.
    private func addFanEdge(from: String, to: String) {
        addEdge(from, to, label: nil)
        fanEdges.insert(edgeKey(from, to))
    }

    private func edgeKey(_ from: String, _ to: String) -> String { from + "\u{1}" + to }

    /// Applies the display label + a small subtitle line (an agent's model, a
    /// subgraph/manager_loop's referenced file) once the whole workflow is read.
    private func finalizeLabels() {
        for id in order {
            guard var n = nodes[id] else { continue }
            let base = explicitLabels[id] ?? id
            var label = base
            switch kinds[id] {
            case .agent:
                if let m = models[id] ?? defaultModel { label = base + "\n" + m }
            case .subgraph, .managerLoop:
                if let r = refs[id] { label = base + "\n" + shortRef(r) }
            default:
                break
            }
            n.label = label
            nodes[id] = n
        }
    }

    // MARK: kind → shape

    private func mapKind(_ s: String) -> Kind? {
        switch s {
        case "agent": return .agent
        case "tool": return .tool
        case "human": return .human
        case "conditional": return .conditional
        case "parallel": return .parallel
        case "fan_in": return .fanIn
        case "subgraph": return .subgraph
        case "manager_loop": return .managerLoop
        default: return nil
        }
    }

    private func shape(for k: Kind) -> Flowchart.NodeShape {
        switch k {
        case .agent: return .rectangle
        case .tool: return .cylinder
        case .human: return .stadium
        case .conditional: return .diamond
        case .parallel: return .hexagon
        case .fanIn: return .circle
        case .subgraph: return .subroutine
        case .managerLoop: return .rounded
        }
    }

    // MARK: lexical helpers

    /// Whitespace-split words of a structural line, with any inline comment
    /// (` # …`, preceded by whitespace) removed first.
    private func tokens(_ s: String) -> [String] {
        stripInlineComment(s).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    private func firstWord(_ s: String) -> String {
        for (i, ch) in s.enumerated() where ch == " " || ch == "\t" {
            return String(s.prefix(i))
        }
        return s
    }

    /// A keyword with any trailing `:` removed (so `start:` and `agent` both
    /// reduce to their bare word), lowercased.
    private func bareKeyword(_ w: String) -> String {
        var s = w
        if s.hasSuffix(":") { s = String(s.dropLast()) }
        return s.lowercased()
    }

    /// The value after the first `:` on a `key: value` line (trimmed). Empty
    /// when the line has no colon or nothing follows it (a multiline block).
    private func fieldValue(_ s: String) -> String {
        let line = stripInlineComment(s)
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Splits a `key:value` token; nil when there's no colon. `value` is the
    /// text after the first colon (possibly empty).
    private func splitColon(_ w: String) -> (String, String)? {
        guard let colon = w.firstIndex(of: ":") else { return nil }
        return (String(w[..<colon]), String(w[w.index(after: colon)...]))
    }

    /// Removes an inline comment: a `#` that is at line start or preceded by
    /// whitespace and not inside a quote. Quote scanning is escape-aware — a
    /// backslash escapes the next char inside a double-quoted region and a
    /// doubled `''` is a literal quote inside a single-quoted one — so a `#`
    /// (or a `\"`) inside a string never ends the string or the line early.
    private func stripInlineComment(_ s: String) -> String {
        let chars = Array(s)
        var quote: Character?
        var prevWasSpace = true
        var out = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if let q = quote {
                out.append(ch)
                if q == "\"", ch == "\\", i + 1 < chars.count {
                    out.append(chars[i + 1]); i += 2; continue     // escaped char
                }
                if ch == q {
                    if q == "'", i + 1 < chars.count, chars[i + 1] == "'" {
                        out.append(chars[i + 1]); i += 2; continue  // '' → literal '
                    }
                    quote = nil
                }
                prevWasSpace = false; i += 1; continue
            }
            if ch == "\"" || ch == "'" { quote = ch; out.append(ch); prevWasSpace = false; i += 1; continue }
            if ch == "#" && prevWasSpace { break }
            out.append(ch)
            prevWasSpace = (ch == " " || ch == "\t")
            i += 1
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Splits on whitespace but keeps a `"…"`/`'…'` region as one token, with
    /// the same escape awareness as `stripInlineComment` so `label: "a \" b"`
    /// stays a single token.
    private func quotedTokens(_ s: String) -> [String] {
        let chars = Array(s)
        var out: [String] = []
        var buf = ""
        var quote: Character?
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if let q = quote {
                buf.append(ch)
                if q == "\"", ch == "\\", i + 1 < chars.count {
                    buf.append(chars[i + 1]); i += 2; continue
                }
                if ch == q {
                    if q == "'", i + 1 < chars.count, chars[i + 1] == "'" {
                        buf.append(chars[i + 1]); i += 2; continue
                    }
                    quote = nil
                }
                i += 1; continue
            }
            if ch == "\"" || ch == "'" { quote = ch; buf.append(ch); i += 1; continue }
            if ch == " " || ch == "\t" {
                if !buf.isEmpty { out.append(buf); buf = "" }
            } else {
                buf.append(ch)
            }
            i += 1
        }
        if !buf.isEmpty { out.append(buf) }
        return out
    }

    /// A comma-separated identifier list (e.g. the RHS of a parallel/fan_in
    /// fan), each entry trimmed and de-commented.
    private func commaList(_ s: String) -> [String] {
        stripInlineComment(s)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Strips one layer of surrounding quotes and decodes the escapes the
    /// scanners preserved: `\"`/`\\` inside `"…"`, and `''` inside `'…'`.
    private func dequote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, let f = t.first, (f == "\"" || f == "'"), t.hasSuffix(String(f)) else { return t }
        let inner = String(t.dropFirst().dropLast())
        if f == "\"" {
            var out = ""
            var esc = false
            for ch in inner {
                if esc { out.append(ch); esc = false; continue }
                if ch == "\\" { esc = true; continue }
                out.append(ch)
            }
            if esc { out.append("\\") }
            return out
        }
        return inner.replacingOccurrences(of: "''", with: "'")
    }

    /// A concise edge label from a `when` condition. A single equality
    /// (`ctx.field == "value"`) collapses to just the value — the branch
    /// outcome, which reads like a decision edge (success / fail / reject) and
    /// keeps the diagram legible. Anything else (inequality, compound
    /// `and`/`or`) falls back to the quote-stripped condition.
    private func cleanCondition(_ s: String) -> String {
        let tokens = quotedTokens(s).map(dequote)
        if tokens.count == 3, tokens[1] == "==", !tokens[2].isEmpty { return tokens[2] }
        return tokens.joined(separator: " ")
    }

    /// The last path component of a subgraph ref (`a/b/quality_loop.dip` →
    /// `quality_loop.dip`).
    private func shortRef(_ ref: String) -> String {
        let parts = ref.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return parts.last.map(String.init) ?? ref
    }
}
