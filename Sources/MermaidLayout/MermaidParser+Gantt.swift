import Foundation

extension MermaidParser {

    /// Parses `gantt` body lines: `title` / `section` directives and task rows
    /// (`Label : done, t1, 2024-01-01, 3d`), whose comma tokens — status tags,
    /// an optional id, a start (ISO date or `after <id>`), and a duration or
    /// end date — may appear in any order. Starts resolve to absolute day
    /// offsets, then shift so the earliest task sits at day 0.
    static func parseGantt(body: [String]) -> GanttChart? {
        var title: String?
        var currentSection = ""
        var sections: [String] = []
        var tasks: [GanttChart.Task] = []
        var endByID: [String: Double] = [:]   // absolute end ordinal per task id
        var previousEnd: Double?               // absolute end of the previous task

        for (index, line) in body.enumerated() {
            // Directives (title / dateFormat / axisFormat / excludes / …).
            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("section ") {
                currentSection = String(line.dropFirst("section ".count)).trimmingCharacters(in: .whitespaces)
                if !sections.contains(currentSection) { sections.append(currentSection) }
                continue
            }
            // Directive lines (dateFormat, axisFormat %H:%M, todayMarker,
            // excludes, tickInterval, click href https://...) often contain
            // colons; without this guard each became a PHANTOM TASK BAR.
            let directiveKeywords = ["dateformat", "axisformat", "todaymarker",
                                     "tickinterval", "excludes", "includes",
                                     "weekday", "weekend", "click", "inclusiveenddates",
                                     "topaxis", "displaymode", "acctitle", "accdescr"]
            let keyword = line.split(separator: " ").first.map { $0.lowercased() } ?? ""
            if directiveKeywords.contains(keyword) { continue }
            guard let colon = line.firstIndex(of: ":") else { continue } // non-task directive
            let label = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let spec = String(line[line.index(after: colon)...])
            guard !label.isEmpty else { continue }

            // Comma-separated tokens: status tags, an optional id, a start
            // (date or `after …`), and a duration or end date — in any order.
            var status = GanttChart.Status.normal
            var isMilestone = false
            var id: String?
            var afterIDs: [String] = []
            var dates: [Double] = []
            var duration: Double?
            for token in spec.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
                switch token.lowercased() {
                case "done": status = .done
                case "active": status = .active
                case "crit": status = .critical
                case "milestone": isMilestone = true
                default:
                    if token.lowercased().hasPrefix("after ") {
                        afterIDs = token.dropFirst("after ".count)
                            .split(separator: " ").map { String($0) }
                    } else if let ordinal = dayOrdinal(fromISODate: token) {
                        dates.append(ordinal)
                    } else if let days = durationInDays(token) {
                        duration = days
                    } else if token.lowercased().hasPrefix("until ") {
                        // `until otherTask` ends at another task's start — we
                        // can't resolve it here, but it must NOT become the
                        // id; the bar keeps its default duration.
                        continue
                    } else {
                        id = token   // a bare identifier
                    }
                }
            }

            // Resolve the absolute start ordinal.
            let start: Double
            if let first = dates.first {
                start = first
            } else if !afterIDs.isEmpty {
                start = afterIDs.compactMap { endByID[$0] }.max() ?? previousEnd ?? 0
            } else {
                start = previousEnd ?? 0
            }

            // Resolve the length in days.
            let length: Double
            if isMilestone {
                length = 0
            } else if dates.count >= 2 {
                length = max(0, dates[1] - start)  // start-date, end-date form
            } else {
                length = duration ?? 1
            }

            let taskID = id ?? "task\(index)"
            endByID[taskID] = start + length
            previousEnd = start + length
            tasks.append(GanttChart.Task(
                id: taskID, label: label, section: currentSection,
                start: start, length: length, isMilestone: isMilestone, status: status
            ))
        }

        guard !tasks.isEmpty else { return nil }

        // Normalize so the earliest task sits at day 0.
        let origin = tasks.map(\.start).min() ?? 0
        let normalized = tasks.map { task -> GanttChart.Task in
            var copy = task
            copy.start -= origin
            return copy
        }
        return GanttChart(title: title, tasks: normalized, sections: sections)
    }

    /// Julian Day Number for a proleptic-Gregorian `YYYY-MM-DD` string, or nil.
    /// Only day *differences* matter, so the absolute epoch is arbitrary; this
    /// is integer and timezone-free (works identically on Linux).
    static func dayOrdinal(fromISODate text: String) -> Double? {
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day), parts[0].count == 4
        else { return nil }
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        let jdn = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        return Double(jdn)
    }

    /// A Mermaid duration like `30d`, `2w`, `12h` in days, or nil. A bare
    /// number is treated as days.
    static func durationInDays(_ text: String) -> Double? {
        guard let unit = text.last else { return nil }
        // The bare-number path must sanitize too: Double("inf")/"nan" parse
        // successfully and a non-finite duration traps layout's Int(span)
        // conversions (a reproduced crash). Durations also cap at a century —
        // finite-but-absurd values otherwise size a multi-billion-point canvas.
        let maxDays = 36_500.0
        if let bare = MermaidParser.finiteDouble(text) {
            return bare >= 0 ? min(bare, maxDays) : nil  // "30" → 30 days
        }
        let value = MermaidParser.finiteDouble(text.dropLast())
        guard let value, value >= 0 else { return nil }
        switch unit {
        case "d": return min(value, maxDays)
        case "w": return min(value * 7, maxDays)
        case "h": return value / 24
        case "m": return value / (24 * 60)   // minutes
        case "y": return min(value * 365, maxDays)
        case "M": return min(value * 30, maxDays)   // months (mermaid's approximation)
        case "s": return value / (24 * 3600)
        default:
            // `Nms` (two-char unit) — vanishingly small on a day axis but a
            // valid token; without this it became the task's id.
            if text.hasSuffix("ms"), let ms = MermaidParser.finiteDouble(text.dropLast(2)), ms >= 0 {
                return ms / (24 * 3600 * 1000)
            }
            return nil
        }
    }
}
