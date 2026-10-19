import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `FlowchartLayout` into a fully-resolved `RenderScene`.
    ///
    /// This is the platform-free twin of `DiagramRenderer.draw(_:theme:in:)`
    /// (MermaidRender/DiagramRenderer+Flowchart.swift): it emits the exact same
    /// shapes, wires, arrowhead gaps, and label anchors that the CoreGraphics
    /// renderer draws, only as scene primitives instead of `CGContext` calls.
    /// Any change to the drawn flowchart appearance must land in both.
    ///
    /// `measure` is accepted for parity with the drawn path and future use
    /// (text-frame resolution); the layout has already positioned every label,
    /// so this slice needs no measurement to place primitives.
    public static func from(_ layout: FlowchartLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        _ = measure
        var elements: [Element] = []

        // Shared node stroke/fill (matches DiagramRenderer.draw): a 35%-ink
        // hairline and a 6%-accent tint, both at line width 1.
        let strokeColor = theme.ink.withAlpha(0.35)
        let edgeStrokeColor = strokeColor
        let nodeStroke = Stroke(color: strokeColor, width: 1, dashed: false)
        let nodeFill = theme.accent.withAlpha(0.06)

        // 1. Subgraph group boxes first — backdrops behind every wire and node.
        //    A deeper box is tinted a touch stronger so nested groups read apart.
        for container in layout.containers.sorted(by: { $0.depth < $1.depth }) {
            let boxFill = theme.ink.withAlpha(0.04 + 0.03 * Double(min(container.depth, 3)))
            let boxStroke = Stroke(color: theme.ink.withAlpha(0.28), width: 1, dashed: false)
            elements.append(.shape(Shape(
                path: .roundedRect(container.frame, radius: 6),
                fill: boxFill, stroke: boxStroke)))
            if !container.label.isEmpty {
                elements.append(.text(Text(
                    string: container.label,
                    center: CGPoint(x: container.frame.midX,
                                    y: container.frame.minY + DiagramLayoutEngine.clusterHeader(measure) / 2),
                    fontSize: 11, weight: .semibold,
                    color: theme.ink.withAlpha(0.75))))
            }
        }

        // 2. Edge shafts. Pull an arrowhead tip back 3pt along the last segment
        //    so the head doesn't jam into the box it points at — the same gap
        //    the renderer opens before drawing the arrowhead.
        //    An invisible link (`~~~`) draws nothing. Circle and cross heads are
        //    marks of their own, drawn after the line, which stops where the
        //    mark begins.
        var marks: [Element] = []
        for edge in layout.edges where !edge.invisible {
            var points = edge.points
            let approach = points.count > 1 ? points[points.count - 2] : edge.start
            let arrows = edge.head == .arrow
            if edge.hasArrow, points.count >= 2 {
                let end = points[points.count - 1]
                if arrows {
                    let dx = end.x - approach.x, dy = end.y - approach.y
                    let len = max(hypot(dx, dy), 0.001)
                    let gap: CGFloat = 3
                    points[points.count - 1] = CGPoint(x: end.x - dx / len * gap,
                                                       y: end.y - dy / len * gap)
                } else {
                    points[points.count - 1] = endMark(
                        edge.head, at: end, from: approach, color: edgeStrokeColor,
                        canvas: theme.canvas, into: &marks)
                }
            }
            if edge.backArrow, !arrows, points.count >= 2 {
                points[0] = endMark(edge.head, at: points[0], from: points[1],
                                    color: edgeStrokeColor, canvas: theme.canvas, into: &marks)
            }
            let stroke = Stroke(color: edgeStrokeColor, width: edge.thick ? 2 : 1, dashed: edge.dashed)
            elements.append(.polyline(Polyline(
                points: points, stroke: stroke,
                startArrow: edge.backArrow && arrows, endArrow: edge.hasArrow && arrows)))
        }
        elements.append(contentsOf: marks)

        // 3. Edge labels, on their canvas-colored chips, above every wire.
        for edge in layout.edges where !edge.invisible {
            guard let label = edge.label, !label.isEmpty else { continue }
            let point = edge.labelPoint ?? DiagramScene.polylineMidpoint(edge.points)
            elements.append(.text(Text(
                string: label, center: point,
                fontSize: 10.5, weight: .regular,
                color: theme.secondaryText, backing: theme.canvas)))
        }

        // 4. Nodes on top, each with its centered label.
        for node in layout.nodes {
            let f = node.frame
            switch node.shape {
            case .stateStart:
                // A solid filled dot in 75%-ink; no label.
                elements.append(.shape(Shape(
                    path: .ellipse(f), fill: theme.ink.withAlpha(0.75), stroke: nil)))
                continue
            case .stateEnd:
                // A ring around a solid dot, both 75%-ink; no label.
                let ink = theme.ink.withAlpha(0.75)
                elements.append(.shape(Shape(
                    path: .ellipse(f.insetBy(dx: 1, dy: 1)),
                    fill: nil, stroke: Stroke(color: ink, width: 1, dashed: false))))
                elements.append(.shape(Shape(
                    path: .ellipse(f.insetBy(dx: 4.5, dy: 4.5)),
                    fill: ink, stroke: nil)))
                continue
            case .cylinder:
                // Database silhouette (sides + back/front arcs) then the visible
                // front rim of the top cap. Label sits in the body, below the cap.
                let capH = min(f.height * 0.14, 7)
                let bodyTop = f.minY + capH
                let bodyBottom = f.maxY - capH
                let silhouette: [PathVerb] = [
                    .move(CGPoint(x: f.minX, y: bodyTop)),
                    .line(CGPoint(x: f.minX, y: bodyBottom)),
                    .quad(to: CGPoint(x: f.maxX, y: bodyBottom),
                          control: CGPoint(x: f.midX, y: bodyBottom + capH * 2)),
                    .line(CGPoint(x: f.maxX, y: bodyTop)),
                    .quad(to: CGPoint(x: f.minX, y: bodyTop),
                          control: CGPoint(x: f.midX, y: bodyTop - capH * 2)),
                    .close,
                ]
                elements.append(.shape(Shape(
                    path: .path(silhouette), fill: nodeFill, stroke: nodeStroke)))
                let rim: [PathVerb] = [
                    .move(CGPoint(x: f.minX, y: bodyTop)),
                    .quad(to: CGPoint(x: f.maxX, y: bodyTop),
                          control: CGPoint(x: f.midX, y: bodyTop + capH * 2)),
                ]
                elements.append(.shape(Shape(
                    path: .path(rim), fill: nil, stroke: nodeStroke)))
                elements.append(.text(Text(
                    string: node.label,
                    center: CGPoint(x: f.midX, y: f.midY + capH / 2),
                    fontSize: 12, weight: .medium, color: theme.ink)))
                continue
            case .rectangle, .rounded, .stadium, .circle, .doubleCircle, .diamond, .hexagon,
                 .subroutine, .parallelogram, .parallelogramAlt, .trapezoid, .trapezoidAlt,
                 .asymmetric:
                break
            }

            let path: ShapePath
            switch node.shape {
            case .rectangle:
                path = .roundedRect(f, radius: 4)
            case .rounded:
                path = .roundedRect(f, radius: 8)
            case .stadium:
                path = .roundedRect(f, radius: f.height / 2)
            case .circle:
                path = .ellipse(f)
            case .diamond:
                path = .polygon([
                    CGPoint(x: f.midX, y: f.minY),
                    CGPoint(x: f.maxX, y: f.midY),
                    CGPoint(x: f.midX, y: f.maxY),
                    CGPoint(x: f.minX, y: f.midY),
                ])
            case .hexagon:
                let inset = min(f.width * 0.22, f.height / 2)
                path = .polygon([
                    CGPoint(x: f.minX, y: f.midY),
                    CGPoint(x: f.minX + inset, y: f.minY),
                    CGPoint(x: f.maxX - inset, y: f.minY),
                    CGPoint(x: f.maxX, y: f.midY),
                    CGPoint(x: f.maxX - inset, y: f.maxY),
                    CGPoint(x: f.minX + inset, y: f.maxY),
                ])
            case .subroutine:
                path = .roundedRect(f, radius: 4)
            case .doubleCircle:
                path = .ellipse(f)
            case .parallelogram, .parallelogramAlt, .trapezoid, .trapezoidAlt, .asymmetric:
                path = .polygon(DiagramLayoutEngine.polygonOutline(node.shape, in: f) ?? [])
            case .cylinder, .stateStart, .stateEnd:
                continue // handled above
            }
            // As Flowchart.NodeShape grows, add the matching ShapePath here
            // and in the CoreGraphics renderer together.
            elements.append(.shape(Shape(path: path, fill: nodeFill, stroke: nodeStroke)))
            if node.shape == .doubleCircle {
                // The inner ring (match DiagramRenderer).
                let gap = DiagramLayoutEngine.doubleCircleGap
                elements.append(.shape(Shape(
                    path: .ellipse(f.insetBy(dx: gap, dy: gap)), fill: nil, stroke: nodeStroke)))
            }
            if node.shape == .subroutine {
                // Twin inner rails of a `[[ … ]]` box (match DiagramRenderer).
                let inset = min(6, f.width / 4)
                for x in [f.minX + inset, f.maxX - inset] {
                    elements.append(.polyline(Polyline(
                        points: [CGPoint(x: x, y: f.minY), CGPoint(x: x, y: f.maxY)],
                        stroke: nodeStroke, startArrow: false, endArrow: false)))
                }
            }
            // A flag's label centers on the part right of its notch.
            let notch = node.shape == .asymmetric ? min(f.width * 0.22, f.height / 2) : 0
            elements.append(.text(Text(
                string: node.label,
                center: CGPoint(x: f.midX + notch / 2, y: f.midY),
                fontSize: 12, weight: .medium, color: theme.ink)))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Adds a circle (`--o`) or cross (`--x`) mark for a line ending at `tip`
    /// from `approach`, and returns where the line should stop. Matches
    /// `DiagramRenderer.drawEndMark`: 3pt clear of the node like an arrow's
    /// tip, a filled 4pt-radius circle (canvas first, so the translucent
    /// line doesn't show through) or a 1.5pt cross 8pt across, which the line
    /// runs into.
    static func endMark(_ head: Flowchart.Edge.Head, at tip: CGPoint, from approach: CGPoint,
                        color: DiagramColor, canvas: DiagramColor,
                        into marks: inout [Element]) -> CGPoint {
        let dx = tip.x - approach.x, dy = tip.y - approach.y
        let len = max(hypot(dx, dy), 0.001)
        let (ux, uy) = (dx / len, dy / len)
        let radius: CGFloat = 4
        // Where the line stops, measured back from the tip. Never past half
        // the segment, so a short `o--o` keeps a forward shaft between marks.
        let reach: CGFloat = head == .circle ? 3 + 2 * radius : 3 + radius
        let scale = min(1, len / 2 / reach)
        let back = (3 + radius) * scale
        let center = CGPoint(x: tip.x - ux * back, y: tip.y - uy * back)
        switch head {
        case .circle:
            let box = CGRect(x: center.x - radius, y: center.y - radius,
                             width: radius * 2, height: radius * 2)
            marks.append(.shape(Shape(path: .ellipse(box), fill: canvas, stroke: nil)))
            marks.append(.shape(Shape(path: .ellipse(box), fill: color, stroke: nil)))
            return CGPoint(x: tip.x - ux * reach * scale, y: tip.y - uy * reach * scale)
        case .cross:
            // Two arms at 45° to the line.
            let arm = radius / 2.squareRoot()
            let a = CGPoint(x: (ux - uy) * arm, y: (uy + ux) * arm)
            let b = CGPoint(x: (ux + uy) * arm, y: (uy - ux) * arm)
            marks.append(.shape(Shape(path: .path([
                .move(CGPoint(x: center.x - a.x, y: center.y - a.y)),
                .line(CGPoint(x: center.x + a.x, y: center.y + a.y)),
                .move(CGPoint(x: center.x - b.x, y: center.y - b.y)),
                .line(CGPoint(x: center.x + b.x, y: center.y + b.y)),
            ]), fill: nil, stroke: Stroke(color: color, width: 1.5, dashed: false))))
            return center
        case .arrow:
            return tip
        }
    }
}
