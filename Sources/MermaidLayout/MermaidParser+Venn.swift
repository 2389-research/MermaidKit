import Foundation

/// A Venn diagram (`venn-beta`): up to three overlapping sets with optional
/// proportional sizes and labeled overlap regions.
public struct VennDiagram: Hashable, Sendable {
    /// One set (drawn as a circle).
    public struct SetItem: Hashable, Sendable, Identifiable {
        public let id: String
        public let label: String?
        /// Relative size; circle AREA scales with it. Defaults to 1.
        public let size: Double
        public init(id: String, label: String?, size: Double) {
            self.id = id; self.label = label; self.size = size
        }
    }
    /// A labeled overlap region between two or more sets.
    public struct Overlap: Hashable, Sendable {
        public let ids: [String]
        public let label: String
        public init(ids: [String], label: String) { self.ids = ids; self.label = label }
    }

    public var sets: [SetItem]
    public var overlaps: [Overlap]
    public init(sets: [SetItem], overlaps: [Overlap]) {
        self.sets = sets; self.overlaps = overlaps
    }
}

extension MermaidParser {
    /// Parses `venn-beta` bodies: `set A`, `set A ["Label"]`, `set A : 12`,
    /// and `union A, B ["Label"]` / `intersection A, B ["Label"]` for labeled
    /// overlap regions. `style` lines are styling and skipped.
    static func parseVenn(body: [String]) -> VennDiagram? {
        var sets: [VennDiagram.SetItem] = []
        var overlaps: [VennDiagram.Overlap] = []

        func bracketLabel(_ s: String) -> (rest: String, label: String?) {
            guard let open = s.firstIndex(of: "["), let close = s.lastIndex(of: "]"),
                  open < close else { return (s, nil) }
            var label = String(s[s.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            label = label.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let rest = String(s[..<open]) + String(s[s.index(after: close)...])
            return (rest, label)
        }

        for line in body {
            if line.hasPrefix("style") { continue }
            if line.hasPrefix("set ") {
                var rest = String(line.dropFirst(4))
                let extracted = bracketLabel(rest)
                rest = extracted.rest
                var size = 1.0
                if let colon = rest.firstIndex(of: ":") {
                    let value = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if let finite = finiteDouble(value) {
                        size = max(0.1, min(finite, 1_000))
                    }
                    rest = String(rest[..<colon])
                }
                let id = rest.trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty else { continue }
                sets.append(.init(id: id, label: extracted.label, size: size))
                continue
            }
            if line.hasPrefix("union ") || line.hasPrefix("intersection ") {
                let keyword = line.hasPrefix("union ") ? 6 : 13
                let extracted = bracketLabel(String(line.dropFirst(keyword)))
                guard let label = extracted.label else { continue }
                let ids = extracted.rest.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard ids.count >= 2 else { continue }
                overlaps.append(.init(ids: ids, label: label))
                continue
            }
        }
        guard !sets.isEmpty, sets.count <= 8 else { return nil }
        return VennDiagram(sets: sets, overlaps: overlaps)
    }
}
