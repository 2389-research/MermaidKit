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

    static func draw(_ layout: C4Layout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        // Relationship arrows first, so box fills tuck over the shaft ends.
        // Routes are orthogonal polylines through the empty channels.
        for edge in layout.edges {
            let pts = edge.points
            guard let first = pts.first, pts.count >= 2 else { continue }
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.5)))
            context.setLineWidth(1)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: first)
            for p in pts.dropFirst() { context.addLine(to: p) }
            context.strokePath()
            context.restoreGState()
            drawFilledArrowhead(at: pts[pts.count - 1], from: pts[pts.count - 2],
                                color: theme.ink, in: context)
        }

        // Boxes.
        for box in layout.boxes {
            let tint = theme.categoricalColor(box.colorIndex)
            let fill = tint.withAlphaComponent(box.external ? 0.06 : 0.14)
            let border = tint.withAlphaComponent(box.external ? 0.45 : 0.65)

            context.saveGState()
            let path = CGPath(roundedRect: box.frame, cornerWidth: 6, cornerHeight: 6, transform: nil)
            context.setFillColor(resolvedCGColor(fill))
            context.addPath(path)
            context.fillPath()
            context.setStrokeColor(resolvedCGColor(border))
            context.setLineWidth(1)
            if box.external { context.setLineDash(phase: 0, lengths: [4, 3]) }
            context.addPath(path)
            context.strokePath()
            context.restoreGState()

            // A person carries a small "head" straddling the top border.
            if box.isPerson {
                let headR: CGFloat = 7
                let head = CGRect(x: box.frame.midX - headR, y: box.frame.minY - headR - 1,
                                  width: headR * 2, height: headR * 2)
                context.saveGState()
                context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.85)))
                context.fillEllipse(in: head)
                context.restoreGState()
            }

            // Stacked text: stereotype, bold title, detail lines.
            let midX = box.frame.midX
            var y = box.frame.minY + 10          // top padding
            drawText(box.stereotype, center: CGPoint(x: midX, y: y + 6.5),
                     size: 9.5, color: theme.secondaryTextColor, in: context)
            y += 13 + 3                           // stereoH + titleGap
            for line in box.titleLines {
                drawText(line, center: CGPoint(x: midX, y: y + 8),
                         size: 12, weight: .semibold, color: theme.ink, in: context)
                y += 16
            }
            if !box.detailLines.isEmpty {
                y += 4
                for line in box.detailLines {
                    drawText(line, center: CGPoint(x: midX, y: y + 6.5),
                             size: 10, color: theme.secondaryTextColor, in: context)
                    y += 13
                }
            }
        }

        // Edge labels on top of everything, on a canvas-colored pad. Drawn at
        // the route's label point, which sits in a clear channel band.
        for edge in layout.edges {
            guard let label = edge.label else { continue }
            drawEdgeLabel(label, at: edge.labelPoint, theme: theme, in: context)
        }
    }
}
#endif
