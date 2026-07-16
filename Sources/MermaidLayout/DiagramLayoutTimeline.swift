import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a timeline as a vertical spine: period labels right-aligned in
    /// a left gutter, a node dot per period on the spine, and each period's
    /// events as rounded cards stacked to the right. A section run gets a
    /// full-width tint band with its name in a reserved header strip above its
    /// first period. Pure geometry — the renderer only draws.
    public static func layout(_ timeline: Timeline, measure: DiagramTextMeasurer) -> TimelineLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = timeline.title == nil ? 0 : 26
        let eventHeight: CGFloat = 24
        let eventGap: CGFloat = 6
        let periodGap: CGFloat = 16
        let sectionHeaderHeight: CGFloat = 22   // strip above a section's first period
        let dotGap: CGFloat = 16                // spine → first event card
        let cardPadding: CGFloat = 10           // horizontal text inset inside a card

        // Left gutter sized to the widest period label (clamped).
        let labelWidth = timeline.periods.map { measure($0.label, labelFontSize).width }.max() ?? 40
        let spineX = margin + min(max(labelWidth, 32), 120) + 12
        let cardX = spineX + dotGap

        // Card width tracks the widest event, clamped so one long event can't
        // blow out the canvas.
        let widestEvent = timeline.periods
            .flatMap(\.events)
            .map { measure($0, nodeFontSize).width }
            .max() ?? 0
        let cardWidth = min(max(widestEvent + cardPadding * 2, 60), 300)
        let bandWidth = cardX + cardWidth - margin

        func colorIndex(for period: Timeline.Period, fallback: Int) -> Int {
            guard !period.section.isEmpty,
                  let index = timeline.sections.firstIndex(of: period.section)
            else { return fallback }
            return index
        }

        var periods: [TimelineLayout.Period] = []
        var sections: [TimelineLayout.SectionBand] = []
        var y = margin + titleHeight
        var firstDotY: CGFloat = y
        var lastDotY: CGFloat = y

        // The open section band, if any: its name, palette index, and top edge.
        var openBand: (name: String, colorIndex: Int, top: CGFloat)?
        var previousSection = ""

        func closeBand(bottom: CGFloat) {
            guard let band = openBand else { return }
            sections.append(TimelineLayout.SectionBand(
                name: band.name,
                frame: CGRect(x: margin, y: band.top, width: bandWidth, height: bottom - band.top),
                colorIndex: band.colorIndex
            ))
            openBand = nil
        }

        for (periodIndex, period) in timeline.periods.enumerated() {
            // Section boundary: close the previous band; if a new named section
            // begins, reserve a header strip so its label never collides with
            // the first period's row.
            if period.section != previousSection {
                closeBand(bottom: y - periodGap / 2)
                if !period.section.isEmpty {
                    openBand = (period.section, timeline.sections.firstIndex(of: period.section) ?? 0, y)
                    y += sectionHeaderHeight
                }
                previousSection = period.section
            }

            let rows = max(period.events.count, 1)
            let blockHeight = CGFloat(rows) * eventHeight + CGFloat(rows - 1) * eventGap
            let dotY = y + eventHeight / 2

            var events: [TimelineLayout.Event] = []
            for (eventIndex, text) in period.events.enumerated() {
                let frame = CGRect(
                    x: cardX,
                    y: y + CGFloat(eventIndex) * (eventHeight + eventGap),
                    width: cardWidth,
                    height: eventHeight
                )
                events.append(TimelineLayout.Event(
                    text: text, frame: frame,
                    colorIndex: colorIndex(for: period, fallback: periodIndex)
                ))
            }

            periods.append(TimelineLayout.Period(
                label: period.label,
                labelPoint: CGPoint(x: spineX - 10, y: dotY),
                dot: CGPoint(x: spineX, y: dotY),
                events: events
            ))

            if periodIndex == 0 { firstDotY = dotY }
            lastDotY = dotY
            y += blockHeight + periodGap
        }

        let contentBottom = y - periodGap
        closeBand(bottom: contentBottom + periodGap / 2)

        return TimelineLayout(
            size: CGSize(width: cardX + cardWidth + margin, height: contentBottom + margin),
            title: timeline.title,
            spineX: spineX,
            spineTop: firstDotY,
            spineBottom: lastDotY,
            periods: periods,
            sections: sections
        )
    }
}
