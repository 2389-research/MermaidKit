import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a sequence layout to the common scene IR: participant head
    /// boxes are the only nodes (lifelines are guides, not obstacles), each
    /// message is an edge along its row — self-messages as a right-side loop
    /// — and message text chips are free-standing labels.
    static func from(_ layout: SequenceLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // Loop depth used to synthesize a polyline for a self-message, whose
        // layout stores only a single y and an outbound `toX`.
        let selfLoopHeight: CGFloat = 12

        return DiagramScene(
            name: "sequence",
            size: layout.size,
            // One Node per participant head box. Heads are the only opaque
            // rectangles a message could be routed through; the lifelines they
            // sit atop are guides, not nodes. Heads contain nothing else.
            nodes: layout.heads.map { head in
                // Actor and typed-glyph heads draw their NAME 7pt below the
                // frame; extend the node so the linter sees the text too.
                var frame = head.frame
                if head.isActor || head.kind != "participant" {
                    frame.size.height += 14
                }
                return Node(id: head.label, frame: frame, isContainer: false)
            } + layout.notes.map { note in
                // Note boxes are opaque rectangles in the message field; the
                // linter must see them so a crossing arrow gets flagged.
                Node(id: "note: \(note.text)", frame: note.frame, isContainer: false)
            } + layout.frames.map { frame in
                // Fragment frames legitimately contain rows: containers.
                Node(id: "\(frame.kind): \(frame.label ?? "")", frame: frame.rect, isContainer: true)
            } + layout.boxBands.map { band in
                Node(id: "box: \(band.label ?? "")", frame: band.rect, isContainer: true)
            } + layout.bars.enumerated().map { index, bar in
                // Activation bars are slim boxes ON the lifeline; arrows
                // meeting them at their edge is design, and their 8pt width
                // keeps traversal below the occlusion floor.
                Node(id: "bar#\(index)",
                     frame: CGRect(x: bar.x - 4 + CGFloat(bar.depth) * 4, y: bar.top,
                                   width: 8, height: max(bar.bottom - bar.top, 6)))
            },
            // One Edge per message arrow, routed along its row. A normal message
            // is the horizontal segment from sender to receiver lifeline. A
            // self-message is a small right-side loop (out, down, back), matching
            // how the renderer draws it. The message text rides the edge label.
            edges: layout.arrows.map { arrow in
                let label = arrow.text.isEmpty ? nil : arrow.text
                if arrow.isSelfMessage {
                    return Edge(
                        polyline: [
                            CGPoint(x: arrow.fromX, y: arrow.y),
                            CGPoint(x: arrow.toX, y: arrow.y),
                            CGPoint(x: arrow.toX, y: arrow.y + selfLoopHeight),
                            CGPoint(x: arrow.fromX, y: arrow.y + selfLoopHeight)
                        ],
                        label: label
                    )
                }
                return Edge(
                    polyline: [
                        CGPoint(x: arrow.fromX, y: arrow.y),
                        CGPoint(x: arrow.toX, y: arrow.y)
                    ],
                    label: label
                )
            },
            // Free-standing message labels only: the text chip can collide with
            // another row's chip or with a head box. A normal chip centers above
            // the arrow's midpoint; a self-message chip sits to the right of the
            // loop (matching the renderer, which widens the canvas for it).
            labels: layout.arrows.enumerated().compactMap { index, arrow -> Label? in
                guard !arrow.text.isEmpty else { return nil }
                let lines = DiagramLayoutEngine.brLines(arrow.text)
                let width = lines.map { measuredLabelSize(measure, $0).width }.max()
                    ?? measuredLabelSize(measure, arrow.text).width
                if arrow.isSelfMessage {
                    // Drawn right of the loop, centred at arrow.y + 6.
                    return Label(
                        text: arrow.text,
                        frame: CGRect(x: arrow.toX + 8, y: arrow.y - 1,
                                      width: width, height: 14),
                        anchorEdge: index
                    )
                }
                // Drawn ABOVE the arrow: line i centres at
                // y - 10 - (n-1-i)*12, so the block spans upward from the row.
                let blockHeight = 14 + CGFloat(lines.count - 1) * 12
                let midX = (arrow.fromX + arrow.toX) / 2
                return Label(
                    text: arrow.text,
                    frame: CGRect(x: midX - width / 2,
                                  y: arrow.y - 10 - CGFloat(lines.count - 1) * 12 - 7,
                                  width: width, height: blockHeight),
                    anchorEdge: index
                )
            } + layout.arrows.enumerated().compactMap { index, arrow -> Label? in
                // Autonumber chips: an opaque accent chip at the sender end.
                guard let number = arrow.number else { return nil }
                let text = "\(number)"
                let width = measuredLabelSize(measure, text).width + 8
                let sign: CGFloat = arrow.toX >= arrow.fromX ? 1 : -1
                let x = arrow.fromX + sign * 4 - (sign < 0 ? width : 0)
                return Label(text: text,
                             frame: CGRect(x: x, y: arrow.y - 17, width: width, height: 12),
                             anchorEdge: index, backed: true)
            } + layout.frames.flatMap { frame -> [Label] in
                guard frame.kind != "rect" else { return [] }
                // Kind tab + optional [guard] beside it, then each divider's
                // canvas-chipped [label].
                var out: [Label] = []
                let kindWidth = measuredLabelSize(measure, frame.kind).width
                out.append(Label(
                    text: frame.kind,
                    frame: CGRect(x: frame.rect.minX + 5, y: frame.rect.minY + 1,
                                  width: kindWidth, height: 13)))
                if let guardText = frame.label, !guardText.isEmpty {
                    let text = "[\(guardText)]"
                    let width = measuredLabelSize(measure, text).width
                    out.append(Label(
                        text: text,
                        frame: CGRect(x: frame.rect.minX + kindWidth + 20,
                                      y: frame.rect.minY + 1, width: width, height: 13)))
                }
                for divider in frame.dividers {
                    guard let label = divider.label, !label.isEmpty else { continue }
                    let text = "[\(label)]"
                    let width = measuredLabelSize(measure, text).width + 6
                    out.append(Label(
                        text: text,
                        frame: CGRect(x: frame.rect.midX - width / 2, y: divider.y - 7,
                                      width: width, height: 14),
                        backed: true))
                }
                return out
            } + layout.boxBands.compactMap { band -> Label? in
                guard let text = band.label, !text.isEmpty else { return nil }
                let width = measuredLabelSize(measure, text).width
                return Label(
                    text: text,
                    frame: CGRect(x: band.rect.midX - width / 2, y: band.rect.minY + 2,
                                  width: width, height: 14))
            }
        )
    }
}