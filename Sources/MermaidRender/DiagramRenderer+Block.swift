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

    static func draw(_ layout: BlockLayout, theme: DiagramTheme, in context: CGContext) {
        // Blocks: subtle categorical tint per row, hairline border, ink label.
        for node in layout.nodes where node.shape != .space {
            let tint = theme.categoricalColor(node.colorIndex)
            let fill = tint.withAlphaComponent(theme.prefersDark ? 0.22 : 0.13)
            let stroke = tint.withAlphaComponent(0.6)

            switch node.shape {
            case .circle:
                let diameter = min(node.frame.width, node.frame.height)
                let r = CGRect(x: node.frame.midX - diameter / 2,
                               y: node.frame.midY - diameter / 2,
                               width: diameter, height: diameter)
                context.saveGState()
                context.setFillColor(resolvedCGColor(fill))
                context.setStrokeColor(resolvedCGColor(stroke))
                context.setLineWidth(1)
                context.fillEllipse(in: r)
                context.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
                context.restoreGState()
            case .rounded:
                fillStrokeBox(node.frame, radius: min(node.frame.height / 2, 16),
                              fill: fill, stroke: stroke, in: context)
            default:
                fillStrokeBox(node.frame, radius: 6, fill: fill, stroke: stroke, in: context)
            }

            drawText(node.label,
                     center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                     size: 12, weight: .medium, color: theme.ink, in: context)
        }

        // Edges: hairline orthogonal shafts with filled arrowheads.
        let shaftColor = theme.ink.withAlphaComponent(0.55)
        for edge in layout.edges {
            guard edge.points.count >= 2 else { continue }
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(shaftColor))
            context.setLineWidth(1.5)
            context.setLineJoin(.round)
            strokePolyline(edge.points, in: context)
            context.restoreGState()

            let tip = edge.points[edge.points.count - 1]
            let from = edge.points[edge.points.count - 2]
            drawArrowhead(at: tip, from: from,
                          color: theme.ink.withAlphaComponent(0.7),
                          canvas: theme.canvas, in: context)
        }

        // Edge labels last so their canvas pad sits over the shafts.
        for edge in layout.edges {
            guard let label = edge.label, !label.isEmpty, edge.points.count >= 2 else { continue }
            drawEdgeLabel(label, at: polylineMidpoint(edge.points), theme: theme, in: context)
        }
    }
}
#endif
