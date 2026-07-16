import Foundation

extension MermaidParser {

    /// Parses `journey` body lines: `title`, `section <name>`, and
    /// `Task name: <score>: Actor1, Actor2` tasks (score clamped to 1…5,
    /// defaulting to 3; actors optional). Nil when no task parses.
    static func parseJourney(body: [String]) -> UserJourney? {
        var title: String?
        var currentSection = ""
        var sections: [String] = []
        var tasks: [UserJourney.Task] = []

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
            // `Task name: <score>: Actor1, Actor2`. Score and actors optional.
            let parts = line.split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let label = parts.first, !label.isEmpty, parts.count >= 2 else { continue }
            let score = min(max(Int(parts[1]) ?? 3, 1), 5)
            let actors = parts.count >= 3
                ? parts[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            tasks.append(UserJourney.Task(label: label, score: score, actors: actors, section: currentSection))
        }

        guard !tasks.isEmpty else { return nil }
        return UserJourney(title: title, tasks: tasks, sections: sections)
    }
}
