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

    static func draw(_ layout: ERLayout, theme: DiagramTheme, in context: CGContext) {
        let stroke = theme.ink.withAlphaComponent(0.35)
        let hairline = theme.ink.withAlphaComponent(0.18)
        let fill = theme.accent.withAlphaComponent(0.06)

        // Batch shafts by dash style so crossing edges don't stack alpha.
        strokeEdgeShafts(layout.edges.map { ($0.points, !$0.identifying) }, color: stroke, in: context)
        var placedLabels: [CGRect] = []
        let nodeObstacles = layout.boxes.map(\.frame)
        let allEdgeRects = layout.edges.map { edgeSegmentRects($0.points) }
        for (i, edge) in layout.edges.enumerated() {
            let fromApproach = edge.points.count > 1 ? edge.points[1] : edge.end
            let toApproach = edge.points.count > 1 ? edge.points[edge.points.count - 2] : edge.start
            drawCardinality(edge.fromCard, at: edge.start, from: fromApproach, color: stroke, in: context)
            drawCardinality(edge.toCard, at: edge.end, from: toApproach, color: stroke, in: context)

            if !edge.label.isEmpty {
                var obstacles = nodeObstacles
                for (j, rects) in allEdgeRects.enumerated() where j != i { obstacles += rects }
                let at = edge.labelAnchor
                    ?? labelAnchor(for: edge.points, label: edge.label, bounds: layout.size, obstacles: obstacles, placed: &placedLabels)
                if edge.labelAnchor != nil {
                    let sz = measure(edge.label, size: labelSize)
                    placedLabels.append(CGRect(x: at.x - sz.width / 2, y: at.y - sz.height / 2, width: sz.width, height: sz.height))
                }
                drawEdgeLabel(edge.label, at: at, theme: theme, in: context)
            }
        }

        for box in layout.boxes {
            fillStrokeBox(box.frame, radius: 4, fill: fill, stroke: stroke, in: context)

            drawText(box.name,
                     center: CGPoint(x: box.frame.midX, y: box.frame.minY + box.nameHeight / 2),
                     size: 12, weight: .semibold, color: theme.ink, in: context)

            if !box.attributes.isEmpty {
                var rowY = box.frame.minY + box.nameHeight
                strokeHLine(y: rowY, from: box.frame.minX, to: box.frame.maxX, color: hairline, in: context)

                rowY += 5
                let typeX = box.frame.minX + 12
                for attribute in box.attributes {
                    let center = rowY + box.rowHeight / 2
                    drawTextLeft(attribute.type, at: CGPoint(x: typeX, y: center),
                                 size: 10.5, color: theme.secondaryTextColor, in: context)
                    let typeWidth = measure(attribute.type, size: 10.5).width
                    drawTextLeft(attribute.name, at: CGPoint(x: typeX + typeWidth + 8, y: center),
                                 size: 10.5, weight: .medium, color: theme.ink, in: context)
                    rowY += box.rowHeight
                }
            }
        }
    }

    /// Crow's-foot notation drawn along the edge at `end`, oriented away
    /// from `other`: ticks for "one", a circle for "zero", three prongs
    /// for "many".
    static func drawCardinality(
        _ card: ERDiagram.Cardinality, at end: CGPoint, from other: CGPoint,
        color: PlatformColor, in context: CGContext
    ) {
        let angle = atan2(other.y - end.y, other.x - end.x) // pointing inward (up the line)
        func p(out: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(
                x: end.x + out * cos(angle) - side * sin(angle),
                y: end.y + out * sin(angle) + side * cos(angle)
            )
        }

        context.saveGState()
        context.setStrokeColor(resolvedCGColor(color))
        context.setLineWidth(1.2)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // A perpendicular "one" tick across the line at `out`.
        func tick(at out: CGFloat, half: CGFloat = 4.5) {
            context.beginPath()
            context.move(to: p(out: out, side: half))
            context.addLine(to: p(out: out, side: -half))
            context.strokePath()
        }
        // The "many" crow's foot: three prongs fanning from an apex up the line
        // out to the entity box — kept compact so it stays in proportion.
        func crowsFoot() {
            let apex = p(out: 11, side: 0)
            context.beginPath()
            for side in [CGFloat(5), 0, -5] {
                context.move(to: apex)
                context.addLine(to: p(out: 1, side: side))
            }
            context.strokePath()
        }
        // The "zero" circle centered on the line at `out`.
        func circle(at out: CGFloat) {
            let c = p(out: out, side: 0)
            context.beginPath()
            context.addEllipse(in: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
            context.strokePath()
        }

        switch card {
        case .one:        tick(at: 6); tick(at: 9.5)    // ‖  exactly one
        case .zeroOrOne:  tick(at: 11); circle(at: 5.5) // ○|  zero or one
        case .oneOrMore:  crowsFoot(); tick(at: 14)     // ‹|  one or many
        case .zeroOrMore: crowsFoot(); circle(at: 15)   // ‹○  zero or many
        }
        context.restoreGState()
    }
}
#endif
