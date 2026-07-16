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

    static func draw(_ layout: JourneyLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        for band in layout.sections {
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.categoricalColor(band.colorIndex).withAlphaComponent(0.10)))
            context.addPath(CGPath(roundedRect: band.frame, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.fillPath()
            context.restoreGState()
            drawTextLeft(band.name, at: CGPoint(x: band.frame.minX + 8, y: band.frame.minY + 10),
                         size: 9.5, weight: .semibold, color: theme.tertiaryTextColor, in: context)
        }

        for task in layout.tasks {
            // Satisfaction badge: colour graded 1 (red) → 5 (green), digit inside.
            let radius = layout.scoreDiameter / 2
            context.saveGState()
            context.setFillColor(resolvedCGColor(journeyScoreColor(task.score)))
            context.fillEllipse(in: CGRect(x: task.scoreCenter.x - radius, y: task.scoreCenter.y - radius,
                                           width: layout.scoreDiameter, height: layout.scoreDiameter))
            context.restoreGState()
            drawText("\(task.score)", center: task.scoreCenter, size: 11, weight: .semibold,
                     color: .white, in: context)

            // Task label.
            let measured = measure(task.label, size: labelSize)
            drawText(task.label,
                     center: CGPoint(x: task.labelPoint.x + measured.width / 2, y: task.labelPoint.y),
                     size: labelSize, color: theme.ink, in: context)

            // Actors, muted.
            if !task.actors.isEmpty {
                let actorsMeasured = measure(task.actors, size: labelSize)
                drawText(task.actors,
                         center: CGPoint(x: task.actorsPoint.x + actorsMeasured.width / 2, y: task.actorsPoint.y),
                         size: labelSize, color: theme.tertiaryTextColor, in: context)
            }
        }
    }

    /// Satisfaction badge colour: 1 red, 2 orange, 3 amber, 4 lime, 5 green.
    static func journeyScoreColor(_ score: Int) -> PlatformColor {
        switch score {
        case 1: return PlatformColor.systemRed
        case 2: return PlatformColor.systemOrange
        case 3: return PlatformColor.systemYellow.withAlphaComponent(0.95)
        case 4: return PlatformColor(red: 0.52, green: 0.72, blue: 0.20, alpha: 1)
        default: return PlatformColor.systemGreen
        }
    }
}
#endif
