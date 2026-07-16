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

    static func draw(_ layout: RadarLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        func polygon(_ points: [CGPoint], in ctx: CGContext) {
            guard let first = points.first else { return }
            ctx.move(to: first)
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.closePath()
        }

        // Graticule rings.
        for ring in layout.rings {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.14)))
            context.setLineWidth(1)
            context.beginPath()
            polygon(ring.points, in: context)
            context.strokePath()
            context.restoreGState()
        }

        // Spokes + axis labels.
        for spoke in layout.spokes {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.18)))
            context.setLineWidth(1)
            context.beginPath()
            context.move(to: layout.center)
            context.addLine(to: spoke.end)
            context.strokePath()
            context.restoreGState()
            drawText(spoke.label, center: spoke.labelPoint, size: 9.5,
                     color: theme.secondaryTextColor, in: context)
        }

        // Curve polygons: translucent fill + stroked outline + vertex dots.
        for curve in layout.curves {
            let color = theme.categoricalColor(curve.colorIndex)
            context.saveGState()
            context.setFillColor(resolvedCGColor(color.withAlphaComponent(0.14)))
            context.beginPath()
            polygon(curve.points, in: context)
            context.fillPath()
            context.setStrokeColor(resolvedCGColor(color.withAlphaComponent(0.9)))
            context.setLineWidth(2)
            context.setLineJoin(.round)
            context.beginPath()
            polygon(curve.points, in: context)
            context.strokePath()
            context.setFillColor(resolvedCGColor(color))
            for p in curve.points {
                context.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
            }
            context.restoreGState()
        }

        // Legend.
        for entry in layout.legend {
            let color = theme.categoricalColor(entry.colorIndex)
            context.saveGState()
            context.setFillColor(resolvedCGColor(color))
            context.fillEllipse(in: CGRect(x: entry.swatchCenter.x - 4, y: entry.swatchCenter.y - 4, width: 8, height: 8))
            context.restoreGState()
            drawTextLeft(entry.label, at: entry.labelPoint, size: 10, color: theme.ink, in: context)
        }
    }
}
#endif
