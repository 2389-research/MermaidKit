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

    static func draw(_ layout: StateLayout, theme: DiagramTheme, in context: CGContext) {
        let stroke = theme.ink.withAlphaComponent(0.35)
        let nodeFill = theme.accent.withAlphaComponent(0.06)
        let solid = theme.ink.withAlphaComponent(0.75)

        // Composite containers first, outermost → innermost so nested tints
        // stack; the title strip carries the composite's name.
        for container in layout.containers.sorted(by: { $0.depth < $1.depth }) {
            context.saveGState()
            context.addPath(CGPath(roundedRect: container.frame, cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.setFillColor(resolvedCGColor(theme.ink.withAlphaComponent(0.03)))
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1)
            context.drawPath(using: .fillStroke)
            drawText(container.label,
                     center: CGPoint(x: container.frame.midX, y: container.frame.minY + container.titleHeight / 2),
                     size: 11.5, weight: .semibold, color: theme.ink, in: context)
            let sepY = container.frame.minY + container.titleHeight
            context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.15)))
            context.beginPath()
            context.move(to: CGPoint(x: container.frame.minX, y: sepY))
            context.addLine(to: CGPoint(x: container.frame.maxX, y: sepY))
            context.strokePath()
            context.restoreGState()
        }

        // Transitions (including those flattened out of composites): batch the
        // shafts into one stroke so crossing lines don't stack their alpha.
        context.saveGState()
        context.setStrokeColor(resolvedCGColor(stroke))
        context.setLineWidth(1)
        context.beginPath()
        for edge in layout.edges { appendRoundedPolyline(edge.points, to: context) }
        context.strokePath()
        context.restoreGState()

        var placedLabels: [CGRect] = []
        let nodeObstacles = layout.nodes.map(\.frame)
        let allEdgeRects = layout.edges.map { edgeSegmentRects($0.points) }
        for (i, edge) in layout.edges.enumerated() {
            let approach = edge.points.count > 1 ? edge.points[edge.points.count - 2] : edge.start
            drawArrowhead(at: edge.end, from: approach, color: stroke, canvas: theme.canvas, in: context)
            if let label = edge.label, !label.isEmpty {
                var obstacles = nodeObstacles
                for (j, rects) in allEdgeRects.enumerated() where j != i { obstacles += rects }
                // Layout reserved space for this label (widened median dummy /
                // grown inter-layer gap) — draw exactly there. Scoring is only
                // the fallback for edges layout couldn't reserve for.
                let at = edge.labelAnchor
                    ?? labelAnchor(for: edge.points, label: label, bounds: layout.size, obstacles: obstacles, placed: &placedLabels)
                if edge.labelAnchor != nil {
                    let sz = measure(label, size: labelSize)
                    placedLabels.append(CGRect(x: at.x - sz.width / 2, y: at.y - sz.height / 2, width: sz.width, height: sz.height))
                }
                drawEdgeLabel(label, at: at, theme: theme, in: context)
            }
        }

        // Nodes on top so borders sit above the edge ends.
        for node in layout.nodes {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1)
            switch node.kind {
            case .start:
                drawStartTerminal(node.frame, color: solid, in: context)
            case .end:
                drawEndTerminal(node.frame, color: solid, in: context)
            case .choice:
                context.addPath(diamondPath(node.frame))
                context.setFillColor(resolvedCGColor(nodeFill))
                context.drawPath(using: .fillStroke)
            case .fork, .join:
                context.addPath(CGPath(roundedRect: node.frame, cornerWidth: 2, cornerHeight: 2, transform: nil))
                context.setFillColor(resolvedCGColor(theme.ink.withAlphaComponent(0.7)))
                context.fillPath()
            case .simple:
                context.addPath(CGPath(roundedRect: node.frame, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.setFillColor(resolvedCGColor(nodeFill))
                context.drawPath(using: .fillStroke)
                drawText(node.label, center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                         size: 12, weight: .medium, color: theme.ink, in: context)
            }
            context.restoreGState()
        }
    }

}
#endif
