import Foundation

/// Diagram-level metadata that is ABOUT a diagram rather than IN it: the
/// YAML front-matter `title:` and the `accTitle:` / `accDescr:` accessibility
/// statements. Hosts use it to render a caption and to label the diagram for
/// assistive technologies; none of it is ever layout content, so the parser
/// strips it before any dialect sees the body (an `accTitle:` line must never
/// become a node).
public struct DiagramMetadata: Hashable, Sendable, Codable {
    /// The front-matter `title:` value (a visible caption in mermaid.js).
    public var title: String?
    /// The `accTitle:` value — a short accessible name for the diagram.
    public var accessibilityTitle: String?
    /// The `accDescr:` value — a longer accessible description. Both the
    /// single-line (`accDescr: text`) and block (`accDescr { … }`) forms
    /// land here, block lines joined with spaces.
    public var accessibilityDescription: String?

    /// True when no metadata was present at all.
    public var isEmpty: Bool {
        title == nil && accessibilityTitle == nil && accessibilityDescription == nil
    }

    /// Creates metadata; every field defaults to absent.
    public init(title: String? = nil,
                accessibilityTitle: String? = nil,
                accessibilityDescription: String? = nil) {
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

extension MermaidParser {

    /// The diagram's metadata (front-matter title, accTitle, accDescr) —
    /// cheap to call on its own (a linear line scan, no diagram parse), so
    /// hosts can caption and AX-label even sources they render elsewhere.
    public static func metadata(in source: String) -> DiagramMetadata {
        stripMetadata(from: source).metadata
    }

    /// Splits a source into its metadata and the body the dialect parsers
    /// should see: YAML front-matter removed (its `title:` captured, every
    /// other key — config/layout/look/theme — tolerated and ignored) and
    /// `accTitle:` / `accDescr:` statements removed (values captured).
    /// Untouched lines keep their exact text, indentation included — the
    /// indentation-significant parsers (mindmap, kanban, treemap, …) re-read
    /// this body raw.
    static func stripMetadata(from source: String) -> (body: String, metadata: DiagramMetadata) {
        var metadata = DiagramMetadata()
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        // YAML front-matter: a leading `---` fence closed by another `---`.
        // Only a top-level (unindented) `title:` is read; nested keys like
        // `config:`'s children are indented and fall through harmlessly.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            if let close = lines.dropFirst().firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            }) {
                for line in lines[1..<close] where !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                    if let value = statementValue(line, keyword: "title") {
                        metadata.title = value.isEmpty ? nil : unquoted(value)
                    }
                }
                lines.removeSubrange(0...close)
            }
        }

        // accTitle / accDescr statements anywhere in the body. Later
        // occurrences overwrite earlier ones, matching mermaid.js.
        var kept: [Substring] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let value = statementValue(trimmed, keyword: "accTitle") {
                metadata.accessibilityTitle = value.isEmpty ? nil : value
                index += 1
                continue
            }
            if let value = statementValue(trimmed, keyword: "accDescr") {
                metadata.accessibilityDescription = value.isEmpty ? nil : value
                index += 1
                continue
            }
            if let opener = blockOpenerRemainder(trimmed, keyword: "accDescr") {
                // `accDescr { … }` block: gather until the closing brace.
                var parts: [String] = []
                var rest = opener
                while true {
                    if let brace = rest.firstIndex(of: "}") {
                        parts.append(String(rest[..<brace]).trimmingCharacters(in: .whitespaces))
                        break
                    }
                    parts.append(rest.trimmingCharacters(in: .whitespaces))
                    index += 1
                    guard index < lines.count else { break }   // unclosed: tolerate
                    rest = lines[index].trimmingCharacters(in: .whitespaces)
                }
                let joined = parts.filter { !$0.isEmpty }.joined(separator: " ")
                metadata.accessibilityDescription = joined.isEmpty ? nil : joined
                index += 1
                continue
            }
            kept.append(lines[index])
            index += 1
        }

        return (kept.joined(separator: "\n"), metadata)
    }

    /// `keyword: value` (keyword case-insensitive, mermaid-style) → value,
    /// or nil when the line isn't that statement.
    private static func statementValue(_ line: some StringProtocol, keyword: String) -> String? {
        guard line.count >= keyword.count + 1,
              line.prefix(keyword.count).lowercased() == keyword.lowercased() else { return nil }
        let rest = line.dropFirst(keyword.count).drop(while: { $0 == " " || $0 == "\t" })
        guard rest.first == ":" else { return nil }
        return rest.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    /// `keyword { remainder` → remainder, or nil when the line isn't a
    /// block opener for that keyword.
    private static func blockOpenerRemainder(_ line: String, keyword: String) -> String? {
        guard line.count > keyword.count,
              line.prefix(keyword.count).lowercased() == keyword.lowercased() else { return nil }
        let rest = line.dropFirst(keyword.count).drop(while: { $0 == " " || $0 == "\t" })
        guard rest.first == "{" else { return nil }
        return String(rest.dropFirst())
    }

    /// Strips one matching pair of surrounding quotes from a YAML scalar.
    private static func unquoted(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2
            && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
