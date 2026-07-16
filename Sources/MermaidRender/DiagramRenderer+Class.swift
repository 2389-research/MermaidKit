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

    static func draw(_ layout: ClassLayout, theme: DiagramTheme, in context: CGContext) {
        let stroke = theme.ink.withAlphaComponent(0.35)
        let hairline = theme.ink.withAlphaComponent(0.18)
        let fill = theme.accent.withAlphaComponent(0.06)

        // Batch shafts by dash style so crossing edges don't stack alpha.
        strokeEdgeShafts(layout.edges.map { ($0.points, $0.kind.dashed) }, color: stroke, in: context)
        var placedLabels: [CGRect] = []
        let nodeObstacles = layout.boxes.map(\.frame)
        let allEdgeRects = layout.edges.map { edgeSegmentRects($0.points) }
        for (i, edge) in layout.edges.enumerated() {
            let approach = edge.points.count > 1 ? edge.points[edge.points.count - 2] : edge.start
            drawRelationMarker(edge.kind, at: edge.end, from: approach,
                               stroke: stroke, canvas: theme.canvas, in: context)
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

        for box in layout.boxes {
            fillStrokeBox(box.frame, radius: 4, fill: fill, stroke: stroke, in: context)

            drawText(box.name,
                     center: CGPoint(x: box.frame.midX, y: box.frame.minY + box.nameHeight / 2),
                     size: 12, weight: .semibold, color: theme.ink, in: context)

            var rowY = box.frame.minY + box.nameHeight
            func separator() {
                strokeHLine(y: rowY, from: box.frame.minX, to: box.frame.maxX, color: hairline, in: context)
            }
            let textX = box.frame.minX + 12
            if !box.attributes.isEmpty {
                separator()
                rowY += 5
                for attribute in box.attributes {
                    drawTextLeft(attribute, at: CGPoint(x: textX, y: rowY + box.rowHeight / 2),
                                 size: 10.5, color: theme.secondaryTextColor, in: context)
                    rowY += box.rowHeight
                }
            }
            if !box.methods.isEmpty {
                separator()
                rowY += 5
                for method in box.methods {
                    drawTextLeft(method, at: CGPoint(x: textX, y: rowY + box.rowHeight / 2),
                                 size: 10.5, color: theme.secondaryTextColor, in: context)
                    rowY += box.rowHeight
                }
            }
        }
    }

    static func drawRelationMarker(
        _ kind: ClassDiagram.RelationKind, at end: CGPoint, from origin: CGPoint,
        stroke: PlatformColor, canvas: PlatformColor, in context: CGContext
    ) {
        let angle = atan2(end.y - origin.y, end.x - origin.x)
        // Stand the marker off the box border by a hairline, the way the
        // flowchart arrowhead leaves a gap, so the whole glyph floats just
        // outside the node instead of straddling the border (where the box
        // outline, stroked afterward, overpaints the marker's near vertex).
        let standoff: CGFloat = 3
        let tip = CGPoint(x: end.x - standoff * cos(angle), y: end.y - standoff * sin(angle))
        func point(back: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(
                x: tip.x - back * cos(angle) - side * sin(angle),
                y: tip.y - back * sin(angle) + side * cos(angle)
            )
        }

        switch kind {
        case .inheritance, .realization:
            // Hollow triangle, canvas-filled so the line doesn't show through.
            context.saveGState()
            context.setFillColor(resolvedCGColor(canvas))
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1)
            context.beginPath()
            context.move(to: tip)
            context.addLine(to: point(back: 11, side: 6))
            context.addLine(to: point(back: 11, side: -6))
            context.closePath()
            context.drawPath(using: .fillStroke)
            context.restoreGState()
        case .composition, .aggregation:
            context.saveGState()
            context.setFillColor(resolvedCGColor(kind == .composition ? stroke : canvas))
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1)
            context.beginPath()
            context.move(to: tip)
            context.addLine(to: point(back: 7, side: 4.5))
            context.addLine(to: point(back: 14, side: 0))
            context.addLine(to: point(back: 7, side: -4.5))
            context.closePath()
            context.drawPath(using: .fillStroke)
            context.restoreGState()
        case .association, .dependency:
            drawArrowhead(at: tip, from: origin, color: stroke, canvas: canvas, in: context)
        case .link:
            break
        }
    }
}
#endif
