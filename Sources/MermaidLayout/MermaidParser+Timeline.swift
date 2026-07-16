import Foundation

extension MermaidParser {

    /// Parses `timeline` body lines: `title`, `section` headers, and period
    /// rows (`2024 : event : event`). A row starting with `:` appends its
    /// events to the previous period. Nil when no period parses.
    static func parseTimeline(body: [String]) -> Timeline? {
        var title: String?
        var currentSection = ""
        var sections: [String] = []
        var periods: [Timeline.Period] = []

        // Appends events to the most recent period (Mermaid's continuation
        // syntax, where a line starting with ":" carries more events for the
        // period above it).
        func appendEvents(_ events: [String]) {
            guard let last = periods.popLast() else { return }
            periods.append(Timeline.Period(
                label: last.label, section: last.section, events: last.events + events))
        }

        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("section ") {
                currentSection = String(line.dropFirst("section ".count)).trimmingCharacters(in: .whitespaces)
                if !currentSection.isEmpty, !sections.contains(currentSection) {
                    sections.append(currentSection)
                }
                continue
            }
            // `<period> : <event> : <event> …`. The first colon-token is the
            // time period; the rest are its events.
            let parts = line.split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // A line starting with ":" continues the previous period.
            if line.hasPrefix(":") {
                appendEvents(parts.filter { !$0.isEmpty })
                continue
            }

            // Otherwise the first token is a new period's time label; a line
            // with no colon is a bare period with no events.
            guard let label = parts.first, !label.isEmpty else { continue }
            let events = parts.dropFirst().filter { !$0.isEmpty }
            periods.append(Timeline.Period(label: label, section: currentSection, events: Array(events)))
        }

        guard !periods.isEmpty else { return nil }
        return Timeline(title: title, periods: periods, sections: sections)
    }
}
