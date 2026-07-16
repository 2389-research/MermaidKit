import Foundation

extension MermaidParser {

    /// Parses a full `mindmap` source (raw, since indentation is significant)
    /// into a single-rooted tree; shape wrappers (`((…))`, `[…]`) reduce to
    /// label text and `::icon`/`:::class` decorations are skipped.
    static func parseMindmap(source: String) -> Mindmap? {
        // Collect (indentation, label) for every content line after the header,
        // preserving leading whitespace (which trimmed `lines` has discarded).
        var started = false
        var entries: [(indent: Int, label: String)] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !started {
                if trimmed.hasPrefix("mindmap") { started = true }
                continue
            }
            // Skip blanks, comments, and `::icon()` / `:::class` decorations.
            if trimmed.isEmpty || trimmed.hasPrefix("%%") || trimmed.hasPrefix(":") { continue }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
                .reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            entries.append((indent, mindmapLabel(trimmed)))
        }
        guard let first = entries.first else { return nil }

        // Build the tree by indentation. A mutable class gives the needed
        // reference semantics while wiring parents to children; convert to the
        // immutable value tree at the end. The root (index 0) is never popped,
        // so a stray under-indented line attaches to it rather than orphaning.
        final class MutableNode {
            let label: String
            var children: [MutableNode] = []
            init(_ label: String) { self.label = label }
        }
        let root = MutableNode(first.label)
        var stack: [(indent: Int, node: MutableNode)] = [(first.indent, root)]
        for entry in entries.dropFirst() {
            while stack.count > 1, let top = stack.last, top.indent >= entry.indent {
                stack.removeLast()
            }
            let node = MutableNode(entry.label)
            stack.last?.node.children.append(node)
            stack.append((entry.indent, node))
        }

        func freeze(_ node: MutableNode) -> MindmapNode {
            MindmapNode(label: node.label, children: node.children.map(freeze))
        }
        return Mindmap(root: freeze(root))
    }

    /// Strips a Mermaid mindmap node's shape wrapper to its label text:
    /// `root((Markdown))` → `Markdown`, `id[Square]` → `Square`. Plain text is
    /// returned unchanged. Reversed cloud/bang shapes degrade to best effort.
    static func mindmapLabel(_ raw: String) -> String {
        let openers: Set<Character> = ["(", "[", "{"]
        let closers: Set<Character> = [")", "]", "}"]
        guard let open = raw.firstIndex(where: { openers.contains($0) }),
              let close = raw.lastIndex(where: { closers.contains($0) }),
              close > open else {
            return raw
        }
        let inner = raw[raw.index(after: open)..<close]
            .trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}"))
            .trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? raw : inner
    }
}
