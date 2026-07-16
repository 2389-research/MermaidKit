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

    static func draw(_ layout: FlowchartLayout, theme: DiagramTheme, in context: CGContext) {
        let stroke = theme.ink.withAlphaComponent(0.35)
        let fill = theme.accent.withAlphaComponent(0.06)

        // Subgraph group boxes first — backdrops behind every wire and node.
        // A deeper box is tinted a touch stronger so nested groups read apart.
        for container in layout.containers.sorted(by: { $0.depth < $1.depth }) {
            let boxFill = theme.ink.withAlphaComponent(0.04 + 0.03 * CGFloat(min(container.depth, 3)))
            let boxStroke = theme.ink.withAlphaComponent(0.28)
            let path = CGPath(roundedRect: container.frame, cornerWidth: 6, cornerHeight: 6, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.setFillColor(resolvedCGColor(boxFill))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(resolvedCGColor(boxStroke))
            context.setLineWidth(1)
            context.strokePath()
            context.restoreGState()
            if !container.label.isEmpty {
                drawText(container.label,
                         center: CGPoint(x: container.frame.midX, y: container.frame.minY + 11),
                         size: 11, weight: .semibold,
                         color: theme.ink.withAlphaComponent(0.75), in: context)
            }
        }

        // Batch edge shafts by dash style and stroke each group in a single
        // pass, so crossing edges composite as one region instead of stacking
        // their translucent strokes into darker seams. Arrowheads and labels
        // draw on top afterward.
        var solidShafts: [[CGPoint]] = []
        var dashedShafts: [[CGPoint]] = []
        var arrows: [(tip: CGPoint, from: CGPoint)] = []
        for edge in layout.edges {
            // Leave a small gap between an arrowhead and the box it points at.
            var points = edge.points
            let approach = points.count > 1 ? points[points.count - 2] : edge.start
            if edge.hasArrow, points.count >= 2 {
                let end = points[points.count - 1]
                let dx = end.x - approach.x, dy = end.y - approach.y
                let len = max(hypot(dx, dy), 0.001)
                let gap: CGFloat = 3
                points[points.count - 1] = CGPoint(x: end.x - dx / len * gap, y: end.y - dy / len * gap)
                arrows.append((points[points.count - 1], approach))
            }
            if edge.backArrow, points.count >= 2 {
                // Bidirectional: a second head at the start, pointing back.
                arrows.append((points[0], points[1]))
            }
            if edge.dashed { dashedShafts.append(points) } else { solidShafts.append(points) }
        }

        strokeEdgeShafts(
            solidShafts.map { ($0, false) } + dashedShafts.map { ($0, true) },
            color: stroke, in: context)

        for arrow in arrows {
            drawArrowhead(at: arrow.tip, from: arrow.from, color: stroke, canvas: theme.canvas, in: context)
        }
        for edge in layout.edges {
            guard let label = edge.label, !label.isEmpty else { continue }
            let point = edge.labelPoint ?? polylineMidpoint(edge.points)
            drawEdgeLabel(label, at: point, theme: theme, in: context)
        }

        for node in layout.nodes {
            context.saveGState()
            context.setFillColor(resolvedCGColor(fill))
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1)

            // State-diagram terminals draw specially: a filled dot and a
            // ringed dot, in ink rather than the accent tint.
            if node.shape == .stateStart {
                drawStartTerminal(node.frame, color: theme.ink.withAlphaComponent(0.75), in: context)
                context.restoreGState()
                continue
            }
            if node.shape == .stateEnd {
                drawEndTerminal(node.frame, color: theme.ink.withAlphaComponent(0.75), in: context)
                context.restoreGState()
                continue
            }
            if node.shape == .cylinder {
                context.restoreGState()
                let capH = drawCylinder(node.frame, fill: fill, stroke: stroke, in: context)
                // Center the label in the body, below the top cap.
                drawText(node.label, center: CGPoint(x: node.frame.midX, y: node.frame.midY + capH / 2),
                         size: 12, weight: .medium, color: theme.ink, in: context)
                continue
            }

            let path: CGPath
            switch node.shape {
            case .rectangle:
                path = CGPath(roundedRect: node.frame, cornerWidth: 4, cornerHeight: 4, transform: nil)
            case .rounded:
                path = CGPath(roundedRect: node.frame, cornerWidth: 8, cornerHeight: 8, transform: nil)
            case .stadium:
                let r = node.frame.height / 2
                path = CGPath(roundedRect: node.frame, cornerWidth: r, cornerHeight: r, transform: nil)
            case .circle, .stateStart, .stateEnd: // terminals handled above
                path = CGPath(ellipseIn: node.frame, transform: nil)
            case .diamond:
                path = diamondPath(node.frame)
            case .cylinder: // handled above with a continue; keep exhaustive
                path = CGPath(roundedRect: node.frame, cornerWidth: 4, cornerHeight: 4, transform: nil)
            }
            context.restoreGState()
            fillStrokeShape(path, fill: fill, stroke: stroke, in: context)

            drawText(node.label, center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                     size: 12, weight: .medium, color: theme.ink, in: context)
        }
    }
}
#endif
