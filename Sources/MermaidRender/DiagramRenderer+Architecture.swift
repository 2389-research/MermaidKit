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

    static func draw(_ layout: ArchitectureLayout, theme: DiagramTheme, in context: CGContext) {
        // Group containers first (behind everything).
        for group in layout.groups {
            let tint = theme.categoricalColor(group.colorIndex)
            fillStrokeBox(group.frame, radius: 8,
                          fill: tint.withAlphaComponent(theme.prefersDark ? 0.12 : 0.08),
                          stroke: tint.withAlphaComponent(0.55), in: context)
            if !group.label.isEmpty {
                var origin = group.titleOrigin
                if !group.icon.isEmpty {
                    drawTextLeft(group.icon, at: origin, size: 9,
                                 color: theme.tertiaryTextColor, in: context)
                    origin.x += measure(group.icon, size: 9).width + 6
                }
                drawTextLeft(group.label, at: origin, size: 11, weight: .semibold,
                             color: theme.ink, in: context)
            }
        }

        // Edges beneath the service boxes so wires tuck under the nodes.
        for edge in layout.edges {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.45)))
            context.setLineWidth(1.25)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            strokePolyline(edge.points, in: context)
            context.restoreGState()
            if edge.arrow, edge.points.count >= 2 {
                drawArrowhead(at: edge.points[edge.points.count - 1],
                              from: edge.points[edge.points.count - 2],
                              color: theme.ink.withAlphaComponent(0.55),
                              canvas: theme.canvas, in: context)
            }
        }

        // Service boxes / junctions on top.
        for svc in layout.services {
            let tint = theme.categoricalColor(svc.colorIndex)
            if svc.isJunction {
                let f = svc.frame
                context.saveGState()
                context.setFillColor(resolvedCGColor(theme.canvas))
                context.fillEllipse(in: f)
                context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.55)))
                context.setLineWidth(1.25)
                context.strokeEllipse(in: f.insetBy(dx: 0.75, dy: 0.75))
                context.setFillColor(resolvedCGColor(theme.ink.withAlphaComponent(0.55)))
                context.fillEllipse(in: f.insetBy(dx: f.width * 0.32, dy: f.height * 0.32))
                context.restoreGState()
                continue
            }

            fillStrokeBox(svc.frame, radius: 6,
                          fill: tint.withAlphaComponent(theme.prefersDark ? 0.22 : 0.14),
                          stroke: tint.withAlphaComponent(0.65), in: context)

            let f = svc.frame
            if svc.icon.isEmpty {
                drawText(svc.label, center: CGPoint(x: f.midX, y: f.midY), size: 11.5,
                         weight: .medium, color: theme.ink, in: context)
            } else {
                drawText(svc.label, center: CGPoint(x: f.midX, y: f.midY - 5), size: 11.5,
                         weight: .medium, color: theme.ink, in: context)
                drawText(svc.icon, center: CGPoint(x: f.midX, y: f.maxY - 9), size: 8.5,
                         color: theme.tertiaryTextColor, in: context)
            }
        }
    }
}
#endif
