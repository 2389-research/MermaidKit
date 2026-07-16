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

    /// Draws the arrow ending for a sequence head style: filled triangle,
    /// cross, open half-arrow, or nothing.
    private static func drawSequenceHead(
        _ head: SequenceDiagram.Message.ArrowHead,
        at tip: CGPoint, from origin: CGPoint,
        stroke: PlatformColor, theme: DiagramTheme, in context: CGContext
    ) {
        switch head {
        case .none:
            return
        case .filled, .both:
            drawArrowhead(at: tip, from: origin, color: stroke, canvas: theme.canvas, in: context)
        case .cross:
            let r: CGFloat = 4.5
            let inset: CGFloat = tip.x >= origin.x ? -3 : 3
            let cx = tip.x + inset
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1.6)
            context.beginPath()
            context.move(to: CGPoint(x: cx - r, y: tip.y - r))
            context.addLine(to: CGPoint(x: cx + r, y: tip.y + r))
            context.move(to: CGPoint(x: cx - r, y: tip.y + r))
            context.addLine(to: CGPoint(x: cx + r, y: tip.y - r))
            context.strokePath()
        case .open:
            let angle = atan2(tip.y - origin.y, tip.x - origin.x)
            let length: CGFloat = 9
            let spread: CGFloat = 0.5
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1.4)
            context.beginPath()
            context.move(to: CGPoint(x: tip.x - length * cos(angle - spread),
                                     y: tip.y - length * sin(angle - spread)))
            context.addLine(to: tip)
            context.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread),
                                        y: tip.y - length * sin(angle + spread)))
            context.strokePath()
        }
    }

    /// Small head glyphs for typed participants (database cylinder, queue,
    /// collections, and the UML robustness trio), centered above the label.
    private static func drawParticipantGlyph(
        _ kind: String, frame: CGRect, theme: DiagramTheme,
        stroke: PlatformColor, in context: CGContext
    ) {
        let cx = frame.midX
        let top = frame.minY + 2
        let fill = theme.accent.withAlphaComponent(0.10)
        context.setFillColor(resolvedCGColor(fill))
        context.setStrokeColor(resolvedCGColor(stroke))
        context.setLineWidth(1.2)
        switch kind {
        case "database":
            let body = CGRect(x: cx - 11, y: top + 3, width: 22, height: 18)
            context.addRect(body.insetBy(dx: 0, dy: 3))
            context.fillPath()
            context.strokeEllipse(in: CGRect(x: cx - 11, y: top, width: 22, height: 7))
            context.beginPath()
            context.move(to: CGPoint(x: cx - 11, y: top + 3.5))
            context.addLine(to: CGPoint(x: cx - 11, y: top + 21))
            context.move(to: CGPoint(x: cx + 11, y: top + 3.5))
            context.addLine(to: CGPoint(x: cx + 11, y: top + 21))
            context.strokePath()
            context.strokeEllipse(in: CGRect(x: cx - 11, y: top + 17, width: 22, height: 7))
        case "queue":
            context.strokeEllipse(in: CGRect(x: cx + 8, y: top + 4, width: 8, height: 16))
            context.beginPath()
            context.move(to: CGPoint(x: cx - 12, y: top + 4))
            context.addLine(to: CGPoint(x: cx + 12, y: top + 4))
            context.move(to: CGPoint(x: cx - 12, y: top + 20))
            context.addLine(to: CGPoint(x: cx + 12, y: top + 20))
            context.strokePath()
            context.addPath(CGPath(ellipseIn: CGRect(x: cx - 16, y: top + 4, width: 8, height: 16), transform: nil))
            context.drawPath(using: .fillStroke)
        case "collections":
            context.addRect(CGRect(x: cx - 8, y: top + 2, width: 18, height: 14))
            context.drawPath(using: .fillStroke)
            context.setFillColor(resolvedCGColor(theme.canvas))
            context.addRect(CGRect(x: cx - 12, y: top + 7, width: 18, height: 14))
            context.drawPath(using: .fillStroke)
        case "boundary":
            context.strokeEllipse(in: CGRect(x: cx - 8, y: top + 3, width: 18, height: 18))
            context.beginPath()
            context.move(to: CGPoint(x: cx - 14, y: top + 3))
            context.addLine(to: CGPoint(x: cx - 14, y: top + 21))
            context.move(to: CGPoint(x: cx - 14, y: top + 12))
            context.addLine(to: CGPoint(x: cx - 8, y: top + 12))
            context.strokePath()
        case "control":
            context.strokeEllipse(in: CGRect(x: cx - 9, y: top + 3, width: 18, height: 18))
            context.beginPath()
            context.move(to: CGPoint(x: cx - 2, y: top))
            context.addLine(to: CGPoint(x: cx + 3, y: top + 3))
            context.addLine(to: CGPoint(x: cx - 2, y: top + 6))
            context.strokePath()
        case "entity":
            context.addPath(CGPath(ellipseIn: CGRect(x: cx - 9, y: top + 2, width: 18, height: 18), transform: nil))
            context.drawPath(using: .fillStroke)
            context.beginPath()
            context.move(to: CGPoint(x: cx - 11, y: top + 22))
            context.addLine(to: CGPoint(x: cx + 11, y: top + 22))
            context.strokePath()
        default:
            break
        }
    }

    static func draw(_ layout: SequenceLayout, theme: DiagramTheme, in context: CGContext) {
        let stroke = theme.ink.withAlphaComponent(0.35)
        let hairline = theme.ink.withAlphaComponent(0.18)

        // Box bands first of all — group backgrounds under everything.
        for band in layout.boxBands {
            context.setFillColor(resolvedCGColor(
                theme.categoricalColor(band.colorIndex).withAlphaComponent(0.08)))
            context.fill(band.rect)
            context.setStrokeColor(resolvedCGColor(theme.hairline))
            context.setLineWidth(1)
            context.stroke(band.rect)
            if let label = band.label {
                drawText(label, center: CGPoint(x: band.rect.midX, y: band.rect.minY + 9),
                         size: 9, weight: .semibold, color: theme.tertiaryTextColor, in: context)
            }
        }

        // Fragment frames first — everything else draws on top of them.
        for frame in layout.frames {
            if frame.kind == "rect" {
                context.setFillColor(resolvedCGColor(theme.accent.withAlphaComponent(0.06)))
                context.fill(frame.rect)
                continue
            }
            context.setStrokeColor(resolvedCGColor(hairline))
            context.setLineWidth(1)
            context.stroke(frame.rect)
            // Kind tab (the classic dog-eared corner chip) + guard label.
            let kindSize = measure(frame.kind, size: 9)
            let tab = CGRect(x: frame.rect.minX, y: frame.rect.minY,
                             width: kindSize.width + 14, height: 15)
            context.setFillColor(resolvedCGColor(theme.hairline.withAlphaComponent(0.14)))
            context.beginPath()
            context.move(to: CGPoint(x: tab.minX, y: tab.minY))
            context.addLine(to: CGPoint(x: tab.maxX, y: tab.minY))
            context.addLine(to: CGPoint(x: tab.maxX - 5, y: tab.maxY))
            context.addLine(to: CGPoint(x: tab.minX, y: tab.maxY))
            context.closePath()
            context.fillPath()
            drawText(frame.kind, center: CGPoint(x: tab.minX + kindSize.width / 2 + 5, y: tab.midY),
                     size: 9, weight: .semibold, color: theme.secondaryTextColor, in: context)
            if let label = frame.label, !label.isEmpty {
                drawTextLeft("[\(label)]", at: CGPoint(x: tab.maxX + 6, y: tab.midY),
                             size: 9, color: theme.tertiaryTextColor, in: context)
            }
            for divider in frame.dividers {
                context.saveGState()
                context.setStrokeColor(resolvedCGColor(hairline))
                context.setLineDash(phase: 0, lengths: [4, 3])
                context.beginPath()
                context.move(to: CGPoint(x: frame.rect.minX, y: divider.y))
                context.addLine(to: CGPoint(x: frame.rect.maxX, y: divider.y))
                context.strokePath()
                context.restoreGState()
                if let label = divider.label, !label.isEmpty {
                    let size = measure("[\(label)]", size: 9)
                    context.setFillColor(resolvedCGColor(theme.canvas))
                    context.fill(CGRect(x: frame.rect.midX - size.width / 2 - 3, y: divider.y - 7,
                                        width: size.width + 6, height: 14))
                    drawText("[\(label)]", center: CGPoint(x: frame.rect.midX, y: divider.y),
                             size: 9, color: theme.tertiaryTextColor, in: context)
                }
            }
        }

        // Lifelines behind everything (per-head end for destroyed ones).
        for head in layout.heads {
            let end = head.lifelineEndY ?? layout.lifelineBottom
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(hairline))
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.beginPath()
            context.move(to: CGPoint(x: head.lifelineX, y: head.frame.maxY))
            context.addLine(to: CGPoint(x: head.lifelineX, y: end))
            context.strokePath()
            context.restoreGState()
            if head.showsDestroyCross {
                let r: CGFloat = 6
                context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.7)))
                context.setLineWidth(1.6)
                context.beginPath()
                context.move(to: CGPoint(x: head.lifelineX - r, y: end - r))
                context.addLine(to: CGPoint(x: head.lifelineX + r, y: end + r))
                context.move(to: CGPoint(x: head.lifelineX - r, y: end + r))
                context.addLine(to: CGPoint(x: head.lifelineX + r, y: end - r))
                context.strokePath()
            }
        }

        // Activation bars: on the lifeline, above it but under arrows; nested
        // bars offset rightward per depth.
        for bar in layout.bars {
            let rect = CGRect(x: bar.x - 4 + CGFloat(bar.depth) * 4, y: bar.top,
                              width: 8, height: max(bar.bottom - bar.top, 6))
            context.setFillColor(resolvedCGColor(theme.accent.withAlphaComponent(0.14)))
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil))
            context.drawPath(using: .fillStroke)
        }

        for head in layout.heads {
            if head.isActor {
                // Stick figure above the label: head circle, body, arms, legs.
                let cx = head.frame.midX
                let top = head.frame.minY
                context.setStrokeColor(resolvedCGColor(theme.ink.withAlphaComponent(0.75)))
                context.setLineWidth(1.4)
                context.strokeEllipse(in: CGRect(x: cx - 4, y: top, width: 8, height: 8))
                context.beginPath()
                context.move(to: CGPoint(x: cx, y: top + 8))
                context.addLine(to: CGPoint(x: cx, y: top + 17))          // body
                context.move(to: CGPoint(x: cx - 6, y: top + 11))
                context.addLine(to: CGPoint(x: cx + 6, y: top + 11))      // arms
                context.move(to: CGPoint(x: cx, y: top + 17))
                context.addLine(to: CGPoint(x: cx - 5, y: top + 24))      // legs
                context.move(to: CGPoint(x: cx, y: top + 17))
                context.addLine(to: CGPoint(x: cx + 5, y: top + 24))
                context.strokePath()
                drawText(head.label, center: CGPoint(x: cx, y: head.frame.maxY + 7),
                         size: 10.5, weight: .medium, color: theme.ink, in: context)
            } else if head.kind != "participant" {
                drawParticipantGlyph(head.kind, frame: head.frame, theme: theme,
                                     stroke: stroke, in: context)
                drawText(head.label, center: CGPoint(x: head.frame.midX, y: head.frame.maxY + 7),
                         size: 10.5, weight: .medium, color: theme.ink, in: context)
            } else {
                fillStrokeBox(head.frame, radius: 6, fill: theme.accent.withAlphaComponent(0.06), stroke: stroke, in: context)
                drawText(head.label, center: CGPoint(x: head.frame.midX, y: head.frame.midY),
                         size: 12, weight: .medium, color: theme.ink, in: context)
            }
        }

        // Autonumber badges: a small chip at the sender end of the arrow.
        for arrow in layout.arrows where arrow.number != nil {
            let text = "\(arrow.number!)"
            let size = measure(text, size: 8)
            let sign: CGFloat = arrow.toX >= arrow.fromX ? 1 : -1
            let chip = CGRect(x: arrow.fromX + sign * 4 - (sign < 0 ? size.width + 8 : 0),
                              y: arrow.y - 17,
                              width: size.width + 8, height: 12)
            context.setFillColor(resolvedCGColor(theme.accent.withAlphaComponent(0.85)))
            context.addPath(CGPath(roundedRect: chip, cornerWidth: 5, cornerHeight: 5, transform: nil))
            context.fillPath()
            drawText(text, center: CGPoint(x: chip.midX, y: chip.midY),
                     size: 8, weight: .semibold, color: theme.canvas, in: context)
        }

        // Note boxes: tinted, hairline-bordered, text centered — the classic
        // sequence-note look.
        for note in layout.notes {
            fillStrokeBox(note.frame, radius: 3,
                          fill: theme.categoricalColor(2).withAlphaComponent(0.18),
                          stroke: theme.categoricalColor(2), in: context)
            let lines = DiagramLayoutEngine.brLines(note.text)
            let startY = note.frame.midY - CGFloat(lines.count - 1) * 6.5
            for (i, line) in lines.enumerated() {
                drawText(line, center: CGPoint(x: note.frame.midX, y: startY + CGFloat(i) * 13),
                         size: labelSize, color: theme.ink, in: context)
            }
        }

        for arrow in layout.arrows {
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(stroke))
            context.setLineWidth(1)
            if arrow.dashed { context.setLineDash(phase: 0, lengths: [4, 3]) }
            context.beginPath()
            if arrow.isSelfMessage {
                // Loop out, down, and back into the lifeline.
                context.move(to: CGPoint(x: arrow.fromX, y: arrow.y))
                context.addLine(to: CGPoint(x: arrow.toX, y: arrow.y))
                context.addLine(to: CGPoint(x: arrow.toX, y: arrow.y + 12))
                context.addLine(to: CGPoint(x: arrow.fromX, y: arrow.y + 12))
            } else {
                context.move(to: CGPoint(x: arrow.fromX, y: arrow.y))
                context.addLine(to: CGPoint(x: arrow.toX, y: arrow.y))
            }
            context.strokePath()
            context.restoreGState()

            if arrow.isSelfMessage {
                drawSequenceHead(arrow.head,
                    at: CGPoint(x: arrow.fromX, y: arrow.y + 12),
                    from: CGPoint(x: arrow.toX, y: arrow.y + 12),
                    stroke: stroke, theme: theme, in: context)
                if !arrow.text.isEmpty {
                    let size = measure(arrow.text, size: 10.5)
                    drawText(arrow.text,
                             center: CGPoint(x: arrow.toX + 8 + size.width / 2, y: arrow.y + 6),
                             size: 10.5, color: theme.secondaryTextColor, in: context)
                }
            } else {
                drawSequenceHead(arrow.head,
                    at: CGPoint(x: arrow.toX, y: arrow.y),
                    from: CGPoint(x: arrow.fromX, y: arrow.y),
                    stroke: stroke, theme: theme, in: context)
                if arrow.head == .both {
                    drawSequenceHead(.filled,
                        at: CGPoint(x: arrow.fromX, y: arrow.y),
                        from: CGPoint(x: arrow.toX, y: arrow.y),
                        stroke: stroke, theme: theme, in: context)
                }
                if !arrow.text.isEmpty {
                    let lines = DiagramLayoutEngine.brLines(arrow.text)
                    for (i, line) in lines.enumerated() {
                        let lineY = arrow.y - 10 - CGFloat(lines.count - 1 - i) * 12
                        drawText(line,
                                 center: CGPoint(x: (arrow.fromX + arrow.toX) / 2, y: lineY),
                                 size: 10.5, color: theme.secondaryTextColor, in: context)
                    }
                }
            }
        }
    }
}
#endif
