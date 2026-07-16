import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a user journey as a vertical list of task rows: a 1–5
    /// satisfaction badge, the task label, and the actors, grouped into
    /// section tint bands with a reserved header strip (as the timeline).
    /// Pure geometry — the renderer only draws.
    public static func layout(_ journey: UserJourney, measure: DiagramTextMeasurer) -> JourneyLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = journey.title == nil ? 0 : 26
        let rowHeight: CGFloat = 32
        let scoreDiameter: CGFloat = 22
        let sectionHeaderHeight: CGFloat = 22

        let labelWidth = min(max(journey.tasks.map { measure($0.label, labelFontSize).width }.max() ?? 80, 60), 320)
        let actorStrings = journey.tasks.map { $0.actors.joined(separator: ", ") }
        // No tight clamp: the canvas must fully contain the drawn actor list
        // (it's not truncated), so a clamp shorter than the text would clip it.
        let actorsWidth = min(actorStrings.map { measure($0, labelFontSize).width }.max() ?? 0, 360)

        let scoreCenterX = margin + 8 + scoreDiameter / 2
        let labelX = scoreCenterX + scoreDiameter / 2 + 12
        let actorsX = labelX + labelWidth + 20
        let width = actorsX + actorsWidth + margin + 6
        let bandWidth = width - margin * 2

        var tasks: [JourneyLayout.Task] = []
        var sections: [JourneyLayout.SectionBand] = []
        var y = margin + titleHeight
        var previousSection = ""
        var openBand: (name: String, colorIndex: Int, top: CGFloat)?

        func closeBand(bottom: CGFloat) {
            guard let band = openBand else { return }
            sections.append(JourneyLayout.SectionBand(
                name: band.name,
                frame: CGRect(x: margin, y: band.top, width: bandWidth, height: bottom - band.top),
                colorIndex: band.colorIndex
            ))
            openBand = nil
        }

        for (index, task) in journey.tasks.enumerated() {
            if task.section != previousSection {
                closeBand(bottom: y)
                if !task.section.isEmpty {
                    openBand = (task.section, journey.sections.firstIndex(of: task.section) ?? 0, y)
                    y += sectionHeaderHeight
                }
                previousSection = task.section
            }

            let centerY = y + rowHeight / 2
            tasks.append(JourneyLayout.Task(
                label: task.label,
                labelPoint: CGPoint(x: labelX, y: centerY),
                score: task.score,
                scoreCenter: CGPoint(x: scoreCenterX, y: centerY),
                actors: actorStrings[index],
                actorsPoint: CGPoint(x: actorsX, y: centerY)
            ))
            y += rowHeight
        }
        closeBand(bottom: y)

        return JourneyLayout(
            size: CGSize(width: width, height: y + margin),
            title: journey.title,
            scoreDiameter: scoreDiameter,
            tasks: tasks,
            sections: sections
        )
    }
}
