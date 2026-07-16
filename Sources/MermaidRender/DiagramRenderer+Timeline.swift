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

    static func draw(_ layout: TimelineLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        // Section tint bands (and their names) behind the spine and cards.
        for band in layout.sections {
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.categoricalColor(band.colorIndex).withAlphaComponent(0.10)))
            context.addPath(CGPath(roundedRect: band.frame, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.fillPath()
            context.restoreGState()
            drawTextLeft(band.name, at: CGPoint(x: band.frame.minX + 8, y: band.frame.minY + 10),
                         size: 9.5, weight: .semibold, color: theme.tertiaryTextColor, in: context)
        }

        // The vertical spine the dots sit on.
        if layout.spineBottom > layout.spineTop {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.25)))
            context.setLineWidth(2)
            context.beginPath()
            context.move(to: CGPoint(x: layout.spineX, y: layout.spineTop))
            context.addLine(to: CGPoint(x: layout.spineX, y: layout.spineBottom))
            context.strokePath()
            context.restoreGState()
        }

        for period in layout.periods {
            // Connector from the spine to the first event card's row.
            if let first = period.events.first {
                context.saveGState()
                context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.18)))
                context.setLineWidth(1)
                context.beginPath()
                context.move(to: period.dot)
                context.addLine(to: CGPoint(x: first.frame.minX, y: period.dot.y))
                context.strokePath()
                context.restoreGState()
            }

            // Node dot on the spine.
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.accent))
            let radius: CGFloat = 4
            context.fillEllipse(in: CGRect(x: period.dot.x - radius, y: period.dot.y - radius,
                                           width: radius * 2, height: radius * 2))
            context.restoreGState()

            // Period label, right-aligned into the gutter.
            let measured = measure(period.label, size: labelSize, weight: .semibold)
            drawText(period.label,
                     center: CGPoint(x: period.labelPoint.x - measured.width / 2, y: period.labelPoint.y),
                     size: labelSize, weight: .semibold, color: theme.secondaryTextColor, in: context)

            // Event cards, tinted by section (else by period).
            for event in period.events {
                let tint = theme.categoricalColor(event.colorIndex)
                context.saveGState()
                context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.16)))
                context.addPath(CGPath(roundedRect: event.frame, cornerWidth: 5, cornerHeight: 5, transform: nil))
                context.fillPath()
                context.setStrokeColor(resolvedCGColor(tint.withAlphaComponent(0.45)))
                context.setLineWidth(1)
                context.addPath(CGPath(roundedRect: event.frame.insetBy(dx: 0.5, dy: 0.5),
                                       cornerWidth: 5, cornerHeight: 5, transform: nil))
                context.strokePath()
                context.restoreGState()

                drawTextLeft(event.text, at: CGPoint(x: event.frame.minX + 10, y: event.frame.midY),
                             size: labelSize, color: theme.ink, in: context)
            }
        }
    }
}
#endif
