import Foundation

extension MermaidParser {

    /// Parses `radar` body lines: `axis k1["Label"], k2`, curves
    /// (`curve name["Label"]{k1: 10, k2: 20}`), and `max` / `min` / `ticks`
    /// directives (defaults 100 / 0 / 5). Curve values are re-aligned to axis
    /// order, with unscored axes falling to `min`. Nil without at least one
    /// axis and one curve.
    static func parseRadar(body: [String]) -> RadarChart? {
        var title: String?
        var axes: [RadarChart.Axis] = []
        var rawCurves: [(label: String, byKey: [String: Double], positional: [Double])] = []
        var maxValue = 100.0, minValue = 0.0, ticks = 5

        /// `KEY["Label"]` or bare `KEY` → (key, label).
        func axisDef(_ token: String) -> RadarChart.Axis? {
            let t = token.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if let open = t.firstIndex(of: "["), let close = t.lastIndex(of: "]"), open < close {
                let key = String(t[..<open]).trimmingCharacters(in: .whitespaces)
                let label = t[t.index(after: open)..<close].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                return RadarChart.Axis(key: key, label: label.isEmpty ? key : label)
            }
            return RadarChart.Axis(key: t, label: t)
        }

        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("axis ") {
                // APPEND: multiple axis lines are the documented way to wrap
                // long axis lists; assignment silently kept only the last.
                axes += splitTopLevel(String(line.dropFirst("axis ".count)), separator: ",").compactMap(axisDef)
            } else if line.hasPrefix("curve ") {
                let spec = String(line.dropFirst("curve ".count))
                let label: String
                if let open = spec.firstIndex(of: "["), let close = spec.firstIndex(of: "]"), open < close {
                    label = String(spec[spec.index(after: open)..<close]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                } else {
                    label = String(spec.prefix { $0 != "{" }).trimmingCharacters(in: .whitespaces)
                }
                var byKey: [String: Double] = [:]
                var positional: [Double] = []
                if let open = spec.firstIndex(of: "{"), let close = spec.lastIndex(of: "}"), open < close {
                    for pair in spec[spec.index(after: open)..<close].split(separator: ",") {
                        let kv = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        if kv.count == 2, let v = MermaidParser.finiteDouble(kv[1]) {
                            byKey[kv[0]] = v
                        } else if kv.count == 1, let v = MermaidParser.finiteDouble(kv[0]) {
                            // Positional form `curve a{1, 2, 3}` — the docs'
                            // primary syntax; values map to axes in order.
                            // The k:v-only parser zeroed every doc-copied
                            // chart flat to the minimum.
                            positional.append(v)
                        }
                    }
                }
                rawCurves.append((label, byKey, positional))
            } else if line.hasPrefix("max ") {
                maxValue = MermaidParser.finiteDouble(line.dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? maxValue
            } else if line.hasPrefix("min ") {
                minValue = MermaidParser.finiteDouble(line.dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? minValue
            } else if line.hasPrefix("ticks ") {
                // Clamped: layout draws one ring polygon per tick, so an
                // unbounded count is a render-time hang.
                if let t = Int(line.dropFirst(6).trimmingCharacters(in: .whitespaces)) {
                    ticks = min(max(t, 1), 100)
                }
            }
        }

        guard !axes.isEmpty, !rawCurves.isEmpty else { return nil }
        // Align each curve's values to the axis order; positional values map
        // to axes by index (short lists pad with the minimum).
        let curves = rawCurves.map { raw in
            RadarChart.Curve(label: raw.label, values: axes.enumerated().map { index, axis in
                raw.byKey[axis.key]
                    ?? (index < raw.positional.count ? raw.positional[index] : minValue)
            })
        }
        // Data above the default ceiling would clip; grow the ceiling to the
        // data (mermaid does the same when max is unset).
        let dataMax = curves.flatMap(\.values).max() ?? maxValue
        let ceiling = max(maxValue, dataMax)
        return RadarChart(title: title, axes: axes, curves: curves,
                          maxValue: ceiling, minValue: minValue, ticks: max(ticks, 1))
    }

    /// Splits on `separator` but not inside `[]` or `{}` (so axis labels and
    /// curve value maps aren't cut in half).
    static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var out: [String] = []
        var depth = 0
        var current = ""
        for ch in text {
            if ch == "[" || ch == "{" { depth += 1 }
            else if ch == "]" || ch == "}" { depth = Swift.max(0, depth - 1) }
            if ch == separator, depth == 0 {
                out.append(current); current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
        return out
    }
}
