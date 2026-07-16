import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a quadrant chart: a square 2×2 plot with per-quadrant tint
    /// quarters and names, axis-end labels (x below, y rotated in a left
    /// gutter), and each data point as a dot with its label to the right.
    /// Coordinates are 0…1 (x left→right, y bottom→top). Pure geometry.
    public static func layout(_ chart: QuadrantChart, measure: DiagramTextMeasurer) -> QuadrantLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = chart.title == nil ? 0 : 26
        let side: CGFloat = 460
        let yGutter: CGFloat = 20        // left strip for rotated y-axis labels
        let xStrip: CGFloat = 22         // bottom strip for x-axis labels
        let dotRadius: CGFloat = 4

        let plotRect = CGRect(x: margin + yGutter, y: margin + titleHeight, width: side, height: side)
        func x(_ v: Double) -> CGFloat { plotRect.minX + CGFloat(v) * side }
        func y(_ v: Double) -> CGFloat { plotRect.maxY - CGFloat(v) * side }  // flip: 1 = top

        // Data points, labels to the right of each dot.
        var points: [QuadrantLayout.Point] = []
        var maxLabelRight: CGFloat = plotRect.maxX
        for point in chart.points {
            let position = CGPoint(x: x(point.x), y: y(point.y))
            let labelPoint = CGPoint(x: position.x + dotRadius + 5, y: position.y)
            let label = flattenLines(point.label)   // single-line point chrome
            points.append(QuadrantLayout.Point(label: label, position: position, labelPoint: labelPoint))
            maxLabelRight = max(maxLabelRight, labelPoint.x + measure(label, labelFontSize).width)
        }

        // Quadrant quarters (Mermaid order: 1 TR, 2 TL, 3 BL, 4 BR).
        let half = side / 2
        let cx = plotRect.midX, cy = plotRect.midY
        let quarters = [
            CGRect(x: cx, y: plotRect.minY, width: half, height: half),           // q1 top-right
            CGRect(x: plotRect.minX, y: plotRect.minY, width: half, height: half), // q2 top-left
            CGRect(x: plotRect.minX, y: cy, width: half, height: half),            // q3 bottom-left
            CGRect(x: cx, y: cy, width: half, height: half)                        // q4 bottom-right
        ]
        var quadrantLabels: [QuadrantLayout.Label] = []
        for (index, name) in chart.quadrants.enumerated() {
            guard let name, index < quarters.count else { continue }
            // Push each name toward the OUTER edge of its quarter (top quarters
            // up, bottom quarters down) so it stays clear of the mid-value dot
            // clusters that gather near the plot's center lines.
            let rect = quarters[index]
            let isBottom = index >= 2   // q3 (BL) and q4 (BR) are the bottom row
            let cy = isBottom ? rect.maxY - 14 : rect.minY + 14
            quadrantLabels.append(QuadrantLayout.Label(text: flattenLines(name), center: CGPoint(x: rect.midX, y: cy)))
        }

        // Axis-end labels, centered under/beside each half.
        var xAxisLabels: [QuadrantLayout.Label] = []
        if let left = chart.xAxisLeft {
            xAxisLabels.append(.init(text: flattenLines(left), center: CGPoint(x: plotRect.minX + side * 0.25, y: plotRect.maxY + xStrip / 2 + 4)))
        }
        if let right = chart.xAxisRight {
            xAxisLabels.append(.init(text: flattenLines(right), center: CGPoint(x: plotRect.minX + side * 0.75, y: plotRect.maxY + xStrip / 2 + 4)))
        }
        var yAxisLabels: [QuadrantLayout.Label] = []
        if let bottom = chart.yAxisBottom {
            yAxisLabels.append(.init(text: flattenLines(bottom), center: CGPoint(x: plotRect.minX - yGutter / 2, y: plotRect.minY + side * 0.75)))
        }
        if let top = chart.yAxisTop {
            yAxisLabels.append(.init(text: flattenLines(top), center: CGPoint(x: plotRect.minX - yGutter / 2, y: plotRect.minY + side * 0.25)))
        }

        let width = max(maxLabelRight, plotRect.maxX) + margin
        let height = plotRect.maxY + xStrip + margin

        return QuadrantLayout(
            size: CGSize(width: width, height: height),
            title: chart.title.map(flattenLines),
            plotRect: plotRect,
            dotRadius: dotRadius,
            points: points,
            quadrantRects: quarters,
            quadrantLabels: quadrantLabels,
            xAxisLabels: xAxisLabels,
            yAxisLabels: yAxisLabels
        )
    }
}
