import Foundation

/// A swimlane diagram (`swimlane-beta`): flowchart semantics with every node
/// assigned to a lane; edges may cross lanes.
public struct SwimlaneDiagram: Hashable, Sendable {
    public struct Lane: Hashable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public init(id: String, label: String) { self.id = id; self.label = label }
    }
    /// A node inside a lane (a subset of flowchart shapes).
    public struct Node: Hashable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let shape: Flowchart.NodeShape
        public let laneID: String
        public init(id: String, label: String, shape: Flowchart.NodeShape, laneID: String) {
            self.id = id; self.label = label; self.shape = shape; self.laneID = laneID
        }
    }
    public struct Edge: Hashable, Sendable {
        public let from: String
        public let to: String
        public let label: String?
        public let dashed: Bool
        public init(from: String, to: String, label: String?, dashed: Bool) {
            self.from = from; self.to = to; self.label = label; self.dashed = dashed
        }
    }
    public var direction: Flowchart.Direction
    public var lanes: [Lane]
    public var nodes: [Node]
    public var edges: [Edge]
    public init(direction: Flowchart.Direction, lanes: [Lane], nodes: [Node], edges: [Edge]) {
        self.direction = direction; self.lanes = lanes; self.nodes = nodes; self.edges = edges
    }
}

extension MermaidParser {
    /// Parses `swimlane-beta [direction]`: lanes are `subgraph id[Label] …
    /// end` blocks, nodes/edges reuse the flowchart micro-syntax (node
    /// declarations bind to the enclosing lane; edges may appear anywhere).
    static func parseSwimlane(header: String, body: [String]) -> SwimlaneDiagram? {
        let headerTokens = header.split(separator: " ").map(String.init)
        var direction: Flowchart.Direction = .leftRight
        if headerTokens.count > 1 {
            let token = headerTokens[1] == "TB" ? "TD" : headerTokens[1]
            direction = Flowchart.Direction(rawValue: token) ?? .leftRight
        }

        var lanes: [SwimlaneDiagram.Lane] = []
        var nodes: [SwimlaneDiagram.Node] = []
        var edges: [SwimlaneDiagram.Edge] = []
        var currentLane: String?

        func ensureNode(_ token: String, laneID: String?) -> String? {
            guard let parsed = parseNodeToken(Substring(token)) else { return nil }
            if !nodes.contains(where: { $0.id == parsed.id }) {
                nodes.append(.init(id: parsed.id, label: parsed.label, shape: parsed.shape,
                                   laneID: laneID ?? lanes.first?.id ?? "lane0"))
            } else if let index = nodes.firstIndex(where: { $0.id == parsed.id }),
                      parsed.label != parsed.id {
                // Redeclaration with a richer label upgrades the stored one.
                let existing = nodes[index]
                nodes[index] = .init(id: existing.id, label: parsed.label,
                                     shape: parsed.shape, laneID: existing.laneID)
            }
            return parsed.id
        }

        for line in body {
            if line.hasPrefix("subgraph ") {
                let rest = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                var id = rest
                var label = rest
                if let open = rest.firstIndex(of: "["), let close = rest.lastIndex(of: "]"), open < close {
                    id = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
                    label = String(rest[rest.index(after: open)..<close])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                guard !id.isEmpty else { continue }
                lanes.append(.init(id: id, label: label))
                currentLane = id
                continue
            }
            if line == "end" { currentLane = nil; continue }
            if line.hasPrefix("accTitle") || line.hasPrefix("accDescr") { continue }

            // Edge lines: find the first connector token.
            var handled = false
            for (token, dashed) in [("-.->", true), ("==>", false), ("-->", false), ("---", false)] {
                guard let range = line.range(of: token) else { continue }
                var fromToken = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var rest = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                var label: String?
                if rest.hasPrefix("|"), let close = rest.dropFirst().firstIndex(of: "|") {
                    label = String(rest[rest.index(after: rest.startIndex)..<close])
                    rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                }
                // Chained edges (A --> B --> C) split on remaining connectors.
                var toToken = rest
                if let next = ["-.->", "==>", "-->", "---"].compactMap({ rest.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
                    toToken = String(rest[..<next.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                fromToken = fromToken.trimmingCharacters(in: .whitespaces)
                guard let from = ensureNode(fromToken, laneID: currentLane),
                      let to = ensureNode(toToken, laneID: currentLane) else { break }
                edges.append(.init(from: from, to: to, label: label, dashed: dashed))
                handled = true
                break
            }
            if handled { continue }
            // Bare node declaration inside a lane.
            if currentLane != nil {
                _ = ensureNode(line, laneID: currentLane)
            }
        }
        guard !lanes.isEmpty, !nodes.isEmpty else { return nil }
        return SwimlaneDiagram(direction: direction, lanes: lanes, nodes: nodes, edges: edges)
    }
}
