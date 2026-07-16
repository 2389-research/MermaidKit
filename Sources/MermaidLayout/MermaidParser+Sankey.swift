import Foundation

/// A Mermaid `sankey-beta` diagram: a set of directed, weighted flows between
/// named nodes. Each source line is `source,target,value` (CSV; quoted fields
/// may contain commas). Nodes are recorded in first-appearance order so column
/// placement and tinting stay stable.
public struct SankeyDiagram: Hashable, Sendable {
    /// One weighted flow; `source`/`target` are names in `nodes`, and
    /// `value` is always > 0.
    public struct Link: Hashable, Sendable {
        public let source: String
        public let target: String
        public let value: Double
        /// Memberwise initializer.
        public init(source: String, target: String, value: Double) {
            self.source = source
            self.target = target
            self.value = value
        }
    }

    /// Node names in first-appearance order.
    public var nodes: [String]
    public var links: [Link]

    /// Memberwise initializer.
    public init(nodes: [String], links: [Link]) {
        self.nodes = nodes
        self.links = links
    }
}

extension MermaidParser {

    /// Parses `sankey-beta` body rows: CSV `source,target,value` links
    /// (quoted fields may contain commas; value must be > 0). Nil when no
    /// link parses.
    static func parseSankey(body: [String]) -> SankeyDiagram? {
        var nodes: [String] = []
        var seen: Set<String> = []
        var links: [SankeyDiagram.Link] = []

        func note(_ name: String) {
            if seen.insert(name).inserted { nodes.append(name) }
        }

        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let fields = sankeyCSVFields(trimmed)
            guard fields.count >= 3 else { continue }
            let source = fields[0].trimmingCharacters(in: .whitespaces)
            let target = fields[1].trimmingCharacters(in: .whitespaces)
            let valueText = fields[2].trimmingCharacters(in: .whitespaces)
            guard let value = MermaidParser.finiteDouble(valueText), value > 0,
                  !source.isEmpty, !target.isEmpty else { continue }
            note(source)
            note(target)
            links.append(SankeyDiagram.Link(source: source, target: target, value: value))
        }

        guard !links.isEmpty else { return nil }
        return SankeyDiagram(nodes: nodes, links: links)
    }

    /// Splits one CSV record into fields, honoring double-quoted fields (which
    /// may contain commas) and `""` escapes for a literal quote.
    static func sankeyCSVFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    current.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
            i += 1
        }
        fields.append(current)
        return fields
    }
}
