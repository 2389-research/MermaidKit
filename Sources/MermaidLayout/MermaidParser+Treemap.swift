import Foundation

extension MermaidParser {

    /// Parses a full `treemap` source (raw, since indentation is significant):
    /// `"Label": value` leaves and `"Label"` branches, nested by indent.
    /// Internal nodes get the sum of their children; nil when the tree's
    /// total weight is 0.
    static func parseTreemap(source: String) -> Treemap? {
        // (indent, label, value?) for each content line after the header.
        var entries: [(indent: Int, label: String, value: Double?)] = []
        var started = false
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !started {
                if trimmed.hasPrefix("treemap") { started = true }
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("%%") { continue }
            // Styling statements are not tree nodes; without this a
            // `classDef urgent fill:#f00` line became a literal node labeled
            // with the CSS.
            if trimmed.hasPrefix("classDef ") || trimmed.hasPrefix("class ") { continue }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            // `"Label": value` (leaf) or `"Label"` (branch), either optionally
            // suffixed `:::styleClass` — strip the style BEFORE the value
            // split, or lastIndex(of: ":") lands inside `:::` and destroys
            // the value while mangling the label.
            var content = trimmed
            if let style = content.range(of: ":::") {
                content = String(content[..<style.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            var label = content
            var value: Double?
            if let colon = content.lastIndex(of: ":") {
                let after = content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if let v = MermaidParser.finiteDouble(after) {
                    value = v
                    label = String(content[..<colon])
                }
            }
            label = label.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            entries.append((indent, label, value))
        }
        guard let first = entries.first else { return nil }

        // Build the tree with an indentation stack (root never popped).
        final class Node {
            let label: String
            var value: Double
            var children: [Node] = []
            init(_ label: String, _ value: Double) { self.label = label; self.value = value }
        }
        let root = Node(first.label, first.value ?? 0)
        var stack: [(indent: Int, node: Node)] = [(first.indent, root)]
        for entry in entries.dropFirst() {
            while stack.count > 1, let top = stack.last, top.indent >= entry.indent { stack.removeLast() }
            let node = Node(entry.label, entry.value ?? 0)
            stack.last?.node.children.append(node)
            stack.append((entry.indent, node))
        }

        // Internal node value = sum of children (post-order).
        func resolve(_ node: Node) -> Double {
            guard !node.children.isEmpty else { return node.value }
            node.value = node.children.map(resolve).reduce(0, +)
            return node.value
        }
        _ = resolve(root)

        func freeze(_ node: Node) -> TreemapNode {
            TreemapNode(label: node.label, value: node.value, children: node.children.map(freeze))
        }
        guard root.value > 0 else { return nil }
        return Treemap(root: freeze(root))
    }
}
