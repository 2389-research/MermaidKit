import Foundation

extension MermaidParser {

    /// Parses a full `kanban` source (raw, since indentation is significant):
    /// shallowest-indent lines become columns; deeper lines become cards of
    /// the latest column (`id[Text]@{ ticket: T-1, priority: 'High' }`).
    static func parseKanban(source: String) -> KanbanBoard? {
        // Columns sit at the shallowest indent; cards are indented under them.
        var entries: [(indent: Int, line: String)] = []
        var started = false
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !started {
                if trimmed.hasPrefix("kanban") { started = true }
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("%%") { continue }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            entries.append((indent, trimmed))
        }
        guard let base = entries.map(\.indent).min() else { return nil }

        var columns: [(title: String, cards: [KanbanBoard.Card])] = []
        for entry in entries {
            if entry.indent <= base {
                columns.append((title: kanbanLabel(entry.line), cards: []))
            } else if !columns.isEmpty {
                columns[columns.count - 1].cards.append(kanbanCard(entry.line))
            }
        }

        let built = columns.map { KanbanBoard.Column(title: $0.title, cards: $0.cards) }
        guard !built.isEmpty else { return nil }
        return KanbanBoard(columns: built)
    }

    /// `id[Label]` → `Label`, else the raw token (minus any `@{…}` metadata).
    static func kanbanLabel(_ raw: String) -> String {
        let head = raw.split(separator: "@", maxSplits: 1).first.map(String.init) ?? raw
        if let open = head.firstIndex(of: "["), let close = head.lastIndex(of: "]"), open < close {
            return head[head.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        }
        return head.trimmingCharacters(in: .whitespaces)
    }

    /// A card line: `id[Text]@{ assigned: 'x', ticket: T-1, priority: 'High' }`.
    static func kanbanCard(_ raw: String) -> KanbanBoard.Card {
        let text = kanbanLabel(raw)
        var ticket: String?, priority: String?
        if let at = raw.range(of: "@{"), let close = raw.lastIndex(of: "}") {
            let meta = raw[at.upperBound..<close]
            for pair in meta.split(separator: ",") {
                let kv = pair.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
                }
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "ticket": ticket = kv[1]
                case "priority": priority = kv[1]
                default: break
                }
            }
        }
        return KanbanBoard.Card(text: text, ticket: ticket, priority: priority)
    }
}
