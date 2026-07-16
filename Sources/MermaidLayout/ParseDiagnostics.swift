import Foundation

/// A human-readable reason `MermaidParser.parse` returned nil (or a note
/// about degraded input) — the answer to "why didn't my diagram render?".
public struct ParseDiagnostic: Hashable, Sendable {
    public enum Severity: String, Hashable, Sendable {
        /// The source cannot produce a diagram.
        case error
        /// The source parses, but something the author wrote was set aside.
        case note
    }

    public let severity: Severity
    /// 1-based line in the original source, or nil when the diagnostic is
    /// about the source as a whole (size caps, empty input).
    public let line: Int?
    public let message: String

    public init(severity: Severity, line: Int?, message: String) {
        self.severity = severity
        self.line = line
        self.message = message
    }
}

extension MermaidParser {

    /// The diagram-type headers `parse` recognizes, in canonical spelling —
    /// the vocabulary "did you mean" suggestions draw from.
    public static let knownHeaders: [String] = [
        "flowchart", "graph", "sequenceDiagram", "pie", "stateDiagram-v2",
        "classDiagram", "erDiagram", "gantt", "timeline", "mindmap",
        "journey", "quadrantChart", "packet-beta", "xychart-beta", "kanban",
        "radar-beta", "treemap-beta", "treeView-beta", "venn-beta", "cynefin-beta", "wardley-beta", "ishikawa-beta", "eventmodeling", "swimlane-beta", "gitGraph", "sankey-beta",
        "requirementDiagram", "zenuml", "C4Context", "architecture-beta",
        "block-beta",
    ]

    /// Explains a source that `parse` rejects (and returns `[]` for one it
    /// accepts). Deliberately cheap — safe to call on every failed parse to
    /// build an error UI or a log line:
    ///
    /// ```swift
    /// guard let diagram = MermaidParser.parse(source) else {
    ///     let reasons = MermaidParser.diagnose(source)
    ///     // "line 1: unknown diagram type 'flowchar' — did you mean 'flowchart'?"
    /// }
    /// ```
    public static func diagnose(_ source: String) -> [ParseDiagnostic] {
        // Whole-source guards, in the same order parse() applies them.
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [.init(severity: .error, line: nil, message: "source is empty")]
        }
        guard source.count <= maxTextSize else {
            return [.init(severity: .error, line: nil,
                          message: "source is \(source.count) characters; the cap is \(maxTextSize) (MermaidParser.maxTextSize)")]
        }

        // Locate the header: first line that isn't blank or a %% comment.
        let rawLines = source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let headerIndex = rawLines.firstIndex(where: { !$0.isEmpty && !$0.hasPrefix("%%") }) else {
            return [.init(severity: .error, line: nil, message: "source contains only comments/blank lines")]
        }
        let header = rawLines[headerIndex]
        let headerLine = headerIndex + 1
        let headerWord = String(header.split(separator: " ").first ?? "")

        if parse(source) != nil { return [] }

        // The header was recognized but the parse still failed: either the
        // flowchart edge cap, or a body the type parser couldn't use.
        if knownHeaders.contains(where: { header.hasPrefix(commonPrefixKey($0)) }) {
            if header.hasPrefix("graph") || header.hasPrefix("flowchart") {
                // Distinguish the edge cap from an empty/broken body.
                let lines = rawLines.filter { !$0.isEmpty && !$0.hasPrefix("%%") }
                if let chart = parseFlowchart(header: header, body: Array(lines.dropFirst())),
                   chart.edges.count > maxEdges {
                    return [.init(severity: .error, line: nil,
                                  message: "flowchart has \(chart.edges.count) edges; the cap is \(maxEdges) (MermaidParser.maxEdges)")]
                }
            }
            return [.init(severity: .error, line: headerLine,
                          message: "recognized '\(headerWord)' but the body produced no usable content — check the type's core syntax")]
        }

        // Unknown header — suggest the nearest known one.
        if let suggestion = nearestHeader(to: headerWord) {
            return [.init(severity: .error, line: headerLine,
                          message: "unknown diagram type '\(headerWord)' — did you mean '\(suggestion)'?")]
        }
        return [.init(severity: .error, line: headerLine,
                      message: "unknown diagram type '\(headerWord)'")]
    }

    /// The prefix `parse` actually matches for a canonical header ("pie"
    /// matches "pie showData", "C4Context" is matched via "C4"…).
    private static func commonPrefixKey(_ canonical: String) -> String {
        if canonical.hasPrefix("C4") { return "C4" }
        if canonical == "stateDiagram-v2" { return "stateDiagram" }
        // block-beta is matched by parse() in FULL (a bare "block" is not a
        // recognized header), unlike the other -beta types which match on
        // their stem.
        if canonical == "block-beta" { return "block-beta" }
        if let dash = canonical.firstIndex(of: "-") { return String(canonical[..<dash]) }
        return canonical
    }

    /// Case-insensitive nearest known header within a small edit distance —
    /// generous enough for typos, strict enough not to "correct" arbitrary text.
    private static func nearestHeader(to word: String) -> String? {
        guard !word.isEmpty else { return nil }
        var best: (header: String, distance: Int)?
        for header in knownHeaders {
            let d = editDistance(word.lowercased(), header.lowercased())
            if best == nil || d < best!.distance { best = (header, d) }
        }
        guard let best, best.distance <= max(2, word.count / 4) else { return nil }
        return best.header
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a.utf8), b = Array(b.utf8)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
