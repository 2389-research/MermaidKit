import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a Gantt chart: a left gutter of task labels, section tint
    /// bands, a day axis, and one bar per task (a diamond for a milestone).
    /// Time maps to x through a bounded day-width so a long schedule can't
    /// produce a runaway canvas. Pure geometry — the renderer only draws.
    public static func layout(_ gantt: GanttChart, measure: DiagramTextMeasurer) -> GanttLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = gantt.title == nil ? 0 : 24
        let rowHeight: CGFloat = 24
        let barHeight: CGFloat = 14
        let axisHeight: CGFloat = 18

        // Left gutter sized to the widest task label (clamped).
        let labelWidth = gantt.tasks.map { measure($0.label, labelFontSize).width }.max() ?? 60
        let gutter = margin + min(max(labelWidth, 40), 180) + 10

        // Day → x, with the day width bounded so the chart stays a sane size
        // regardless of the schedule's span (guards the runaway-width budget).
        let span = max(gantt.tasks.map(\.end).max() ?? 1, 1)
        let dayWidth = min(max(360 / CGFloat(span), 3), 36)
        let chartWidth = CGFloat(span) * dayWidth
        func x(_ day: Double) -> CGFloat { gutter + CGFloat(day) * dayWidth }

        let chartTop = margin + titleHeight

        // One bar per task, in declaration order.
        var bars: [GanttLayout.Bar] = []
        for (row, task) in gantt.tasks.enumerated() {
            let rowY = chartTop + CGFloat(row) * rowHeight
            let barY = rowY + (rowHeight - barHeight) / 2
            let startX = x(task.start)
            let frame = task.isMilestone
                ? CGRect(x: startX - barHeight / 2, y: barY, width: barHeight, height: barHeight)
                : CGRect(x: startX, y: barY, width: max(CGFloat(task.length) * dayWidth, 3), height: barHeight)
            bars.append(GanttLayout.Bar(
                label: task.label,
                frame: frame,
                labelPoint: CGPoint(x: gutter - 8, y: rowY + rowHeight / 2),
                isMilestone: task.isMilestone,
                status: task.status
            ))
        }

        // Section tint bands over each run of consecutive same-section rows.
        var sections: [GanttLayout.SectionBand] = []
        var row = 0
        while row < gantt.tasks.count {
            let name = gantt.tasks[row].section
            var count = 1
            while row + count < gantt.tasks.count, gantt.tasks[row + count].section == name { count += 1 }
            if !name.isEmpty {
                sections.append(GanttLayout.SectionBand(
                    name: name,
                    frame: CGRect(x: margin, y: chartTop + CGFloat(row) * rowHeight,
                                  width: gutter - margin + chartWidth, height: CGFloat(count) * rowHeight),
                    colorIndex: gantt.sections.firstIndex(of: name) ?? 0
                ))
            }
            row += count
        }

        let chartBottom = chartTop + CGFloat(gantt.tasks.count) * rowHeight

        // A handful of evenly spaced day ticks across the span.
        var ticks: [GanttLayout.Tick] = []
        let step = max(1, Int((span / 4).rounded()))
        var day = 0
        while Double(day) <= span {
            ticks.append(GanttLayout.Tick(x: x(Double(day)), label: "\(day)", top: chartTop, bottom: chartBottom))
            day += step
        }

        return GanttLayout(
            size: CGSize(width: gutter + chartWidth + margin, height: chartBottom + axisHeight + margin),
            title: gantt.title,
            labelGutter: gutter,
            bars: bars,
            sections: sections,
            ticks: ticks
        )
    }
}
