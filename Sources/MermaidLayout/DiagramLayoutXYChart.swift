import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out an xy chart: bar and/or line series over shared x-axis
    /// categories, with a value axis on the left. Bar series are grouped
    /// side-by-side within each category slot; line series connect category
    /// centers. Pure geometry — the renderer only draws.
    public static func layout(_ chart: XYChart, measure: DiagramTextMeasurer) -> XYChartLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = chart.title == nil ? 0 : 26
        let yGutter: CGFloat = 44          // value labels + rotated axis title
        let xStrip: CGFloat = chart.xAxisTitle == nil ? 22 : 38
        let plotHeight: CGFloat = 240
        let categoryCount = max(chart.categories.count, 1)
        let plotWidth = CGFloat(categoryCount) * 56

        let plotRect = CGRect(x: margin + yGutter, y: margin + titleHeight,
                              width: plotWidth, height: plotHeight)

        // Value range: explicit bounds win; otherwise derive from the data,
        // with the floor pinned at 0 for all-positive data.
        let allValues = chart.series.flatMap(\.values)
        let dataMax = allValues.max() ?? 1
        let dataMin = allValues.min() ?? 0
        // The axis must always cover the data: even when a range is declared,
        // extend it so no series can escape the plot (a declared 0→260 must
        // still hold a series that peaks at 375).
        let yMax = Swift.max(chart.yMax ?? 0, niceCeiling(dataMax))
        let yMin = Swift.min(chart.yMin ?? 0, dataMin, 0)
        let span = yMax - yMin == 0 ? 1 : yMax - yMin
        func y(_ value: Double) -> CGFloat {
            plotRect.maxY - CGFloat((value - yMin) / span) * plotHeight
        }

        let categoryWidth = plotWidth / CGFloat(categoryCount)
        func categoryCenter(_ index: Int) -> CGFloat {
            plotRect.minX + (CGFloat(index) + 0.5) * categoryWidth
        }

        // Bars: grouped within each category's central band.
        let barSeries = chart.series.enumerated().filter { $0.element.kind == .bar }
        let barCount = max(barSeries.count, 1)
        let band = categoryWidth * 0.7
        let subWidth = band / CGFloat(barCount)
        var bars: [XYChartLayout.Bar] = []
        for (slot, (seriesIndex, s)) in barSeries.enumerated() {
            for (i, value) in s.values.enumerated() where i < categoryCount {
                let left = categoryCenter(i) - band / 2 + CGFloat(slot) * subWidth
                let top = y(value)
                let base = y(Swift.max(yMin, 0))
                bars.append(XYChartLayout.Bar(
                    frame: CGRect(x: left + subWidth * 0.1, y: Swift.min(top, base),
                                  width: subWidth * 0.8, height: abs(base - top)),
                    colorIndex: seriesIndex
                ))
            }
        }

        // Lines: polylines across category centers.
        var lines: [XYChartLayout.Line] = []
        for (seriesIndex, s) in chart.series.enumerated() where s.kind == .line {
            let points = s.values.enumerated().prefix(categoryCount).map { i, value in
                CGPoint(x: categoryCenter(i), y: y(value))
            }
            if !points.isEmpty { lines.append(XYChartLayout.Line(points: Array(points), colorIndex: seriesIndex)) }
        }

        // x-axis category labels. Axis chrome is single-line: collapse any
        // line break to a space rather than wrap a fixed-height tick strip.
        let xLabels = chart.categories.enumerated().map { i, text in
            XYChartLayout.Label(text: flattenLines(text), center: CGPoint(x: categoryCenter(i), y: plotRect.maxY + 11))
        }

        // y-axis value ticks (5 divisions).
        var yLabels: [XYChartLayout.Label] = []
        let divisions = 4
        for step in 0...divisions {
            let value = yMin + (span) * Double(step) / Double(divisions)
            let text = (abs(value) >= 100 && value.isFinite) ? String(Int(value.rounded())) : formatAxisValue(value)
            yLabels.append(XYChartLayout.Label(text: text, center: CGPoint(x: plotRect.minX - 6, y: y(value))))
        }

        let yAxisTitle = chart.yAxisTitle.map {
            XYChartLayout.Label(text: flattenLines($0), center: CGPoint(x: margin + 6, y: plotRect.midY))
        }
        let xAxisTitle = chart.xAxisTitle.map {
            XYChartLayout.Label(text: flattenLines($0), center: CGPoint(x: plotRect.midX, y: plotRect.maxY + xStrip - 2))
        }

        return XYChartLayout(
            size: CGSize(width: plotRect.maxX + margin, height: plotRect.maxY + xStrip + margin),
            title: chart.title.map(flattenLines),
            plotRect: plotRect,
            bars: bars,
            lines: lines,
            xLabels: xLabels,
            yLabels: yLabels,
            yAxisTitle: yAxisTitle,
            xAxisTitle: xAxisTitle
        )
    }

    /// Rounds an axis maximum up to a readable value (1/2/5 × 10ⁿ).
    static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let exponent = (log10(value)).rounded(.down)
        let magnitude = pow(10, exponent)
        let fraction = value / magnitude
        let niceFraction: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10
        return niceFraction * magnitude
    }

    /// Axis tick text: whole numbers plain, otherwise one decimal place;
    /// em-dash for a non-finite value.
    static func formatAxisValue(_ value: Double) -> String {
        guard value.isFinite else { return "\u{2014}" }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
