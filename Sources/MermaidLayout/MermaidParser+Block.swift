import Foundation

/// A Mermaid `block-beta` diagram: a grid of labelled blocks that flow
/// left-to-right and wrap every `columns` cells into rows, connected by
/// directed edges. Shapes: `id["…"]` rectangle, `id("…")` rounded,
/// `id(("…"))` circle. `space` tokens occupy an empty cell.
public struct BlockDiagram: Hashable, Sendable {
    /// Block outline, from the bracket style around the label.
    public enum Shape: Hashable, Sendable {
        case rectangle      // id["Label"]
        case rounded        // id("Label")
        case circle         // id(("Label"))
        case space          // a blank grid cell
    }

    /// One grid cell. `space` cells carry empty `id`/`label`.
    public struct Block: Hashable, Sendable, Identifiable {
        public let id: String
        /// Display text; falls back to `id` when no label is given.
        public let label: String
        public let shape: Shape
        /// Memberwise initializer.
        public init(id: String, label: String, shape: Shape) {
            self.id = id
            self.label = label
            self.shape = shape
        }
    }

    /// A directed connection between two block ids in `blocks`.
    public struct Edge: Hashable, Sendable {
        public let from: String
        public let to: String
        /// Optional `|label|` text.
        public let label: String?
        /// Creates an edge; `label` defaults to nil.
        public init(from: String, to: String, label: String? = nil) {
            self.from = from
            self.to = to
            self.label = label
        }
    }

    /// Number of columns the grid wraps at (>= 1).
    public let columns: Int
    /// Blocks in flow order (including `space` placeholders).
    public let blocks: [Block]
    public let edges: [Edge]

    /// Memberwise initializer.
    public init(columns: Int, blocks: [Block], edges: [Edge]) {
        self.columns = columns
        self.blocks = blocks
        self.edges = edges
    }
}

extension MermaidParser {

    /// Parses `block-beta` body lines: an optional `columns N`, rows of block
    /// tokens (`a["Label"] b space c`), and `a --> b` edge lines. Without a
    /// `columns` directive the first row's cell count sets the grid width.
    /// Nil when no real (non-space) block parses.
    static func parseBlock(body: [String]) -> BlockDiagram? {
        var columns = 0
        var blocks: [BlockDiagram.Block] = []
        var edges: [BlockDiagram.Edge] = []
        var firstRowCount = 0
        var seenRow = false

        for raw in body {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            if line.hasPrefix("columns ") {
                let value = line.dropFirst("columns ".count).trimmingCharacters(in: .whitespaces)
                columns = Int(value) ?? columns
                continue
            }
            // Skip styling / nested-block scaffolding we don't model.
            if line.hasPrefix("style") || line.hasPrefix("classDef")
                || line.hasPrefix("class ") || line.hasPrefix("block:") || line == "end" {
                continue
            }
            if line.contains("-->") {
                parseBlockEdges(line, into: &edges)
                continue
            }
            // A block-definition row: one or more whitespace-separated tokens.
            var rowCount = 0
            for token in blockTokens(line) {
                guard let block = blockToken(token) else { continue }
                blocks.append(block)
                rowCount += 1
            }
            if rowCount > 0 && !seenRow { firstRowCount = rowCount; seenRow = true }
        }

        let realIDs = Set(blocks.map(\.id)).subtracting([""])
        guard !realIDs.isEmpty else { return nil }

        if columns <= 0 { columns = firstRowCount > 0 ? firstRowCount : max(1, blocks.count) }
        edges = edges.filter { realIDs.contains($0.from) && realIDs.contains($0.to) }

        return BlockDiagram(columns: columns, blocks: blocks, edges: edges)
    }

    /// Splits a block-definition line on top-level whitespace, keeping bracketed
    /// (and quoted) labels intact.
    private static func blockTokens(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        for ch in line {
            if ch == "\"" { inQuote.toggle(); current.append(ch); continue }
            if !inQuote {
                if ch == "[" || ch == "(" || ch == "{" { depth += 1 }
                else if ch == "]" || ch == ")" || ch == "}" { depth = max(0, depth - 1) }
                if ch == " " && depth == 0 {
                    if !current.isEmpty { out.append(current); current = "" }
                    continue
                }
            }
            current.append(ch)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Parses one block token: `id["Label"]`, `id("Label")`, `id(("Label"))`,
    /// a bare `id`, or a `space` placeholder.
    private static func blockToken(_ raw: String) -> BlockDiagram.Block? {
        let token = raw.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return nil }
        if token == "space" || token.hasPrefix("space:") {
            return BlockDiagram.Block(id: "", label: "", shape: .space)
        }
        let idEnd = token.firstIndex(where: { $0 == "[" || $0 == "(" || $0 == "{" }) ?? token.endIndex
        let id = String(token[..<idEnd]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        let rest = String(token[idEnd...])
        if rest.isEmpty {
            return BlockDiagram.Block(id: id, label: id, shape: .rectangle)
        }
        let shape: BlockDiagram.Shape
        if rest.hasPrefix("((") { shape = .circle }
        else if rest.hasPrefix("(") { shape = .rounded }
        else { shape = .rectangle }
        let label = blockLabel(rest)
        return BlockDiagram.Block(id: id, label: label.isEmpty ? id : label, shape: shape)
    }

    /// Strips the (possibly nested) surrounding brackets and quotes from a
    /// block label spec like `(("AST"))` → `AST`.
    private static func blockLabel(_ spec: String) -> String {
        var text = spec.trimmingCharacters(in: .whitespaces)
        let pairs: [(Character, Character)] = [("(", ")"), ("[", "]"), ("{", "}")]
        var changed = true
        while changed {
            changed = false
            if let first = text.first, let last = text.last,
               pairs.contains(where: { $0.0 == first && $0.1 == last }) {
                text = String(text.dropFirst().dropLast())
                changed = true
            }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }

    /// Parses an edge line, supporting chains (`a --> b --> c`) and optional
    /// `|label|` segments (`a -->|yes| b`).
    private static func parseBlockEdges(_ line: String, into edges: inout [BlockDiagram.Edge]) {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return }
        var previous = blockNodeRef(parts[0])
        for segment in parts.dropFirst() {
            var rest = segment.trimmingCharacters(in: .whitespaces)
            var label: String?
            if rest.hasPrefix("|"), let close = rest.dropFirst().firstIndex(of: "|") {
                label = String(rest[rest.index(after: rest.startIndex)..<close])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            let to = blockNodeRef(rest)
            if !previous.isEmpty && !to.isEmpty {
                edges.append(BlockDiagram.Edge(from: previous, to: to,
                                               label: (label?.isEmpty ?? true) ? nil : label))
            }
            previous = to
        }
    }

    /// The leading identifier of an edge endpoint (ignoring any inline label).
    private static func blockNodeRef(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let end = trimmed.firstIndex(where: { !($0.isLetter || $0.isNumber || $0 == "_") }) ?? trimmed.endIndex
        return String(trimmed[..<end])
    }
}
