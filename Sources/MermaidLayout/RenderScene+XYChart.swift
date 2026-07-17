import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers an `XYChartLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: XYChartLayout, …)`
    /// (MermaidRender/DiagramRenderer+XYChart.swift). It emits, in the same
    /// painter's order: an optional title, horizontal gridlines with
    /// right-aligned value labels, the left+bottom axis frame, categorical bar
    /// series, categorical line series (polyline + vertex dots), then the x
    /// category labels and optional axis titles (y-axis title rotated). All
    /// colors are flat; nothing is approximated.
    public static func from(_ layout: XYChartLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // Horizontal gridlines + value labels (right-aligned to their center).
        for label in layout.yLabels {
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: layout.plotRect.minX, y: label.center.y),
                         CGPoint(x: layout.plotRect.maxX, y: label.center.y)],
                stroke: Stroke(color: theme.hairline, width: 1))))
            if !label.text.isEmpty {
                let measured = measure(label.text, 9)
                elements.append(.text(Text(
                    string: label.text,
                    center: CGPoint(x: label.center.x - measured.width / 2, y: label.center.y),
                    fontSize: 9, color: theme.tertiaryText)))
            }
        }

        // Axis frame (left + bottom).
        elements.append(.polyline(Polyline(
            points: [CGPoint(x: layout.plotRect.minX, y: layout.plotRect.minY),
                     CGPoint(x: layout.plotRect.minX, y: layout.plotRect.maxY),
                     CGPoint(x: layout.plotRect.maxX, y: layout.plotRect.maxY)],
            stroke: Stroke(color: theme.ink.withAlpha(0.35), width: 1))))

        // Bars.
        for bar in layout.bars {
            elements.append(.shape(Shape(
                path: .roundedRect(bar.frame, radius: 2),
                fill: theme.categoricalColor(bar.colorIndex).withAlpha(0.75), stroke: nil)))
        }

        // Line series: stroked polyline with a dot per point.
        for line in layout.lines {
            let color = theme.categoricalColor(line.colorIndex)
            if line.points.count >= 2 {
                elements.append(.polyline(Polyline(
                    points: line.points, stroke: Stroke(color: color, width: 2))))
            }
            for point in line.points {
                elements.append(.shape(Shape(
                    path: .ellipse(CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                    fill: color, stroke: nil)))
            }
        }

        // x-axis category labels.
        for label in layout.xLabels where !label.text.isEmpty {
            elements.append(.text(Text(
                string: label.text, center: label.center,
                fontSize: 9, color: theme.secondaryText)))
        }
        if let xTitle = layout.xAxisTitle, !xTitle.text.isEmpty {
            elements.append(.text(Text(
                string: xTitle.text, center: xTitle.center,
                fontSize: 9.5, weight: .medium, color: theme.secondaryText)))
        }
        if let yTitle = layout.yAxisTitle, !yTitle.text.isEmpty {
            elements.append(.text(Text(
                string: yTitle.text, center: yTitle.center,
                fontSize: 9.5, weight: .medium, color: theme.secondaryText, rotation: -.pi / 2)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
