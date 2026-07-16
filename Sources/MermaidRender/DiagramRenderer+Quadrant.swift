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

    static func draw(_ layout: QuadrantLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        // Tint quarters (Mermaid quadrant order → categorical palette).
        for (index, rect) in layout.quadrantRects.enumerated() {
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.categoricalColor(index).withAlphaComponent(0.08)))
            context.fill(rect)
            context.restoreGState()
        }

        // Plot border and center cross.
        context.saveGState()
        context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.28)))
        context.setLineWidth(1)
        context.stroke(layout.plotRect)
        context.beginPath()
        context.move(to: CGPoint(x: layout.plotRect.midX, y: layout.plotRect.minY))
        context.addLine(to: CGPoint(x: layout.plotRect.midX, y: layout.plotRect.maxY))
        context.move(to: CGPoint(x: layout.plotRect.minX, y: layout.plotRect.midY))
        context.addLine(to: CGPoint(x: layout.plotRect.maxX, y: layout.plotRect.midY))
        context.strokePath()
        context.restoreGState()

        for label in layout.quadrantLabels {
            drawText(label.text, center: label.center, size: 10, weight: .semibold,
                     color: theme.tertiaryTextColor, in: context)
        }
        for label in layout.xAxisLabels {
            drawText(label.text, center: label.center, size: 9.5,
                     color: theme.secondaryTextColor, in: context)
        }
        for label in layout.yAxisLabels {
            drawTextRotated(label.text, center: label.center, size: 9.5,
                            color: theme.secondaryTextColor, in: context)
        }

        for point in layout.points {
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.accent))
            context.fillEllipse(in: CGRect(x: point.position.x - layout.dotRadius,
                                           y: point.position.y - layout.dotRadius,
                                           width: layout.dotRadius * 2, height: layout.dotRadius * 2))
            context.restoreGState()
            let measured = measure(point.label, size: labelSize)
            drawText(point.label,
                     center: CGPoint(x: point.labelPoint.x + measured.width / 2, y: point.labelPoint.y),
                     size: labelSize, color: theme.ink, in: context)
        }
    }
}
#endif
