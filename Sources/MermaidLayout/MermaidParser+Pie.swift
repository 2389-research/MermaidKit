import Foundation

extension MermaidParser {

    /// Parses a `pie` chart: an optional `title` (on the header line or the
    /// next), then `"Label" : 42.5` slice rows (non-negative values).
    /// Nil when no valid slice parses.
    static func parsePie(header: String, body: [String]) -> PieChart? {
        var title: String?
        var lines = body

        // Title can ride the header line or the next line.
        if let range = header.range(of: "title ") {
            title = String(header[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let first = lines.first, first.hasPrefix("title ") {
            title = String(first.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
        }

        var slices: [PieChart.Slice] = []
        for line in lines {
            // "Label" : 42.5
            guard let colon = line.lastIndex(of: ":") else { continue }
            let rawLabel = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let label = rawLabel.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let valueText = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, let value = MermaidParser.finiteDouble(valueText), value >= 0 else { continue }
            slices.append(PieChart.Slice(label: label, value: value))
        }
        guard !slices.isEmpty else { return nil }
        return PieChart(title: title, slices: slices)
    }
}
