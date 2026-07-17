import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `SequenceLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: SequenceLayout, …)`
    /// (MermaidRender/DiagramRenderer+Sequence.swift). It emits, in the same
    /// painter's order: participant-group box bands, combined-fragment frames
    /// (with dog-eared kind tabs and dashed dividers), dashed lifelines and
    /// destroy crosses, activation bars, participant heads (boxes / stick-figure
    /// actors / typed glyphs), autonumber chips, note boxes, and message arrows
    /// with per-`ArrowHead` endings (filled / open / cross / none / both).
    ///
    /// The `RenderScene.Stroke` dash flag renders a single "4 3" pattern, so the
    /// lifeline's 3,3 dots read as the 4,3 dashes the message arrows use — a
    /// dash-pitch approximation the fixed primitive can't distinguish. Any other
    /// change to the drawn sequence appearance must land in both.
    public static func from(_ layout: SequenceLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        let stroke = theme.ink.withAlpha(0.35)
        let hairline = theme.ink.withAlpha(0.18)

        // 1. Box bands — participant-group backgrounds under everything.
        for band in layout.boxBands {
            elements.append(.shape(Shape(
                path: .roundedRect(band.rect, radius: 0),
                fill: theme.categoricalColor(band.colorIndex).withAlpha(0.08),
                stroke: Stroke(color: theme.hairline, width: 1))))
            if let label = band.label, !label.isEmpty {
                elements.append(.text(Text(
                    string: label,
                    center: CGPoint(x: band.rect.midX, y: band.rect.minY + 9),
                    fontSize: 9, weight: .semibold, color: theme.tertiaryText)))
            }
        }

        // 2. Fragment frames — everything else draws on top.
        for frame in layout.frames {
            if frame.kind == "rect" {
                elements.append(.shape(Shape(
                    path: .roundedRect(frame.rect, radius: 0),
                    fill: theme.accent.withAlpha(0.06), stroke: nil)))
                continue
            }
            elements.append(.shape(Shape(
                path: .roundedRect(frame.rect, radius: 0), fill: nil,
                stroke: Stroke(color: hairline, width: 1))))
            // Kind tab: the classic dog-eared corner chip + guard label.
            let kindWidth = measure(frame.kind, 9).width
            let tab = CGRect(x: frame.rect.minX, y: frame.rect.minY, width: kindWidth + 14, height: 15)
            elements.append(.shape(Shape(path: .polygon([
                CGPoint(x: tab.minX, y: tab.minY), CGPoint(x: tab.maxX, y: tab.minY),
                CGPoint(x: tab.maxX - 5, y: tab.maxY), CGPoint(x: tab.minX, y: tab.maxY),
            ]), fill: theme.hairline.withAlpha(0.14), stroke: nil)))
            elements.append(.text(Text(
                string: frame.kind,
                center: CGPoint(x: tab.minX + kindWidth / 2 + 5, y: tab.midY),
                fontSize: 9, weight: .semibold, color: theme.secondaryText)))
            if let label = frame.label, !label.isEmpty {
                let text = "[\(label)]"
                let w = measure(text, 9).width
                elements.append(.text(Text(
                    string: text, center: CGPoint(x: tab.maxX + 6 + w / 2, y: tab.midY),
                    fontSize: 9, color: theme.tertiaryText)))
            }
            for divider in frame.dividers {
                elements.append(.polyline(Polyline(
                    points: [CGPoint(x: frame.rect.minX, y: divider.y),
                             CGPoint(x: frame.rect.maxX, y: divider.y)],
                    stroke: Stroke(color: hairline, width: 1, dashed: true))))
                if let label = divider.label, !label.isEmpty {
                    let text = "[\(label)]"
                    let size = measure(text, 9)
                    elements.append(.shape(Shape(
                        path: .roundedRect(CGRect(x: frame.rect.midX - size.width / 2 - 3,
                                                  y: divider.y - 7, width: size.width + 6, height: 14),
                                           radius: 0),
                        fill: theme.canvas, stroke: nil)))
                    elements.append(.text(Text(
                        string: text, center: CGPoint(x: frame.rect.midX, y: divider.y),
                        fontSize: 9, color: theme.tertiaryText)))
                }
            }
        }

        // 3. Lifelines (dashed) with an optional destruction cross.
        for head in layout.heads {
            let end = head.lifelineEndY ?? layout.lifelineBottom
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: head.lifelineX, y: head.frame.maxY),
                         CGPoint(x: head.lifelineX, y: end)],
                stroke: Stroke(color: hairline, width: 1, dashed: true))))
            if head.showsDestroyCross {
                let r: CGFloat = 6, x = head.lifelineX
                elements.append(.shape(Shape(path: .path([
                    .move(CGPoint(x: x - r, y: end - r)), .line(CGPoint(x: x + r, y: end + r)),
                    .move(CGPoint(x: x - r, y: end + r)), .line(CGPoint(x: x + r, y: end - r)),
                ]), fill: nil, stroke: Stroke(color: theme.ink.withAlpha(0.7), width: 1.6))))
            }
        }

        // 4. Activation bars: rounded rects on the lifeline, offset per depth.
        for bar in layout.bars {
            let rect = CGRect(x: bar.x - 4 + CGFloat(bar.depth) * 4, y: bar.top,
                              width: 8, height: max(bar.bottom - bar.top, 6))
            elements.append(.shape(Shape(
                path: .roundedRect(rect, radius: 2),
                fill: theme.accent.withAlpha(0.14), stroke: Stroke(color: stroke, width: 1))))
        }

        // 5. Participant heads: stick-figure actors, typed glyphs, or boxes.
        for head in layout.heads {
            if head.isActor {
                let cx = head.frame.midX, top = head.frame.minY
                let s = Stroke(color: theme.ink.withAlpha(0.75), width: 1.4)
                elements.append(.shape(Shape(
                    path: .ellipse(CGRect(x: cx - 4, y: top, width: 8, height: 8)),
                    fill: nil, stroke: s)))
                elements.append(.shape(Shape(path: .path([
                    .move(CGPoint(x: cx, y: top + 8)), .line(CGPoint(x: cx, y: top + 17)),       // body
                    .move(CGPoint(x: cx - 6, y: top + 11)), .line(CGPoint(x: cx + 6, y: top + 11)), // arms
                    .move(CGPoint(x: cx, y: top + 17)), .line(CGPoint(x: cx - 5, y: top + 24)),   // legs
                    .move(CGPoint(x: cx, y: top + 17)), .line(CGPoint(x: cx + 5, y: top + 24)),
                ]), fill: nil, stroke: s)))
                elements.append(.text(Text(
                    string: head.label, center: CGPoint(x: cx, y: head.frame.maxY + 7),
                    fontSize: 10.5, weight: .medium, color: theme.ink)))
            } else if head.kind != "participant" {
                elements += participantGlyphElements(head.kind, frame: head.frame, theme: theme, stroke: stroke)
                elements.append(.text(Text(
                    string: head.label,
                    center: CGPoint(x: head.frame.midX, y: head.frame.maxY + 7),
                    fontSize: 10.5, weight: .medium, color: theme.ink)))
            } else {
                elements.append(.shape(Shape(
                    path: .roundedRect(head.frame, radius: 6),
                    fill: theme.accent.withAlpha(0.06), stroke: Stroke(color: stroke, width: 1))))
                elements.append(.text(Text(
                    string: head.label,
                    center: CGPoint(x: head.frame.midX, y: head.frame.midY),
                    fontSize: 12, weight: .medium, color: theme.ink)))
            }
        }

        // 6. Autonumber badges: a small chip at the sender end of the arrow.
        for arrow in layout.arrows where arrow.number != nil {
            let text = "\(arrow.number!)"
            let size = measure(text, 8)
            let sign: CGFloat = arrow.toX >= arrow.fromX ? 1 : -1
            let chip = CGRect(x: arrow.fromX + sign * 4 - (sign < 0 ? size.width + 8 : 0),
                              y: arrow.y - 17, width: size.width + 8, height: 12)
            elements.append(.shape(Shape(
                path: .roundedRect(chip, radius: 5),
                fill: theme.accent.withAlpha(0.85), stroke: nil)))
            elements.append(.text(Text(
                string: text, center: CGPoint(x: chip.midX, y: chip.midY),
                fontSize: 8, weight: .semibold, color: theme.canvas)))
        }

        // 7. Note boxes: tinted, hairline-bordered, text centered.
        for note in layout.notes {
            let hue = theme.categoricalColor(2)
            elements.append(.shape(Shape(
                path: .roundedRect(note.frame, radius: 3),
                fill: hue.withAlpha(0.18), stroke: Stroke(color: hue, width: 1))))
            let lines = DiagramLayoutEngine.brLines(note.text)
            let startY = note.frame.midY - CGFloat(lines.count - 1) * 6.5
            for (i, line) in lines.enumerated() where !line.isEmpty {
                elements.append(.text(Text(
                    string: line, center: CGPoint(x: note.frame.midX, y: startY + CGFloat(i) * 13),
                    fontSize: 10.5, color: theme.ink)))
            }
        }

        // 8. Message arrows: shaft, arrow ending, and caption.
        for arrow in layout.arrows {
            let shaftStroke = Stroke(color: stroke, width: 1, dashed: arrow.dashed)
            if arrow.isSelfMessage {
                elements.append(.polyline(Polyline(points: [
                    CGPoint(x: arrow.fromX, y: arrow.y), CGPoint(x: arrow.toX, y: arrow.y),
                    CGPoint(x: arrow.toX, y: arrow.y + 12), CGPoint(x: arrow.fromX, y: arrow.y + 12),
                ], stroke: shaftStroke)))
                elements += sequenceHeadElements(arrow.head,
                    at: CGPoint(x: arrow.fromX, y: arrow.y + 12),
                    from: CGPoint(x: arrow.toX, y: arrow.y + 12), stroke: stroke)
                if !arrow.text.isEmpty {
                    let size = measure(arrow.text, 10.5)
                    elements.append(.text(Text(
                        string: arrow.text,
                        center: CGPoint(x: arrow.toX + 8 + size.width / 2, y: arrow.y + 6),
                        fontSize: 10.5, color: theme.secondaryText)))
                }
            } else {
                elements.append(.polyline(Polyline(points: [
                    CGPoint(x: arrow.fromX, y: arrow.y), CGPoint(x: arrow.toX, y: arrow.y),
                ], stroke: shaftStroke)))
                elements += sequenceHeadElements(arrow.head,
                    at: CGPoint(x: arrow.toX, y: arrow.y),
                    from: CGPoint(x: arrow.fromX, y: arrow.y), stroke: stroke)
                if arrow.head == .both {
                    elements += sequenceHeadElements(.filled,
                        at: CGPoint(x: arrow.fromX, y: arrow.y),
                        from: CGPoint(x: arrow.toX, y: arrow.y), stroke: stroke)
                }
                if !arrow.text.isEmpty {
                    let lines = DiagramLayoutEngine.brLines(arrow.text)
                    for (i, line) in lines.enumerated() where !line.isEmpty {
                        let lineY = arrow.y - 10 - CGFloat(lines.count - 1 - i) * 12
                        elements.append(.text(Text(
                            string: line,
                            center: CGPoint(x: (arrow.fromX + arrow.toX) / 2, y: lineY),
                            fontSize: 10.5, color: theme.secondaryText)))
                    }
                }
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// The arrow ending for a sequence head style — the platform-free twin of
    /// `DiagramRenderer.drawSequenceHead`: filled triangle, X-cross, open
    /// half-arrow, or nothing.
    private static func sequenceHeadElements(
        _ head: SequenceDiagram.Message.ArrowHead,
        at tip: CGPoint, from origin: CGPoint, stroke: DiagramColor
    ) -> [Element] {
        switch head {
        case .none:
            return []
        case .filled, .both:
            let a = atan2(tip.y - origin.y, tip.x - origin.x)
            let length: CGFloat = 8.5, spread: CGFloat = 0.40
            let p2 = CGPoint(x: tip.x - length * cos(a - spread), y: tip.y - length * sin(a - spread))
            let p3 = CGPoint(x: tip.x - length * cos(a + spread), y: tip.y - length * sin(a + spread))
            return [.shape(Shape(path: .polygon([tip, p2, p3]), fill: stroke, stroke: nil))]
        case .cross:
            let r: CGFloat = 4.5
            let inset: CGFloat = tip.x >= origin.x ? -3 : 3
            let cx = tip.x + inset
            return [.shape(Shape(path: .path([
                .move(CGPoint(x: cx - r, y: tip.y - r)), .line(CGPoint(x: cx + r, y: tip.y + r)),
                .move(CGPoint(x: cx - r, y: tip.y + r)), .line(CGPoint(x: cx + r, y: tip.y - r)),
            ]), fill: nil, stroke: Stroke(color: stroke, width: 1.6)))]
        case .open:
            let a = atan2(tip.y - origin.y, tip.x - origin.x)
            let length: CGFloat = 9, spread: CGFloat = 0.5
            return [.shape(Shape(path: .path([
                .move(CGPoint(x: tip.x - length * cos(a - spread), y: tip.y - length * sin(a - spread))),
                .line(tip),
                .line(CGPoint(x: tip.x - length * cos(a + spread), y: tip.y - length * sin(a + spread))),
            ]), fill: nil, stroke: Stroke(color: stroke, width: 1.4)))]
        }
    }

    /// Small head glyphs for typed participants (database cylinder, queue,
    /// collections, and the UML robustness trio) — the platform-free twin of
    /// `DiagramRenderer.drawParticipantGlyph`, centered above the label.
    private static func participantGlyphElements(
        _ kind: String, frame: CGRect, theme: RenderTheme, stroke: DiagramColor
    ) -> [Element] {
        let cx = frame.midX, top = frame.minY + 2
        let fill = theme.accent.withAlpha(0.10)
        let s = Stroke(color: stroke, width: 1.2)
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                  fill f: DiagramColor?, stroke st: Stroke?) -> Element {
            .shape(Shape(path: .roundedRect(CGRect(x: x, y: y, width: w, height: h), radius: 0),
                         fill: f, stroke: st))
        }
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     fill f: DiagramColor?, stroke st: Stroke?) -> Element {
            .shape(Shape(path: .ellipse(CGRect(x: x, y: y, width: w, height: h)), fill: f, stroke: st))
        }
        func line(_ a: CGPoint, _ b: CGPoint) -> Element {
            .polyline(Polyline(points: [a, b], stroke: s))
        }
        switch kind {
        case "database":
            return [
                rect(cx - 11, top + 6, 22, 12, fill: fill, stroke: nil),
                ellipse(cx - 11, top, 22, 7, fill: nil, stroke: s),
                line(CGPoint(x: cx - 11, y: top + 3.5), CGPoint(x: cx - 11, y: top + 21)),
                line(CGPoint(x: cx + 11, y: top + 3.5), CGPoint(x: cx + 11, y: top + 21)),
                ellipse(cx - 11, top + 17, 22, 7, fill: nil, stroke: s),
            ]
        case "queue":
            return [
                ellipse(cx + 8, top + 4, 8, 16, fill: nil, stroke: s),
                line(CGPoint(x: cx - 12, y: top + 4), CGPoint(x: cx + 12, y: top + 4)),
                line(CGPoint(x: cx - 12, y: top + 20), CGPoint(x: cx + 12, y: top + 20)),
                ellipse(cx - 16, top + 4, 8, 16, fill: fill, stroke: s),
            ]
        case "collections":
            return [
                rect(cx - 8, top + 2, 18, 14, fill: fill, stroke: s),
                rect(cx - 12, top + 7, 18, 14, fill: theme.canvas, stroke: s),
            ]
        case "boundary":
            return [
                ellipse(cx - 8, top + 3, 18, 18, fill: nil, stroke: s),
                line(CGPoint(x: cx - 14, y: top + 3), CGPoint(x: cx - 14, y: top + 21)),
                line(CGPoint(x: cx - 14, y: top + 12), CGPoint(x: cx - 8, y: top + 12)),
            ]
        case "control":
            return [
                ellipse(cx - 9, top + 3, 18, 18, fill: nil, stroke: s),
                .shape(Shape(path: .path([
                    .move(CGPoint(x: cx - 2, y: top)), .line(CGPoint(x: cx + 3, y: top + 3)),
                    .line(CGPoint(x: cx - 2, y: top + 6)),
                ]), fill: nil, stroke: s)),
            ]
        case "entity":
            return [
                ellipse(cx - 9, top + 2, 18, 18, fill: fill, stroke: s),
                line(CGPoint(x: cx - 11, y: top + 22), CGPoint(x: cx + 11, y: top + 22)),
            ]
        default:
            return []
        }
    }
}
