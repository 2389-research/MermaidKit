import Foundation

/// A Wardley map (`wardley-beta`): components positioned by author-given
/// [visibility, evolution] coordinates on a value-chain × evolution plot,
/// with dependency links and evolution arrows.
public struct WardleyMap: Hashable, Sendable {
    /// Sourcing/strategy decorator after a component, e.g. `(build)`.
    public enum Decorator: String, Hashable, Sendable {
        case build, buy, outsource, market
    }
    /// One mapped component (or user anchor).
    public struct Component: Hashable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        /// 0 (invisible to the user) … 1 (visible). OWM's first coordinate.
        public let visibility: Double
        /// 0 (genesis) … 1 (commodity). OWM's second coordinate.
        public let evolution: Double
        /// True for `anchor` lines (the user/need at the top of the chain).
        public let isAnchor: Bool
        /// `(inertia)` — resistance to evolution, drawn as a bar.
        public let inertia: Bool
        public let decorator: Decorator?
        public init(name: String, visibility: Double, evolution: Double,
                    isAnchor: Bool, inertia: Bool, decorator: Decorator?) {
            self.name = name; self.visibility = visibility; self.evolution = evolution
            self.isAnchor = isAnchor; self.inertia = inertia; self.decorator = decorator
        }
    }
    /// A dependency link (`A -> B`); `+>` marks a flow (drawn emphasized).
    public struct Link: Hashable, Sendable {
        public let from: String
        public let to: String
        public let isFlow: Bool
        public init(from: String, to: String, isFlow: Bool) {
            self.from = from; self.to = to; self.isFlow = isFlow
        }
    }
    /// `evolve Name 0.8` — a dashed arrow to the component's future position.
    public struct Evolve: Hashable, Sendable {
        public let name: String
        public let target: Double
        public init(name: String, target: Double) { self.name = name; self.target = target }
    }
    /// Free-floating annotation at a map position.
    public struct Note: Hashable, Sendable {
        public let text: String
        public let visibility: Double
        public let evolution: Double
        public init(text: String, visibility: Double, evolution: Double) {
            self.text = text; self.visibility = visibility; self.evolution = evolution
        }
    }

    public var title: String?
    public var components: [Component]
    public var links: [Link]
    public var evolves: [Evolve]
    public var notes: [Note]
    public init(title: String?, components: [Component], links: [Link],
                evolves: [Evolve], notes: [Note]) {
        self.title = title; self.components = components
        self.links = links; self.evolves = evolves; self.notes = notes
    }
}

extension MermaidParser {
    /// Parses `wardley-beta` bodies: `title`, `component Name [v, e]` with
    /// optional `(inertia)`/`(build|buy|outsource|market)` decorators,
    /// `anchor Name [v, e]`, `evolve Name 0.8`, `note "text" [v, e]`, and
    /// links `A -> B` / `A +> B` (flow). Coordinates are clamped to 0...1.
    static func parseWardley(body: [String]) -> WardleyMap? {
        var title: String?
        var components: [WardleyMap.Component] = []
        var links: [WardleyMap.Link] = []
        var evolves: [WardleyMap.Evolve] = []
        var notes: [WardleyMap.Note] = []

        func coordinates(_ s: String) -> (rest: String, v: Double, e: Double)? {
            guard let open = s.lastIndex(of: "["), let close = s.lastIndex(of: "]"),
                  open < close else { return nil }
            let inner = s[s.index(after: open)..<close].split(separator: ",")
            guard inner.count == 2,
                  let v = finiteDouble(inner[0].trimmingCharacters(in: .whitespaces)),
                  let e = finiteDouble(inner[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return (String(s[..<open]).trimmingCharacters(in: .whitespaces),
                    min(max(v, 0), 1), min(max(e, 0), 1))
        }

        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("component ") || line.hasPrefix("anchor ") {
                let isAnchor = line.hasPrefix("anchor ")
                var rest = String(line.dropFirst(isAnchor ? 7 : 10))
                var inertia = false
                var decorator: WardleyMap.Decorator?
                if rest.contains("(inertia)") {
                    inertia = true
                    rest = rest.replacingOccurrences(of: "(inertia)", with: "")
                }
                for kind in ["build", "buy", "outsource", "market"] where rest.contains("(\(kind))") {
                    decorator = WardleyMap.Decorator(rawValue: kind)
                    rest = rest.replacingOccurrences(of: "(\(kind))", with: "")
                }
                guard let parsed = coordinates(rest), !parsed.rest.isEmpty else { continue }
                components.append(.init(name: parsed.rest, visibility: parsed.v, evolution: parsed.e,
                                        isAnchor: isAnchor, inertia: inertia, decorator: decorator))
                continue
            }
            if line.hasPrefix("evolve ") {
                let rest = String(line.dropFirst(7))
                guard let lastSpace = rest.range(of: " ", options: .backwards),
                      let target = finiteDouble(rest[lastSpace.upperBound...].trimmingCharacters(in: .whitespaces)) else { continue }
                let name = String(rest[..<lastSpace.lowerBound]).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                evolves.append(.init(name: name, target: min(max(target, 0), 1)))
                continue
            }
            if line.hasPrefix("note ") {
                guard let parsed = coordinates(String(line.dropFirst(5))) else { continue }
                let text = parsed.rest.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard !text.isEmpty else { continue }
                notes.append(.init(text: text, visibility: parsed.v, evolution: parsed.e))
                continue
            }
            // Links: A -> B (dependency) or A +> B (flow); tolerate '-->'.
            for (token, isFlow) in [("+>", true), ("-->", false), ("->", false)] {
                if let range = line.range(of: token) {
                    let from = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let to = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !from.isEmpty, !to.isEmpty {
                        links.append(.init(from: from, to: to, isFlow: isFlow))
                    }
                    break
                }
            }
        }
        guard !components.isEmpty else { return nil }
        return WardleyMap(title: title, components: components, links: links,
                          evolves: evolves, notes: notes)
    }
}
