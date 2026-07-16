import Foundation

/// A Cynefin framework diagram (`cynefin-beta`): the five decision domains
/// with per-domain items and optional transitions between domains.
public struct CynefinDiagram: Hashable, Sendable {
    /// The five Cynefin domains. Raw values are the source keywords.
    public enum Domain: String, Hashable, Sendable, CaseIterable {
        case complex, complicated, clear, chaotic, confusion
        /// The canonical decision heuristic shown under the domain name.
        public var heuristic: String {
            switch self {
            case .complex: return "probe · sense · respond"
            case .complicated: return "sense · analyze · respond"
            case .clear: return "sense · categorize · respond"
            case .chaotic: return "act · sense · respond"
            case .confusion: return "break it down"
            }
        }
    }

    /// A movement between domains, e.g. `chaotic --> clear : "stabilize"`.
    public struct Transition: Hashable, Sendable {
        public let from: Domain
        public let to: Domain
        public let label: String?
        public init(from: Domain, to: Domain, label: String?) {
            self.from = from; self.to = to; self.label = label
        }
    }

    public var title: String?
    /// Items per domain, in source order.
    public var items: [Domain: [String]]
    public var transitions: [Transition]

    public init(title: String?, items: [Domain: [String]], transitions: [Transition]) {
        self.title = title; self.items = items; self.transitions = transitions
    }
}

extension MermaidParser {
    /// Parses `cynefin-beta` bodies: `title …`, a domain keyword opening a
    /// block, quoted strings as that domain's items, and
    /// `domain --> domain : "label"` transitions. Unknown lines are skipped.
    static func parseCynefin(body: [String]) -> CynefinDiagram? {
        var title: String?
        var items: [CynefinDiagram.Domain: [String]] = [:]
        var transitions: [CynefinDiagram.Transition] = []
        var current: CynefinDiagram.Domain?

        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            // Transition: complex --> complicated : "label"
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                guard parts.count == 2,
                      let from = CynefinDiagram.Domain(rawValue: parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
                let rest = parts[1]
                let toToken: String
                var label: String?
                if let colon = rest.firstIndex(of: ":") {
                    toToken = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
                    label = rest[rest.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                } else {
                    toToken = rest.trimmingCharacters(in: .whitespaces)
                }
                guard let to = CynefinDiagram.Domain(rawValue: toToken) else { continue }
                transitions.append(.init(from: from, to: to, label: label))
                continue
            }
            // Domain block opener.
            if let domain = CynefinDiagram.Domain(rawValue: line) {
                current = domain
                if items[domain] == nil { items[domain] = [] }
                continue
            }
            // Quoted item inside the current domain.
            if line.hasPrefix("\""), line.hasSuffix("\""), line.count >= 2, let domain = current {
                items[domain, default: []].append(String(line.dropFirst().dropLast()))
                continue
            }
        }
        guard !items.isEmpty || !transitions.isEmpty else { return nil }
        return CynefinDiagram(title: title, items: items, transitions: transitions)
    }
}
