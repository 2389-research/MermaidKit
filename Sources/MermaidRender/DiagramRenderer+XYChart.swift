#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
import MermaidLayout

#if canImport(AppKit)
import CoreGraphics
import CoreText
import AppKit
#elseif canImport(UIKit)
import CoreGraphics
import CoreText
import UIKit
#endif

extension DiagramRenderer {

    static func draw(_ layout: XYChartLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        // Horizontal gridlines + value labels.
        for label in layout.yLabels {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            context.beginPath()
            context.move(to: CGPoint(x: layout.plotRect.minX, y: label.center.y))
            context.addLine(to: CGPoint(x: layout.plotRect.maxX, y: label.center.y))
            context.strokePath()
            context.restoreGState()
            let measured = measure(label.text, size: 9)
            drawText(label.text, center: CGPoint(x: label.center.x - measured.width / 2, y: label.center.y),
                     size: 9, color: theme.tertiaryTextColor, in: context)
        }

        // Axis frame (left + bottom).
        context.saveGState()
        context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.35)))
        context.setLineWidth(1)
        context.beginPath()
        context.move(to: CGPoint(x: layout.plotRect.minX, y: layout.plotRect.minY))
        context.addLine(to: CGPoint(x: layout.plotRect.minX, y: layout.plotRect.maxY))
        context.addLine(to: CGPoint(x: layout.plotRect.maxX, y: layout.plotRect.maxY))
        context.strokePath()
        context.restoreGState()

        // Bars.
        for bar in layout.bars {
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.categoricalColor(bar.colorIndex).withAlphaComponent(0.75)))
            context.addPath(CGPath(roundedRect: bar.frame, cornerWidth: 2, cornerHeight: 2, transform: nil))
            context.fillPath()
            context.restoreGState()
        }

        // Line series: stroked polyline with a dot per point.
        for line in layout.lines {
            let color = theme.categoricalColor(line.colorIndex)
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(color))
            context.setLineWidth(2)
            context.setLineJoin(.round)
            context.beginPath()
            for (i, point) in line.points.enumerated() {
                if i == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.strokePath()
            context.setFillColor(resolvedCGColor(color))
            for point in line.points {
                context.fillEllipse(in: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
            }
            context.restoreGState()
        }

        // x-axis category labels.
        for label in layout.xLabels {
            drawText(label.text, center: label.center, size: 9,
                     color: theme.secondaryTextColor, in: context)
        }
        if let xTitle = layout.xAxisTitle {
            drawText(xTitle.text, center: xTitle.center, size: 9.5, weight: .medium,
                     color: theme.secondaryTextColor, in: context)
        }
        if let yTitle = layout.yAxisTitle {
            drawTextRotated(yTitle.text, center: yTitle.center, size: 9.5, weight: .medium,
                            color: theme.secondaryTextColor, in: context)
        }
    }
}
#endif
