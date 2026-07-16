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

    static func draw(_ layout: MindmapLayout, theme: DiagramTheme, in context: CGContext) {
        // Curved branch connectors, behind the nodes, tinted per branch. A
        // horizontal-tangent cubic gives the organic mindmap look.
        for edge in layout.edges {
            let dx = max((edge.to.x - edge.from.x) * 0.5, 8)
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(theme.categoricalColor(edge.colorIndex).withAlphaComponent(0.55)))
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: edge.from)
            context.addCurve(
                to: edge.to,
                control1: CGPoint(x: edge.from.x + dx, y: edge.from.y),
                control2: CGPoint(x: edge.to.x - dx, y: edge.to.y)
            )
            context.strokePath()
            context.restoreGState()
        }

        for node in layout.nodes {
            context.saveGState()
            if node.depth == 0 {
                // Root: a filled accent pill.
                context.setFillColor(resolvedCGColor(theme.accent))
                context.addPath(CGPath(roundedRect: node.frame, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.fillPath()
            } else {
                let tint = theme.categoricalColor(node.colorIndex)
                context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.16)))
                context.addPath(CGPath(roundedRect: node.frame, cornerWidth: 7, cornerHeight: 7, transform: nil))
                context.fillPath()
                context.setStrokeColor(resolvedCGColor(tint.withAlphaComponent(0.5)))
                context.setLineWidth(1)
                context.addPath(CGPath(roundedRect: node.frame.insetBy(dx: 0.5, dy: 0.5),
                                       cornerWidth: 7, cornerHeight: 7, transform: nil))
                context.strokePath()
            }
            context.restoreGState()

            let color = node.depth == 0 ? PlatformColor.white : theme.ink
            drawText(node.label, center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                     size: labelSize, weight: node.depth == 0 ? .semibold : .regular,
                     color: color, in: context)
        }
    }
}
#endif
