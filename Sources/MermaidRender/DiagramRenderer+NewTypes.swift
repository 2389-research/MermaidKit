#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
import MermaidLayout
#if canImport(AppKit) || canImport(UIKit)
import CoreGraphics
#endif

// Renderers for the v0.5.0 diagram types: treeView, venn, cynefin, wardley.

extension DiagramRenderer {

    // MARK: - Tree view

    static func draw(_ layout: TreeViewLayout, theme: DiagramTheme, in context: CGContext) {
        // Guide lines first, under everything.
        context.setStrokeColor(resolvedCGColor(theme.hairline))
        context.setLineWidth(1)
        for connector in layout.connectors {
            guard connector.count >= 2 else { continue }
            context.beginPath()
            context.move(to: connector[0])
            for point in connector.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
        for row in layout.rows {
            drawTreeGlyph(row: row, theme: theme, in: context)
            drawText(row.label,
                     center: CGPoint(x: row.textOrigin.x + measure(row.label, size: 12).width / 2,
                                     y: row.textOrigin.y),
                     size: 12, weight: row.isDirectory ? .semibold : .regular,
                     color: theme.ink, in: context)
            if let description = row.description, let at = row.descriptionOrigin {
                drawText(description,
                         center: CGPoint(x: at.x + measure(description, size: labelSize).width / 2, y: at.y),
                         size: labelSize, color: theme.tertiaryTextColor, in: context)
            }
        }
    }

    private static func drawTreeGlyph(row: TreeViewLayout.Row, theme: DiagramTheme, in context: CGContext) {
        let f = row.glyphFrame
        context.saveGState()
        if row.isDirectory {
            // Folder: body + top tab, accent-tinted.
            let tint = theme.accent
            context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.28)))
            context.setStrokeColor(resolvedCGColor(tint))
            let tab = CGRect(x: f.minX, y: f.minY + 1, width: f.width * 0.45, height: 3)
            let body = CGRect(x: f.minX, y: f.minY + 3, width: f.width, height: f.height - 4)
            context.addPath(CGPath(roundedRect: tab, cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.addPath(CGPath(roundedRect: body, cornerWidth: 2, cornerHeight: 2, transform: nil))
            context.drawPath(using: .fillStroke)
        } else {
            // File: rect with a folded corner.
            let fold: CGFloat = 4
            context.setFillColor(resolvedCGColor(theme.canvas))
            context.setStrokeColor(resolvedCGColor(theme.secondaryTextColor))
            context.beginPath()
            context.move(to: CGPoint(x: f.minX + 1, y: f.minY))
            context.addLine(to: CGPoint(x: f.maxX - fold, y: f.minY))
            context.addLine(to: CGPoint(x: f.maxX - 1, y: f.minY + fold))
            context.addLine(to: CGPoint(x: f.maxX - 1, y: f.maxY))
            context.addLine(to: CGPoint(x: f.minX + 1, y: f.maxY))
            context.closePath()
            context.drawPath(using: .fillStroke)
            context.beginPath()
            context.move(to: CGPoint(x: f.maxX - fold, y: f.minY))
            context.addLine(to: CGPoint(x: f.maxX - fold, y: f.minY + fold))
            context.addLine(to: CGPoint(x: f.maxX - 1, y: f.minY + fold))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Venn

    static func draw(_ layout: VennLayout, theme: DiagramTheme, in context: CGContext) {
        // Translucent fills first (overlaps blend), then rims, then labels.
        for circle in layout.circles {
            let rect = CGRect(x: circle.center.x - circle.radius, y: circle.center.y - circle.radius,
                              width: circle.radius * 2, height: circle.radius * 2)
            context.setFillColor(resolvedCGColor(
                theme.categoricalColor(circle.colorIndex).withAlphaComponent(0.26)))
            context.fillEllipse(in: rect)
        }
        for circle in layout.circles {
            let rect = CGRect(x: circle.center.x - circle.radius, y: circle.center.y - circle.radius,
                              width: circle.radius * 2, height: circle.radius * 2)
            context.setStrokeColor(resolvedCGColor(theme.categoricalColor(circle.colorIndex)))
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect)
        }
        for circle in layout.circles {
            guard let label = circle.label, !label.isEmpty else { continue }
            drawLabelChip(label, center: circle.labelCenter, weight: .semibold,
                          color: theme.ink, theme: theme, in: context)
        }
        for region in layout.regionLabels {
            drawLabelChip(region.text, center: region.center, weight: .regular,
                          color: theme.secondaryTextColor, theme: theme, in: context)
        }
    }

    /// Text on an opaque canvas chip (the scene declares these labels
    /// `backed` on the strength of this fill).
    private static func drawLabelChip(_ text: String, center: CGPoint,
                                      weight: PlatformFont.Weight, color: PlatformColor,
                                      theme: DiagramTheme, in context: CGContext) {
        let size = measure(text, size: labelSize)
        let pad: CGFloat = 3
        context.setFillColor(resolvedCGColor(theme.canvas.withAlphaComponent(0.88)))
        context.fill(CGRect(x: center.x - size.width / 2 - pad, y: center.y - size.height / 2 - pad,
                            width: size.width + pad * 2, height: size.height + pad * 2))
        drawText(text, center: center, size: labelSize, weight: weight, color: color, in: context)
    }

    // MARK: - Cynefin

    static func draw(_ layout: CynefinLayout, theme: DiagramTheme, in context: CGContext) {
        if let title = layout.title {
            drawText(title, center: CGPoint(x: layout.size.width / 2, y: 16),
                     size: 13, weight: .semibold, color: theme.ink, in: context)
        }
        for quadrant in layout.quadrants {
            let tint = theme.categoricalColor(quadrant.colorIndex)
            context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.14)))
            context.fill(quadrant.frame)
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            context.stroke(quadrant.frame)
            drawText(quadrant.name,
                     center: CGPoint(x: quadrant.frame.midX, y: quadrant.frame.minY + 18),
                     size: 12, weight: .semibold, color: theme.ink, in: context)
            drawText(quadrant.heuristic,
                     center: CGPoint(x: quadrant.frame.midX, y: quadrant.frame.minY + 34),
                     size: 9, color: theme.tertiaryTextColor, in: context)
            for item in quadrant.items {
                drawText(item.text, center: item.center, size: labelSize,
                         color: theme.secondaryTextColor, in: context)
            }
        }
        if let center = layout.center {
            context.setFillColor(resolvedCGColor(theme.canvas))
            context.fillEllipse(in: center.frame)
            context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.5)))
            context.setLineWidth(1.2)
            context.strokeEllipse(in: center.frame)
            drawText(center.name,
                     center: CGPoint(x: center.frame.midX, y: center.frame.midY - 10),
                     size: 11, weight: .semibold, color: theme.ink, in: context)
            drawText(center.heuristic,
                     center: CGPoint(x: center.frame.midX, y: center.frame.midY + 5),
                     size: 8.5, color: theme.tertiaryTextColor, in: context)
            for item in center.items {
                drawText(item.text, center: item.center, size: 8.5,
                         color: theme.secondaryTextColor, in: context)
            }
        }
        for transition in layout.transitions {
            context.setStrokeColor(resolvedCGColor(theme.accent))
            context.setLineWidth(1.4)
            context.beginPath()
            context.move(to: transition.from)
            context.addLine(to: transition.to)
            context.strokePath()
            drawArrowhead(at: transition.to, from: transition.from,
                          color: theme.accent, canvas: theme.canvas, in: context)
            if let label = transition.label {
                drawLabelChip(label, center: transition.labelCenter, weight: .regular,
                              color: theme.secondaryTextColor, theme: theme, in: context)
            }
        }
    }

    // MARK: - Wardley

    static func draw(_ layout: WardleyLayout, theme: DiagramTheme, in context: CGContext) {
        if let title = layout.title {
            drawText(title, center: CGPoint(x: layout.size.width / 2, y: 16),
                     size: 13, weight: .semibold, color: theme.ink, in: context)
        }
        // Plot frame + evolution band boundaries.
        context.setStrokeColor(resolvedCGColor(theme.hairline))
        context.setLineWidth(1)
        context.stroke(layout.plotFrame)
        for band in layout.bands.dropFirst() {
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.beginPath()
            context.move(to: CGPoint(x: band.x, y: layout.plotFrame.minY))
            context.addLine(to: CGPoint(x: band.x, y: layout.plotFrame.maxY))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
        for band in layout.bands {
            drawTextLeft(band.name,
                         at: CGPoint(x: band.x + 4, y: layout.plotFrame.maxY + 10),
                         size: 9, weight: .regular, color: theme.tertiaryTextColor, in: context)
        }
        // Y axis: value chain.
        drawTextRotated("Value Chain",
                        center: CGPoint(x: layout.plotFrame.minX - 12, y: layout.plotFrame.midY),
                        size: 9, color: theme.tertiaryTextColor, in: context)

        // Links under dots.
        for link in layout.links {
            context.setStrokeColor(resolvedCGColor(
                link.isFlow ? theme.accent : theme.secondaryTextColor.withAlphaComponent(0.55)))
            context.setLineWidth(link.isFlow ? 2 : 1)
            context.beginPath()
            context.move(to: link.from)
            context.addLine(to: link.to)
            context.strokePath()
        }
        // Evolve arrows: dashed accent to the future position + hollow dot.
        for evolve in layout.evolves {
            context.setStrokeColor(resolvedCGColor(theme.accent))
            context.setLineWidth(1.4)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.beginPath()
            context.move(to: evolve.from)
            context.addLine(to: evolve.to)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            drawArrowhead(at: evolve.to, from: evolve.from, color: theme.accent, canvas: theme.canvas, in: context)
            context.setFillColor(resolvedCGColor(theme.canvas))
            context.setStrokeColor(resolvedCGColor(theme.accent))
            context.fillEllipse(in: CGRect(x: evolve.to.x - 4, y: evolve.to.y - 4, width: 8, height: 8))
            context.strokeEllipse(in: CGRect(x: evolve.to.x - 4, y: evolve.to.y - 4, width: 8, height: 8))
        }
        // Component dots + labels.
        for node in layout.nodes {
            let dot = CGRect(x: node.center.x - 5, y: node.center.y - 5, width: 10, height: 10)
            if node.isAnchor {
                context.setFillColor(resolvedCGColor(theme.canvas))
                context.setStrokeColor(resolvedCGColor(theme.ink))
                context.setLineWidth(1.4)
                context.fillEllipse(in: dot)
                context.strokeEllipse(in: dot)
            } else {
                context.setFillColor(resolvedCGColor(theme.accent))
                context.fillEllipse(in: dot)
            }
            if node.inertia {
                context.setStrokeColor(resolvedCGColor(theme.ink))
                context.setLineWidth(3)
                context.beginPath()
                context.move(to: CGPoint(x: node.center.x + 9, y: node.center.y - 7))
                context.addLine(to: CGPoint(x: node.center.x + 9, y: node.center.y + 7))
                context.strokePath()
            }
            let text = node.decorator.map { "\(node.name) (\($0))" } ?? node.name
            let size = measure(node.name, size: labelSize)
            context.setFillColor(resolvedCGColor(theme.canvas.withAlphaComponent(0.88)))
            context.fill(node.labelFrame.insetBy(dx: -2, dy: -1))
            drawText(text,
                     center: CGPoint(x: node.labelFrame.minX + size.width / 2,
                                     y: node.labelFrame.midY),
                     size: labelSize,
                     weight: node.isAnchor ? .semibold : .regular,
                     color: theme.ink, in: context)
        }
        for note in layout.notes {
            drawChippedText(note.text, center: note.center, size: 9,
                            color: theme.tertiaryTextColor, theme: theme, in: context)
        }
    }
}
#endif
