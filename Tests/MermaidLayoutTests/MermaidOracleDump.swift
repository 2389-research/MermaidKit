import XCTest
@testable import MermaidLayout

/// The MermaidKit half of the mermaid.js differential test (tools/mermaid-oracle):
/// parses every source in `ORACLE_CORPUS` and writes one JSON line per source
/// to `ORACLE_OUT`, in the comparison schema `normalize.mjs` documents — what a
/// reader sees. Skipped unless both variables are set; the tool's
/// `scripts/check-mermaid-oracle.sh` drives it.
final class MermaidOracleDump: XCTestCase {
    func testDumpForTheMermaidOracle() throws {
        let env = ProcessInfo.processInfo.environment
        guard let corpusPath = env["ORACLE_CORPUS"], let outPath = env["ORACLE_OUT"] else {
            throw XCTSkip("set ORACLE_CORPUS and ORACLE_OUT (scripts/check-mermaid-oracle.sh)")
        }
        let sources = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: corpusPath)))
        var lines: [String] = []
        for source in sources {
            lines.append(String(decoding: try JSONSerialization.data(withJSONObject: Self.reduce(source),
                                                                    options: [.sortedKeys]), as: UTF8.self))
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
    }

    /// Visible label text: `<br>` as a line break, whitespace collapsed per line.
    static func visible(_ text: String) -> String {
        let broken = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        return broken.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func reduce(_ source: String) -> [String: Any] {
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return ["ok": false] }
        let direction = chart.direction.rawValue == "TD" ? "TB" : chart.direction.rawValue
        let vertices: [[String: Any]] = chart.nodes.map {
            ["id": $0.id, "label": visible($0.label), "shape": "\($0.shape)"]
        }
        let edges: [[String: Any]] = chart.edges.map { e in
            let stroke = e.invisible ? "invisible" : e.thick ? "thick" : e.dashed ? "dotted" : "normal"
            let arrows = e.hasArrow && e.backArrow ? "both" : e.hasArrow ? "end" : e.backArrow ? "start" : "none"
            return ["from": e.from, "to": e.to, "label": visible(e.label ?? ""), "stroke": stroke,
                    "head": arrows == "none" ? "arrow" : "\(e.head)", "arrows": arrows, "length": e.length]
        }
        // Subgraphs as normalize.mjs's `anonymized` leaves them: synthesized ids
        // (`§sub0`) as `§anon<k>` by number, members sorted, sorted by id.
        let synthesized = chart.subgraphs.map(\.id).filter { $0.hasPrefix("\u{a7}sub") }
            .sorted { Int($0.dropFirst(4)) ?? 0 < Int($1.dropFirst(4)) ?? 0 }
        func name(_ id: String) -> String {
            synthesized.firstIndex(of: id).map { "\u{a7}anon\($0)" } ?? id
        }
        let subgraphs: [[String: Any]] = chart.subgraphs.map { s in
            let direction: Any = s.direction.map { $0.rawValue == "TD" ? "TB" : $0.rawValue } ?? NSNull()
            return ["id": name(s.id), "title": visible(s.label), "members": (s.nodeIDs + s.childIDs).map(name).sorted(),
                    "direction": direction]
        }.sorted { ($0["id"] as! String) < ($1["id"] as! String) }
        return ["ok": true, "direction": direction, "vertices": vertices, "edges": edges, "subgraphs": subgraphs]
    }
}
