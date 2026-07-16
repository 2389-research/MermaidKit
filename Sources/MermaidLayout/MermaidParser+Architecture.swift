import Foundation

/// A Mermaid `architecture-beta` diagram: services (icon-labeled boxes)
/// optionally nested in tinted groups, plus junctions (routing dots), wired
/// together by orthogonal edges that name a leave/arrive side (L/R/T/B) on
/// each end. Icons are parsed but only shown as a subtle caption — the visual
/// is the box + label.
public struct ArchitectureDiagram: Hashable, Sendable {

    /// Which border a wire leaves or enters.
    public enum Side: String, Hashable, Sendable {
        case left = "L"
        case right = "R"
        case top = "T"
        case bottom = "B"
    }

    /// A tinted frame that services may sit inside (via `Service.group`).
    public struct Group: Hashable, Sendable, Identifiable {
        public let id: String
        /// Icon name from `(…)`; "" when omitted.
        public let icon: String
        /// Display text from `[…]`; falls back to `id`.
        public let label: String
        /// Memberwise initializer.
        public init(id: String, icon: String, label: String) {
            self.id = id
            self.icon = icon
            self.label = label
        }
    }

    /// A service box, or a junction dot when `isJunction` is set (junctions
    /// carry empty `icon`/`label`).
    public struct Service: Hashable, Sendable, Identifiable {
        public let id: String
        /// Icon name from `(…)`; "" when omitted.
        public let icon: String
        /// Display text from `[…]`; falls back to `id`.
        public let label: String
        /// Owning group id, or nil when the service floats at the top level.
        public let group: String?
        /// Junctions are anonymous routing points drawn as a small dot.
        public let isJunction: Bool
        /// Memberwise initializer.
        public init(id: String, icon: String, label: String, group: String?, isJunction: Bool) {
            self.id = id
            self.icon = icon
            self.label = label
            self.group = group
            self.isJunction = isJunction
        }
    }

    /// An orthogonal wire between two service/junction ids in `services`.
    public struct Edge: Hashable, Sendable {
        public let from: String
        /// Border the wire leaves `from` by. A non-nil side is the author's
        /// declared port (`waf:R -- ...`) and layout honors it as a fixed-side
        /// constraint; nil lets the engine pick the side facing the target.
        public let fromSide: Side?
        public let to: String
        /// Border the wire enters `to` by; same fixed-side semantics.
        public let toSide: Side?
        /// True when the connector carries `<` or `>`.
        public let arrow: Bool
        /// Memberwise initializer.
        public init(from: String, fromSide: Side?, to: String, toSide: Side?, arrow: Bool) {
            self.from = from
            self.fromSide = fromSide
            self.to = to
            self.toSide = toSide
            self.arrow = arrow
        }
    }

    public var groups: [Group]
    /// Services and junctions, in declaration order.
    public var services: [Service]
    public var edges: [Edge]

    /// Memberwise initializer.
    public init(groups: [Group], services: [Service], edges: [Edge]) {
        self.groups = groups
        self.services = services
        self.edges = edges
    }
}

extension MermaidParser {

    /// Parses `architecture-beta` body lines: `group`/`service`/`junction`
    /// declarations (`service db(database)[DB] in api`) plus `a:R --> L:b`
    /// edges. Nil when no service or junction parses.
    static func parseArchitecture(body: [String]) -> ArchitectureDiagram? {
        var groups: [ArchitectureDiagram.Group] = []
        var services: [ArchitectureDiagram.Service] = []
        var edges: [ArchitectureDiagram.Edge] = []

        for line in body {
            if line.hasPrefix("group ") {
                let node = archNode(String(line.dropFirst("group ".count)))
                guard !node.id.isEmpty else { continue }
                groups.append(ArchitectureDiagram.Group(id: node.id, icon: node.icon, label: node.label))
            } else if line.hasPrefix("service ") {
                let node = archNode(String(line.dropFirst("service ".count)))
                guard !node.id.isEmpty else { continue }
                services.append(ArchitectureDiagram.Service(
                    id: node.id, icon: node.icon, label: node.label, group: node.group, isJunction: false))
            } else if line.hasPrefix("junction ") {
                let node = archNode(String(line.dropFirst("junction ".count)))
                guard !node.id.isEmpty else { continue }
                services.append(ArchitectureDiagram.Service(
                    id: node.id, icon: "", label: "", group: node.group, isJunction: true))
            } else if let edge = archEdge(line) {
                edges.append(edge)
            }
        }

        guard !services.isEmpty else { return nil }
        return ArchitectureDiagram(groups: groups, services: services, edges: edges)
    }

    /// Parses `id(icon)[Label] in group` (any of the trailing parts optional).
    private static func archNode(_ rest: String) -> (id: String, icon: String, label: String, group: String?) {
        // id: leading run up to the first '(', '[' or space.
        var id = ""
        var idx = rest.startIndex
        while idx < rest.endIndex, !"([ ".contains(rest[idx]) {
            id.append(rest[idx])
            idx = rest.index(after: idx)
        }

        var icon = ""
        if let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")"), open < close {
            icon = String(rest[rest.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        }

        var label = ""
        if let open = rest.firstIndex(of: "["), let close = rest.firstIndex(of: "]"), open < close {
            label = String(rest[rest.index(after: open)..<close])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        }

        var group: String?
        if let range = rest.range(of: " in ") {
            var g = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let space = g.firstIndex(where: { $0 == " " || $0 == "[" || $0 == "(" }) {
                g = String(g[..<space])
            }
            group = g.isEmpty ? nil : g
        }

        if label.isEmpty { label = id }
        return (id, icon, label, group)
    }

    /// Parses `a:L -- R:b`, `a:L --> R:b`, `a -- b`, etc. The left endpoint is
    /// `id:side`; the right endpoint is `side:id` (Mermaid's convention).
    private static func archEdge(_ line: String) -> ArchitectureDiagram.Edge? {
        guard line.contains("--") else { return nil }
        let arrow = line.contains(">") || line.contains("<")

        let parts = line.components(separatedBy: "--")
        guard parts.count == 2 else { return nil }

        let strip = CharacterSet(charactersIn: " <>")
        let lhs = parts[0].trimmingCharacters(in: strip)
        let rhs = parts[1].trimmingCharacters(in: strip)
        guard !lhs.isEmpty, !rhs.isEmpty else { return nil }

        // Left: id[:side].
        let l = lhs.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        let fromId = l[0]
        let fromSide = l.count > 1 ? ArchitectureDiagram.Side(rawValue: l[1].uppercased()) : nil

        // Right: [side:]id.
        let r = rhs.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        let toId: String
        let toSide: ArchitectureDiagram.Side?
        if r.count > 1 {
            toSide = ArchitectureDiagram.Side(rawValue: r[0].uppercased())
            toId = r[1]
        } else {
            toSide = nil
            toId = r[0]
        }

        guard !fromId.isEmpty, !toId.isEmpty else { return nil }
        return ArchitectureDiagram.Edge(from: fromId, fromSide: fromSide, to: toId, toSide: toSide, arrow: arrow)
    }
}
