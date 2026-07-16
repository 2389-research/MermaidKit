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

    static func draw(_ layout: ZenUMLLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        // Dashed lifelines dropping from each participant box.
        for p in layout.participants {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.beginPath()
            context.move(to: CGPoint(x: p.centerX, y: p.lifelineTop))
            context.addLine(to: CGPoint(x: p.centerX, y: p.lifelineBottom))
            context.strokePath()
            context.restoreGState()
        }

        // Message arrows, stacked top to bottom.
        let shaft = theme.ink.withAlphaComponent(0.55)
        for arrow in layout.arrows {
            if arrow.isSelf {
                let yTop = arrow.y
                let yBot = arrow.y + arrow.selfHeight
                context.saveGState()
                context.setStrokeColor(resolvedCGColor(shaft))
                context.setLineWidth(1.3)
                context.setLineJoin(.round)
                context.beginPath()
                context.move(to: CGPoint(x: arrow.fromX, y: yTop))
                context.addLine(to: CGPoint(x: arrow.toX, y: yTop))
                context.addLine(to: CGPoint(x: arrow.toX, y: yBot))
                context.addLine(to: CGPoint(x: arrow.fromX + 5, y: yBot))
                context.strokePath()
                context.restoreGState()
                drawArrowhead(at: CGPoint(x: arrow.fromX, y: yBot),
                              from: CGPoint(x: arrow.toX, y: yBot),
                              color: shaft, canvas: theme.canvas, in: context)
                if !arrow.label.isEmpty {
                    drawTextLeft(arrow.label, at: CGPoint(x: arrow.toX + 6, y: (yTop + yBot) / 2),
                                 size: 10, color: theme.secondaryTextColor, in: context)
                }
            } else {
                context.saveGState()
                context.setStrokeColor(resolvedCGColor(shaft))
                context.setLineWidth(1.3)
                context.beginPath()
                context.move(to: CGPoint(x: arrow.fromX, y: arrow.y))
                context.addLine(to: CGPoint(x: arrow.toX, y: arrow.y))
                context.strokePath()
                context.restoreGState()
                drawArrowhead(at: CGPoint(x: arrow.toX, y: arrow.y),
                              from: CGPoint(x: arrow.fromX, y: arrow.y),
                              color: shaft, canvas: theme.canvas, in: context)
                if !arrow.label.isEmpty {
                    let mid = CGPoint(x: (arrow.fromX + arrow.toX) / 2, y: arrow.y - 9)
                    drawEdgeLabel(arrow.label, at: mid, theme: theme, in: context)
                }
            }
        }

        // Participant boxes on top so lifelines/arrows tuck under them.
        for p in layout.participants {
            let color = theme.categoricalColor(p.colorIndex)
            fillStrokeBox(p.frame, radius: 6,
                          fill: color.withAlphaComponent(0.14),
                          stroke: color.withAlphaComponent(0.6), in: context)
            if let s = p.stereotype {
                drawText(s, center: CGPoint(x: p.frame.midX, y: p.frame.minY + 12),
                         size: 8.5, color: theme.tertiaryTextColor, in: context)
                drawText(p.name, center: CGPoint(x: p.frame.midX, y: p.frame.minY + 25),
                         size: 12, weight: .medium, color: theme.ink, in: context)
            } else {
                drawText(p.name, center: CGPoint(x: p.frame.midX, y: p.frame.midY),
                         size: 12, weight: .medium, color: theme.ink, in: context)
            }
        }
    }
}
#endif
