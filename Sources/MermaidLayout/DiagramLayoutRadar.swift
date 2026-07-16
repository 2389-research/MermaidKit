import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a radar chart: N axes as spokes from a center, a concentric
    /// graticule of `ticks` polygons, and one polygon per curve. A legend of
    /// curve labels sits below. Pure geometry — the renderer only draws.
    public static func layout(_ chart: RadarChart, measure: DiagramTextMeasurer) -> RadarLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = chart.title == nil ? 0 : 26
        let radius: CGFloat = 108
        let hMargin: CGFloat = 78          // room for side axis labels
        let vMargin: CGFloat = 26          // room for top/bottom axis labels
        let axisCount = chart.axes.count

        let center = CGPoint(x: margin + hMargin + radius,
                             y: margin + titleHeight + vMargin + radius)

        // Angle for axis i: start at the top, go clockwise.
        func angle(_ i: Int) -> CGFloat { -.pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(axisCount) }
        func point(fraction: CGFloat, axis i: Int) -> CGPoint {
            let a = angle(i)
            return CGPoint(x: center.x + fraction * radius * cos(a),
                           y: center.y + fraction * radius * sin(a))
        }

        // Graticule rings.
        var rings: [RadarLayout.Ring] = []
        for tick in 1...max(chart.ticks, 1) {
            let fraction = CGFloat(tick) / CGFloat(max(chart.ticks, 1))
            rings.append(RadarLayout.Ring(points: (0..<axisCount).map { point(fraction: fraction, axis: $0) }))
        }

        // Spokes with outward axis labels.
        var spokes: [RadarLayout.Spoke] = []
        for i in 0..<axisCount {
            spokes.append(RadarLayout.Spoke(
                end: point(fraction: 1, axis: i),
                label: flattenLines(chart.axes[i].label),   // single-line chrome
                labelPoint: point(fraction: 1.16, axis: i)
            ))
        }

        // Curve polygons.
        let span = chart.maxValue - chart.minValue == 0 ? 1 : chart.maxValue - chart.minValue
        var curves: [RadarLayout.Curve] = []
        for (curveIndex, curve) in chart.curves.enumerated() {
            let points = curve.values.enumerated().map { i, value in
                point(fraction: CGFloat((value - chart.minValue) / span), axis: i)
            }
            curves.append(RadarLayout.Curve(points: points, colorIndex: curveIndex))
        }

        // Legend below the chart.
        let chartBottom = center.y + radius + vMargin
        var legend: [RadarLayout.LegendEntry] = []
        var legendWidth: CGFloat = 0
        for (i, curve) in chart.curves.enumerated() {
            let y = chartBottom + 10 + CGFloat(i) * 18
            let label = flattenLines(curve.label)   // single-line legend chrome
            legend.append(RadarLayout.LegendEntry(
                label: label,
                swatchCenter: CGPoint(x: margin + 6, y: y),
                labelPoint: CGPoint(x: margin + 18, y: y),
                colorIndex: i
            ))
            legendWidth = max(legendWidth, 18 + measure(label, labelFontSize).width)
        }

        let width = max(center.x + radius + hMargin + margin, margin + legendWidth + margin)
        let height = (legend.last?.labelPoint.y ?? chartBottom) + margin
        return RadarLayout(
            size: CGSize(width: width, height: height),
            title: chart.title.map(flattenLines),
            center: center,
            rings: rings,
            spokes: spokes,
            curves: curves,
            legend: legend
        )
    }
}
