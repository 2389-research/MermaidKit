import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a ZenUML layout to the common scene IR: participant head boxes
    /// are the only nodes (lifelines are guides), each message is an edge
    /// along its row — self-calls as a right-side loop — and message text
    /// chips are free-standing labels.
    static func from(_ layout: ZenUMLLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        DiagramScene(
            name: "zenuml",
            size: layout.size,
            // One Node per participant head box across the top. The dashed
            // lifelines dropping from each head are guides, not nodes; a head is
            // the only opaque rectangle a message could be routed through, and it
            // contains nothing else.
            nodes: layout.participants.map { p in
                Node(id: p.name, frame: p.frame, isContainer: false)
            },
            // One Edge per message. A normal message is the horizontal segment
            // between two lifelines at its row `y`. A self-call is a small
            // right-side loop (out to `toX`, down by `selfHeight`, back), matching
            // how the renderer draws the return loop. The message text rides the
            // edge label.
            edges: layout.arrows.map { arrow in
                let label = arrow.label.isEmpty ? nil : arrow.label
                if arrow.isSelf {
                    return Edge(
                        polyline: [
                            CGPoint(x: arrow.fromX, y: arrow.y),
                            CGPoint(x: arrow.toX, y: arrow.y),
                            CGPoint(x: arrow.toX, y: arrow.y + arrow.selfHeight),
                            CGPoint(x: arrow.fromX, y: arrow.y + arrow.selfHeight)
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
            // Free-standing message text chips only: a chip can collide with
            // another row's chip or with a head box. A normal chip centers above
            // the arrow midpoint; a self-call chip sits to the right of the loop
            // (matching the renderer, which widens the canvas for it). Head names
            // are implicit in their Node, and the `«Stereotype»` line is drawn
            // inside the head box (node-internal), so neither is listed here.
            labels: layout.arrows.enumerated().compactMap { index, arrow -> Label? in
                guard !arrow.label.isEmpty else { return nil }
                let width = measuredLabelSize(measure, arrow.label).width
                if arrow.isSelf {
                    return Label(
                        text: arrow.label,
                        frame: CGRect(x: arrow.toX + 8, y: arrow.y - 7,
                                      width: width, height: 14),
                        anchorEdge: index
                    )
                }
                let midX = (arrow.fromX + arrow.toX) / 2
                return Label(
                    text: arrow.label,
                    frame: CGRect(x: midX - width / 2, y: arrow.y - 9,
                                  width: width, height: 14),
                    anchorEdge: index
                )
            }
        )
    }
}