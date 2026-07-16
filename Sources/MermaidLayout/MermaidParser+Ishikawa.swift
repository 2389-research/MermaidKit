import Foundation

/// An Ishikawa / fishbone diagram (`ishikawa-beta`): a problem statement
/// (the fish head) with indentation-nested causes (ribs) and sub-causes
/// (twigs). Upstream's syntax is explicitly minimal and "may evolve"; this
/// parses the documented core: first line = problem, indented lines = causes.
public struct IshikawaDiagram: Hashable, Sendable {
    /// A cause with optional sub-causes (one level of twigs is drawn;
    /// deeper nesting flattens into the twig list).
    public struct Cause: Hashable, Sendable {
        public let label: String
        public let subCauses: [String]
        public init(label: String, subCauses: [String]) {
            self.label = label; self.subCauses = subCauses
        }
    }
    public var problem: String
    public var causes: [Cause]
    public init(problem: String, causes: [Cause]) {
        self.problem = problem; self.causes = causes
    }
}

extension MermaidParser {
    /// Parses `ishikawa-beta` from RAW source (indentation is significant):
    /// the first content line is the problem, depth-1 lines are major causes,
    /// anything deeper is a twig on its nearest major cause.
    static func parseIshikawa(source: String) -> IshikawaDiagram? {
        var problem: String?
        var causes: [IshikawaDiagram.Cause] = []
        var currentLabel: String?
        var currentSubs: [String] = []
        var baseIndent: Int?
        var sawHeader = false

        func flush() {
            if let label = currentLabel {
                causes.append(.init(label: label, subCauses: currentSubs))
            }
            currentLabel = nil; currentSubs = []
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("%%") { continue }
            if !sawHeader {
                if trimmed.hasPrefix("ishikawa") { sawHeader = true }
                continue
            }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
                .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            var label = trimmed
            if label.hasPrefix("\""), label.hasSuffix("\""), label.count >= 2 {
                label = String(label.dropFirst().dropLast())
            }
            if problem == nil {
                problem = label
                continue
            }
            if baseIndent == nil { baseIndent = indent }
            if indent <= (baseIndent ?? 0) {
                flush()
                currentLabel = label
            } else if currentLabel != nil {
                currentSubs.append(label)
            }
        }
        flush()
        guard let head = problem, !causes.isEmpty else { return nil }
        return IshikawaDiagram(problem: head, causes: causes)
    }
}
