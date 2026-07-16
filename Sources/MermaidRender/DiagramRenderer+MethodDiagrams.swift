#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
import MermaidLayout
#if canImport(AppKit) || canImport(UIKit)
import CoreGraphics
#endif

// Renderers for ishikawa, eventmodeling, and swimlane.

extension DiagramRenderer {

    /// Text on an opaque canvas chip — the fill that makes a scene label's
    /// `backed: true` an honest claim.
    static func drawChippedText(_ text: String, center: CGPoint, size: CGFloat,
                                weight: PlatformFont.Weight = .regular,
                                color: PlatformColor, theme: DiagramTheme,
                                in context: CGContext) {
        let measured = measure(text, size: size, weight: weight)
        let pad: CGFloat = 3
        context.setFillColor(resolvedCGColor(theme.canvas.withAlphaComponent(0.88)))
        context.fill(CGRect(x: center.x - measured.width / 2 - pad,
                            y: center.y - measured.height / 2 - pad,
                            width: measured.width + pad * 2,
                            height: measured.height + pad * 2))
        drawText(text, center: center, size: size, weight: weight, color: color, in: context)
    }

    // MARK: - Ishikawa (fishbone)

    static func draw(_ layout: IshikawaLayout, theme: DiagramTheme, in context: CGContext) {
        // Spine with an arrowhead into the head box.
        context.setStrokeColor(resolvedCGColor(theme.ink))
        context.setLineWidth(2)
        context.beginPath()
        context.move(to: layout.spineStart)
        context.addLine(to: layout.spineEnd)
        context.strokePath()
        drawArrowhead(at: layout.spineEnd, from: layout.spineStart,
                      color: theme.ink, canvas: theme.canvas, in: context)

        // Head box (the problem).
        context.setFillColor(resolvedCGColor(theme.accent.withAlphaComponent(0.16)))
        context.setStrokeColor(resolvedCGColor(theme.accent))
        context.setLineWidth(1.4)
        let head = CGPath(roundedRect: layout.headFrame, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(head)
        context.drawPath(using: .fillStroke)
        drawText(layout.problem,
                 center: CGPoint(x: layout.headFrame.midX, y: layout.headFrame.midY),
                 size: 12, weight: .semibold, color: theme.ink, in: context)

        for rib in layout.ribs {
            let tint = theme.categoricalColor(rib.colorIndex)
            context.setStrokeColor(resolvedCGColor(tint))
            context.setLineWidth(1.6)
            context.beginPath()
            context.move(to: rib.from)
            context.addLine(to: rib.to)
            context.strokePath()
            drawChippedText(rib.label, center: rib.labelCenter, size: labelSize,
                            weight: .semibold, color: theme.ink, theme: theme, in: context)
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            for twig in rib.twigs {
                context.beginPath()
                context.move(to: twig.from)
                context.addLine(to: twig.to)
                context.strokePath()
                drawChippedText(twig.label, center: twig.labelCenter, size: labelSize,
                                color: theme.secondaryTextColor, theme: theme, in: context)
            }
        }
    }

    // MARK: - Event modeling

    static func draw(_ layout: EventModelingLayout, theme: DiagramTheme, in context: CGContext) {
        for (index, lane) in layout.lanes.enumerated() {
            if index % 2 == 1 {
                context.setFillColor(resolvedCGColor(theme.hairline.withAlphaComponent(0.05)))
                context.fill(lane.band)
            }
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            context.stroke(lane.band)
            drawTextLeft(lane.name,
                         at: CGPoint(x: lane.band.minX + 6, y: lane.band.minY + 10),
                         size: 9, weight: .semibold, color: theme.tertiaryTextColor, in: context)
        }
        context.setStrokeColor(resolvedCGColor(theme.secondaryTextColor.withAlphaComponent(0.6)))
        context.setLineWidth(1.2)
        for connector in layout.connectors {
            guard connector.count >= 2 else { continue }
            context.beginPath()
            context.move(to: connector[0])
            for point in connector.dropFirst() { context.addLine(to: point) }
            context.strokePath()
            drawArrowhead(at: connector[connector.count - 1],
                          from: connector[connector.count - 2],
                          color: theme.secondaryTextColor.withAlphaComponent(0.6),
                          canvas: theme.canvas, in: context)
        }
        for frame in layout.frames {
            let tint = theme.categoricalColor(frame.colorIndex)
            context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.22)))
            context.setStrokeColor(resolvedCGColor(tint))
            context.setLineWidth(1.2)
            let path = CGPath(roundedRect: frame.frame, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(path)
            context.drawPath(using: .fillStroke)
            drawText(frame.entity,
                     center: CGPoint(x: frame.frame.midX, y: frame.frame.midY),
                     size: labelSize, color: theme.ink, in: context)
        }
    }

    // MARK: - Swimlane

    static func draw(_ layout: SwimlaneLayout, theme: DiagramTheme, in context: CGContext) {
        for (index, lane) in layout.lanes.enumerated() {
            let tint = theme.categoricalColor(index)
            context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.07)))
            context.fill(lane.band)
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            context.stroke(lane.band)
            drawTextRotated(lane.label,
                            center: CGPoint(x: lane.band.minX + 12, y: lane.band.midY),
                            size: 10, weight: .semibold,
                            color: theme.secondaryTextColor, in: context)
        }
        for edge in layout.edges {
            context.setStrokeColor(resolvedCGColor(theme.secondaryTextColor.withAlphaComponent(0.75)))
            context.setLineWidth(1.2)
            if edge.dashed { context.setLineDash(phase: 0, lengths: [4, 3]) }
            context.beginPath()
            context.move(to: edge.points[0])
            for point in edge.points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            if edge.points.count >= 2 {
                drawArrowhead(at: edge.points[edge.points.count - 1],
                              from: edge.points[edge.points.count - 2],
                              color: theme.secondaryTextColor.withAlphaComponent(0.75),
                              canvas: theme.canvas, in: context)
            }
            if let label = edge.label, let at = edge.labelCenter {
                drawEdgeLabel(label, at: at, theme: theme, in: context)
            }
        }
        for node in layout.nodes {
            drawFlowchartShape(node.shape, in: node.frame, theme: theme, context: context)
            drawText(node.label,
                     center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                     size: 12, color: theme.ink, in: context)
        }
    }

    /// Shared flowchart-family node shapes (subset used by swimlanes).
    private static func drawFlowchartShape(_ shape: Flowchart.NodeShape, in frame: CGRect,
                                           theme: DiagramTheme, context: CGContext) {
        context.setFillColor(resolvedCGColor(theme.accent.withAlphaComponent(0.10)))
        context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.75)))
        context.setLineWidth(1.2)
        switch shape {
        case .diamond:
            context.beginPath()
            context.move(to: CGPoint(x: frame.midX, y: frame.minY))
            context.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
            context.addLine(to: CGPoint(x: frame.midX, y: frame.maxY))
            context.addLine(to: CGPoint(x: frame.minX, y: frame.midY))
            context.closePath()
            context.drawPath(using: .fillStroke)
        case .circle:
            context.addEllipse(in: frame)
            context.drawPath(using: .fillStroke)
        case .stadium:
            let path = CGPath(roundedRect: frame, cornerWidth: frame.height / 2,
                              cornerHeight: frame.height / 2, transform: nil)
            context.addPath(path)
            context.drawPath(using: .fillStroke)
        case .rounded:
            let path = CGPath(roundedRect: frame, cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(path)
            context.drawPath(using: .fillStroke)
        default:
            let path = CGPath(roundedRect: frame, cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(path)
            context.drawPath(using: .fillStroke)
        }
    }
}
#endif
