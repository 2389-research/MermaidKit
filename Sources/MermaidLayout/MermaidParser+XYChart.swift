import Foundation

extension MermaidParser {

    /// Parses `xychart-beta` body lines: `title`, `x-axis "Title" [a, b, c]`
    /// (title and bracket each optional), `y-axis "Title" lo --> hi`, and
    /// `bar [..]` / `line [..]` series. Categories default to 1-based indices
    /// when the x-axis lists none. Nil when no series parses.
    static func parseXYChart(body: [String]) -> XYChart? {
        var title: String?
        var xAxisTitle: String?
        var categories: [String] = []
        var yAxisTitle: String?
        var yMin: Double?, yMax: Double?
        var series: [XYChart.Series] = []

        /// Bracketed, comma-separated tokens: `["a", "b"]` or `[1, 2, 3]`.
        func bracketTokens(_ text: String) -> [String]? {
            guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close
            else { return nil }
            return text[text.index(after: open)..<close]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
        }

        /// A numeric value, tolerating a `value:"label"` point annotation.
        func number(_ token: String) -> Double? {
            let head = token.split(separator: ":").first.map(String.init) ?? token
            return MermaidParser.finiteDouble(head.trimmingCharacters(in: .whitespaces))
        }

        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            } else if line.hasPrefix("x-axis ") {
                let spec = String(line.dropFirst("x-axis ".count))
                if let tokens = bracketTokens(spec) {
                    categories = tokens
                    // An optional quoted title precedes the bracket.
                    if let open = spec.firstIndex(of: "[") {
                        let lead = spec[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                        if !lead.isEmpty { xAxisTitle = lead }
                    }
                } else {
                    xAxisTitle = spec.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                }
            } else if line.hasPrefix("y-axis ") {
                var spec = String(line.dropFirst("y-axis ".count))
                if let range = spec.range(of: "-->") {
                    // `… lo --> hi`: the numbers on either side of the arrow.
                    let before = spec[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                    let after = spec[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    yMax = MermaidParser.finiteDouble(after.split(separator: " ").last.map(String.init) ?? after)
                    if let lo = before.split(separator: " ").last.map(String.init), let v = MermaidParser.finiteDouble(lo) {
                        yMin = v
                        spec = String(before.dropLast(lo.count))
                    }
                }
                let leadTitle = spec.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !leadTitle.isEmpty { yAxisTitle = leadTitle }
            } else if line.hasPrefix("bar ") || line.hasPrefix("line ") {
                let kind: XYChart.SeriesKind = line.hasPrefix("bar ") ? .bar : .line
                guard let tokens = bracketTokens(line) else { continue }
                let values = tokens.compactMap(number)
                guard !values.isEmpty else { continue }
                series.append(XYChart.Series(kind: kind, values: values))
            }
        }

        guard !series.isEmpty else { return nil }
        // Categories default to 1-based indices when the x-axis is unlabelled.
        if categories.isEmpty {
            let count = series.map(\.values.count).max() ?? 0
            categories = (1...max(count, 1)).map(String.init)
        }
        return XYChart(title: title, xAxisTitle: xAxisTitle, categories: categories,
                       yAxisTitle: yAxisTitle, yMin: yMin, yMax: yMax, series: series)
    }
}
