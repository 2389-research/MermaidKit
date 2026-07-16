import Foundation

/// A tree view (`treeView-beta`): an indentation-defined hierarchy of files
/// and folders (trailing `/` marks a directory), with optional inline
/// descriptions after `##`.
public struct TreeViewDiagram: Hashable, Sendable {
    public var roots: [TreeViewNode]
    public init(roots: [TreeViewNode]) { self.roots = roots }
}

/// One row of a tree view.
public struct TreeViewNode: Hashable, Sendable {
    public let label: String
    /// Muted inline description (`## text` in the source), if any.
    public let description: String?
    /// Trailing `/` in the source: rendered bold with a folder glyph.
    public let isDirectory: Bool
    public let children: [TreeViewNode]
    public init(label: String, description: String?, isDirectory: Bool, children: [TreeViewNode]) {
        self.label = label; self.description = description
        self.isDirectory = isDirectory; self.children = children
    }
}

extension MermaidParser {
    /// Parses `treeView-beta` from RAW source (indentation is significant).
    /// Box-drawing prefixes (`│ ├── └──`) are normalized to spaces first, so
    /// pasted `tree`-command output parses as-is. `:::class` and `icon(...)`
    /// decorations are stripped (styling); `## description` is kept.
    static func parseTreeView(source: String) -> TreeViewDiagram? {
        struct Row { let depth: Int; let node: (label: String, desc: String?, dir: Bool) }
        var rows: [Row] = []
        var sawHeader = false

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("%%") { continue }
            if !sawHeader {
                if trimmed.hasPrefix("treeView") { sawHeader = true }
                continue
            }
            // Normalize box-drawing to indentation: every "│   ", "├── ",
            // "└── " (and bare "─") becomes spaces of equal width.
            for ch in ["│", "├", "└", "─"] { line = line.replacingOccurrences(of: ch, with: " ") }
            let content = line.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
                .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }

            var label = content
            var desc: String?
            if let range = label.range(of: "##") {
                desc = String(label[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                label = String(label[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            if let range = label.range(of: ":::") {
                label = String(label[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            // icon(name) prefix or suffix decoration — styling, stripped.
            label = label.replacingOccurrences(of: #"icon\([^)]*\)"#, with: "",
                                               options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let isDir = label.hasSuffix("/")
            if isDir { label = String(label.dropLast()) }
            if label.hasPrefix("\""), label.hasSuffix("\""), label.count >= 2 {
                label = String(label.dropFirst().dropLast())
            }
            guard !label.isEmpty else { continue }
            rows.append(Row(depth: indent, node: (label, desc, isDir)))
        }
        guard !rows.isEmpty else { return nil }

        // Normalize arbitrary indent widths to depth levels: each row's level
        // is the number of distinct smaller indents on its ancestor path.
        var built: [TreeViewNode] = []
        // Recursive descent over the row list using an index cursor.
        var index = 0
        func parseSiblings(minDepth: Int) -> [TreeViewNode] {
            var siblings: [TreeViewNode] = []
            let depth = index < rows.count ? rows[index].depth : 0
            while index < rows.count, rows[index].depth >= minDepth, rows[index].depth <= depth {
                let row = rows[index]
                index += 1
                let children: [TreeViewNode]
                if index < rows.count, rows[index].depth > row.depth {
                    children = parseSiblings(minDepth: rows[index].depth)
                } else {
                    children = []
                }
                siblings.append(TreeViewNode(label: row.node.label, description: row.node.desc,
                                             isDirectory: row.node.dir, children: children))
                if index < rows.count, rows[index].depth < depth { break }
            }
            return siblings
        }
        built = parseSiblings(minDepth: 0)
        guard !built.isEmpty else { return nil }
        return TreeViewDiagram(roots: built)
    }
}
