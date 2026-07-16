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

    static func draw(_ layout: PieLayout, theme: DiagramTheme, in context: CGContext) {
        if let title = layout.title {
            drawText(title,
                     center: CGPoint(x: layout.center.x, y: layout.center.y - layout.radius - 16),
                     size: 12.5, weight: .semibold, color: theme.ink, in: context)
        }

        // Fill wedges without a per-wedge stroke, then draw one canvas-colored
        // separator per boundary from the hub to the rim. Stroking each wedge
        // outline drew every boundary twice and piled overlapping strokes at
        // the center; a single line per boundary keeps the hub clean.
        for slice in layout.slices {
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.categoricalColor(slice.colorIndex)))
            context.beginPath()
            context.move(to: layout.center)
            context.addArc(
                center: layout.center, radius: layout.radius,
                startAngle: CGFloat(slice.startAngle), endAngle: CGFloat(slice.endAngle),
                clockwise: false
            )
            context.closePath()
            context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.setStrokeColor(resolvedCGColor(theme.canvas))
        context.setLineWidth(2)
        context.setLineCap(.round)
        for slice in layout.slices {
            context.beginPath()
            context.move(to: layout.center)
            context.addLine(to: CGPoint(
                x: layout.center.x + layout.radius * cos(CGFloat(slice.startAngle)),
                y: layout.center.y + layout.radius * sin(CGFloat(slice.startAngle))
            ))
            context.strokePath()
        }
        context.restoreGState()

        // Legend with value chips, vertically stacked.
        var y = layout.legendOrigin.y
        for slice in layout.slices {
            let swatch = CGRect(x: layout.legendOrigin.x, y: y + 4, width: 10, height: 10)
            context.saveGState()
            context.setFillColor(resolvedCGColor(theme.categoricalColor(slice.colorIndex)))
            context.addPath(CGPath(roundedRect: swatch, cornerWidth: 2, cornerHeight: 2, transform: nil))
            context.fillPath()
            context.restoreGState()

            let percent = Int((slice.fraction * 100).rounded())
            let label = "\(slice.label) (\(percent)%)"
            let size = measure(label, size: 10.5)
            drawText(label,
                     center: CGPoint(x: swatch.maxX + 6 + size.width / 2, y: swatch.midY),
                     size: 10.5, color: theme.secondaryTextColor, in: context)
            y += 20
        }
    }
}
#endif
