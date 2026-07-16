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

    static func draw(_ layout: GanttLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        // Section tint bands behind everything, in the section's palette color.
        for band in layout.sections {
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.categoricalColor(band.colorIndex).withAlphaComponent(0.10)))
            context.fill(band.frame)
            context.restoreGState()
        }

        // Day grid: hairline verticals with a small index label at the base.
        for tick in layout.ticks {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            context.beginPath()
            context.move(to: CGPoint(x: tick.x, y: tick.top))
            context.addLine(to: CGPoint(x: tick.x, y: tick.bottom))
            context.strokePath()
            context.restoreGState()
            drawText(tick.label, center: CGPoint(x: tick.x, y: tick.bottom + 9),
                     size: 9, color: theme.tertiaryTextColor, in: context)
        }

        for bar in layout.bars {
            // Task label, right-aligned into the gutter.
            let measured = measure(bar.label, size: labelSize)
            drawText(bar.label,
                     center: CGPoint(x: bar.labelPoint.x - measured.width / 2, y: bar.labelPoint.y),
                     size: labelSize, color: theme.secondaryTextColor, in: context)

            let fill = ganttFill(bar.status, theme: theme)
            context.saveGState()
            context.setFillColor(resolvedCGColor(fill))
            if bar.isMilestone {
                // A diamond centered in the bar's box.
                let f = bar.frame
                context.beginPath()
                context.move(to: CGPoint(x: f.midX, y: f.minY))
                context.addLine(to: CGPoint(x: f.maxX, y: f.midY))
                context.addLine(to: CGPoint(x: f.midX, y: f.maxY))
                context.addLine(to: CGPoint(x: f.minX, y: f.midY))
                context.closePath()
                context.fillPath()
            } else {
                context.addPath(CGPath(roundedRect: bar.frame, cornerWidth: 3, cornerHeight: 3, transform: nil))
                context.fillPath()
                if bar.status == .critical {
                    context.setStrokeColor(resolvedCGColor(PlatformColor.systemRed))
                    context.setLineWidth(1.5)
                    context.addPath(CGPath(roundedRect: bar.frame.insetBy(dx: 0.75, dy: 0.75),
                                           cornerWidth: 3, cornerHeight: 3, transform: nil))
                    context.strokePath()
                }
            }
            context.restoreGState()
        }
    }

    /// Bar fill by task status: active is the full accent, normal a lighter
    /// tint, done a muted ink, critical a warm red.
    static func ganttFill(_ status: GanttChart.Status, theme: DiagramTheme) -> PlatformColor {
        switch status {
        case .normal: return theme.accent.withAlphaComponent(0.55)
        case .active: return theme.accent
        case .done: return theme.ink.withAlphaComponent(0.28)
        case .critical: return PlatformColor.systemRed.withAlphaComponent(0.85)
        }
    }
}
#endif
