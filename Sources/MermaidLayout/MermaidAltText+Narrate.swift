import Foundation

/// A step-by-step *narration* of a diagram — a richer companion to
/// `MermaidAltText.describe`, which gives a one-line summary. Where `describe`
/// says "how big and what it's about", `narrate` walks the structure: it follows
/// a flowchart's edges through its decisions, reads a state machine from its
/// initial state, spells out an ER schema's entities and cardinalities, and
/// replays a sequence message by message.
///
/// Only the types where a walkthrough beats a headcount are narrated
/// (flowchart, state, ER, sequence); every other type falls back to `describe`,
/// so `narrate` is always defined and never worse than the summary. Output is
/// deterministic and length-bounded (large diagrams truncate with a remainder
/// count) so it stays usable as a spoken description.
extension MermaidAltText {

    /// A structural walkthrough of the diagram (falls back to `describe` for
    /// types without a meaningful traversal).
    public static func narrate(_ diagram: MermaidDiagram) -> String {
        switch diagram {
        case .flowchart(let f): return narrateFlowchart(f)
        case .state(let s):     return narrateState(s)
        case .er(let e):        return narrateER(e)
        case .sequence(let s):  return narrateSequence(s)
        default:                return describe(diagram)
        }
    }

    /// A walkthrough led by the author's own accessibility statements (accTitle
    /// / front-matter title, then accDescr), mirroring `describe(_:metadata:)`.
    public static func narrate(_ diagram: MermaidDiagram, metadata: DiagramMetadata) -> String {
        var parts: [String] = []
        if let title = metadata.accessibilityTitle ?? metadata.title { parts.append(terminated(title)) }
        if let descr = metadata.accessibilityDescription { parts.append(terminated(descr)) }
        parts.append(narrate(diagram))
        return parts.joined(separator: " ")
    }

    /// Parses and narrates in one call; nil when the source doesn't parse.
    public static func narrate(source: String) -> String? {
        MermaidParser.parse(source).map {
            narrate($0, metadata: MermaidParser.metadata(in: source))
        }
    }

    // MARK: - Per-type narration

    private static let stepCap = 24

    private static func narrateFlowchart(_ f: Flowchart) -> String {
        let shape = dict(f.nodes.map { ($0.id, $0.shape) })
        let label = dict(f.nodes.map { ($0.id, $0.label) })
        func noun(_ id: String) -> String {
            let n = qt(label[id] ?? id)
            switch shape[id] {
            case .diamond:            return "the decision \(n)"
            case .cylinder:           return "the datastore \(n)"
            case .circle, .stadium:   return "the node \(n)"
            default:                  return "the step \(n)"
            }
        }
        let g = walk("The flowchart", begin: "begins at",
                     ids: f.nodes.map(\.id),
                     edges: f.edges.map { Arc($0.from, $0.to, $0.label) }, noun: noun)
        return g.isEmpty ? describe(.flowchart(f)) : g
    }

    private static func narrateState(_ s: StateDiagram) -> String {
        let label = dict(s.nodes.map { ($0.id, $0.label) })
        let kind = dict(s.nodes.map { ($0.id, $0.kind) })
        func noun(_ id: String) -> String {
            let n = qt(label[id]?.isEmpty == false ? label[id]! : id)
            switch kind[id] {
            case .start:     return "the initial state"
            case .end:       return "the final state"
            case .choice:    return "the choice \(n)"
            case .fork:      return "the fork \(n)"
            case .join:      return "the join \(n)"
            case .composite: return "the composite state \(n)"
            default:         return "the state \(n)"
            }
        }
        let g = walk("The state machine", begin: "starts in",
                     ids: s.nodes.map(\.id),
                     edges: s.edges.map { Arc($0.from, $0.to, $0.label) }, noun: noun)
        return g.isEmpty ? describe(.state(s)) : g
    }

    private static func narrateER(_ e: ERDiagram) -> String {
        guard !e.entities.isEmpty else { return describe(.er(e)) }
        var out: [String] = []
        for entity in e.entities.prefix(stepCap) {
            if entity.attributes.isEmpty {
                out.append("\(qt(entity.name)) has no listed attributes.")
            } else {
                let attrs = entity.attributes.prefix(8).map { "\($0.name) (\($0.type))" }
                let more = entity.attributes.count > 8 ? ", and \(entity.attributes.count - 8) more" : ""
                out.append("\(qt(entity.name)) has \(andList(Array(attrs)))\(more).")
            }
        }
        if e.entities.count > stepCap {
            out.append("…and \(cnt(e.entities.count - stepCap, "more entity", "more entities")).")
        }
        for rel in e.relations.prefix(stepCap) {
            let card = "\(cardWord(rel.fromCard)) to \(cardWord(rel.toCard))"
            let label = rel.label.isEmpty ? "" : " — \(rel.label)"
            let kind = rel.identifying ? "" : " (non-identifying)"
            out.append("\(qt(rel.from)) relates to \(qt(rel.to)): \(card)\(label)\(kind).")
        }
        return out.joined(separator: " ")
    }

    private static func narrateSequence(_ s: SequenceDiagram) -> String {
        guard !s.messages.isEmpty else { return describe(.sequence(s)) }
        let label = dict(s.participants.map { ($0.id, $0.label) })
        func nm(_ id: String) -> String { qt(label[id] ?? id) }
        var out = ["A sequence between \(andList(s.participants.map { qt($0.label) }))."]
        for (i, m) in s.messages.prefix(stepCap).enumerated() {
            let verb: String
            if m.dashed {
                verb = "replies to"
            } else {
                switch m.head {
                case .filled, .both: verb = "calls"
                case .open:          verb = "sends asynchronously to"
                case .cross:         verb = "sends a terminal message to"
                case .none:          verb = "signals"
                }
            }
            let text = m.text.isEmpty ? "" : ": \(qt(m.text))"
            out.append("\(i + 1). \(nm(m.from)) \(verb) \(nm(m.to))\(text).")
        }
        if s.messages.count > stepCap {
            out.append("…and \(cnt(s.messages.count - stepCap, "more message")).")
        }
        return out.joined(separator: " ")
    }

    // MARK: - Shared graph walk (flowchart + state)

    private struct Arc { let from, to: String; let label: String?
        init(_ f: String, _ t: String, _ l: String?) { from = f; to = t; label = l } }

    /// Walks a directed graph: names the entry, then describes each node's
    /// outgoing edges (single "leads to", multiple "branches"), caps the detail,
    /// and names the terminals. Empty for an edgeless graph (caller falls back).
    private static func walk(_ subject: String, begin: String,
                             ids: [String], edges: [Arc], noun: (String) -> String) -> String {
        guard !edges.isEmpty else { return "" }
        let incoming = Set(edges.map(\.to))
        let hasOut = Set(edges.map(\.from))
        var out: [String] = []
        // Prefer a node with no incoming edge; a fully cyclic graph (e.g. a
        // flowchart with a back-edge into its first node) has none, so fall back
        // to the first declared node so there's always an opener.
        if let entry = ids.first(where: { !incoming.contains($0) }) ?? ids.first {
            out.append("\(subject) \(begin) \(noun(entry)).")
        }
        var steps = 0
        for id in ids {
            if steps >= stepCap { break }
            let outs = edges.filter { $0.from == id }
            guard !outs.isEmpty else { continue }
            steps += 1
            if outs.count == 1, let o = outs.first {
                let when = o.label.map { " on \(qt($0))" } ?? ""
                out.append("\(cap(noun(id))) leads to \(noun(o.to))\(when).")
            } else {
                let branches = outs.map { o in o.label.map { "on \(qt($0)) to \(noun(o.to))" } ?? "to \(noun(o.to))" }
                out.append("\(cap(noun(id))) branches \(andList(branches)).")
            }
        }
        let remaining = ids.filter { hasOut.contains($0) }.count - steps
        if remaining > 0 { out.append("…and \(cnt(remaining, "further step")).") }
        let terminals = ids.filter { !hasOut.contains($0) }
        if !terminals.isEmpty, terminals.count <= 4 {
            out.append("\(terminals.count == 1 ? "The end point is" : "End points are") \(andList(terminals.map(noun))).")
        }
        return out.joined(separator: " ")
    }

    // MARK: - Phrasing helpers

    private static func dict<V>(_ pairs: [(String, V)]) -> [String: V] {
        Dictionary(pairs, uniquingKeysWith: { a, _ in a })
    }

    private static func cardWord(_ c: ERDiagram.Cardinality) -> String {
        switch c {
        case .one:        return "one"
        case .zeroOrOne:  return "zero or one"
        case .oneOrMore:  return "one or more"
        case .zeroOrMore: return "zero or more"
        }
    }

    private static func qt(_ s: String) -> String { "“\(s)”" }

    private static func cap(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    private static func cnt(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    private static func andList(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }

    private static func terminated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}
