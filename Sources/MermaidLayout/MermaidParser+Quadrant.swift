import Foundation

extension MermaidParser {

    /// Parses `quadrantChart` body lines: `title`, `x-axis Low --> High`,
    /// `y-axis Low --> High`, `quadrant-1…4 Name`, and `"Label": [x, y]`
    /// points (coordinates clamped to 0…1). Nil when no point parses.
    static func parseQuadrant(body: [String]) -> QuadrantChart? {
        var title: String?
        var xLeft: String?, xRight: String?, yBottom: String?, yTop: String?
        var quadrants: [String?] = [nil, nil, nil, nil]
        var points: [QuadrantChart.Point] = []

        // Splits `Low --> High` into (Low, High); a label with no arrow is the
        // low/left/bottom end alone.
        func axisEnds(_ spec: String) -> (String?, String?) {
            if let range = spec.range(of: "-->") {
                let lo = spec[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let hi = spec[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return (lo.isEmpty ? nil : lo, hi.isEmpty ? nil : hi)
            }
            let single = spec.trimmingCharacters(in: .whitespaces)
            return (single.isEmpty ? nil : single, nil)
        }

        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("x-axis ") {
                (xLeft, xRight) = axisEnds(String(line.dropFirst("x-axis ".count)))
            } else if line.hasPrefix("y-axis ") {
                (yBottom, yTop) = axisEnds(String(line.dropFirst("y-axis ".count)))
            } else if line.hasPrefix("quadrant-"),
                      let digit = line.dropFirst("quadrant-".count).first,
                      let index = Int(String(digit)), (1...4).contains(index) {
                let name = line.drop { $0 != " " }.trimmingCharacters(in: .whitespaces)
                quadrants[index - 1] = name.isEmpty ? nil : name
            } else if let point = parseQuadrantPoint(line) {
                points.append(point)
            }
        }

        guard !points.isEmpty else { return nil }
        return QuadrantChart(title: title, xAxisLeft: xLeft, xAxisRight: xRight,
                             yAxisBottom: yBottom, yAxisTop: yTop, quadrants: quadrants, points: points)
    }

    /// Parses `"Label": [x, y]` (x, y in 0…1). Returns nil if malformed.
    private static func parseQuadrantPoint(_ line: String) -> QuadrantChart.Point? {
        guard let colon = line.firstIndex(of: ":"),
              let open = line.firstIndex(of: "["),
              let close = line.lastIndex(of: "]"), open < close else { return nil }
        let label = line[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        guard !label.isEmpty else { return nil }
        let coords = line[line.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard coords.count == 2, let x = MermaidParser.finiteDouble(coords[0]), let y = MermaidParser.finiteDouble(coords[1]) else { return nil }
        return QuadrantChart.Point(label: label, x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}
