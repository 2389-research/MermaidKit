import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers an `ERLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: ERLayout, …)`
    /// (MermaidRender/DiagramRenderer+ER.swift). It emits entity boxes with a
    /// name compartment and typed attribute rows (type / name / PK·FK·UK badge),
    /// relationship shafts (dashed for non-identifying), and crow's-foot
    /// cardinality markers resolved to concrete geometry at both ends. Any change
    /// to the drawn ER appearance must land in both.
    public static func from(_ layout: ERLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        let stroke = theme.ink.withAlpha(0.35)
        let hairline = theme.ink.withAlpha(0.18)
        let fill = theme.accent.withAlpha(0.06)

        // 1. Relationship shafts (dashed = non-identifying). Cardinality markers
        //    are separate geometry, so the shaft carries no arrowhead flag.
        for edge in layout.edges {
            elements.append(.polyline(Polyline(
                points: edge.points,
                stroke: Stroke(color: stroke, width: 1, dashed: !edge.identifying))))
        }

        // 2. Crow's-foot cardinality at both ends, then the edge label.
        for edge in layout.edges {
            let fromApproach = edge.points.count > 1 ? edge.points[1] : edge.end
            let toApproach = edge.points.count > 1 ? edge.points[edge.points.count - 2] : edge.start
            elements += cardinalityElements(edge.fromCard, at: edge.start, from: fromApproach, color: stroke)
            elements += cardinalityElements(edge.toCard, at: edge.end, from: toApproach, color: stroke)
            if !edge.label.isEmpty {
                let at = edge.labelAnchor ?? DiagramScene.polylineMidpoint(edge.points)
                elements.append(.text(Text(
                    string: edge.label, center: at, fontSize: 10.5,
                    color: theme.secondaryText, backing: theme.canvas)))
            }
        }

        // 3. Entity boxes on top: name compartment, then typed attribute rows.
        for box in layout.boxes {
            elements.append(.shape(Shape(
                path: .roundedRect(box.frame, radius: 4), fill: fill,
                stroke: Stroke(color: stroke, width: 1))))
            elements.append(.text(Text(
                string: box.name,
                center: CGPoint(x: box.frame.midX, y: box.frame.minY + box.nameHeight / 2),
                fontSize: 12, weight: .semibold, color: theme.ink)))

            guard !box.attributes.isEmpty else { continue }
            var rowY = box.frame.minY + box.nameHeight
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: box.frame.minX, y: rowY), CGPoint(x: box.frame.maxX, y: rowY)],
                stroke: Stroke(color: hairline, width: 1))))
            rowY += 5
            let typeX = box.frame.minX + 12
            for attribute in box.attributes {
                let center = rowY + box.rowHeight / 2
                // Left-anchored runs: a scene Text is centered, so shift each by
                // half its measured width (mirrors DiagramRenderer.drawTextLeft).
                let typeWidth = measure(attribute.type, 10.5).width
                elements.append(.text(Text(
                    string: attribute.type,
                    center: CGPoint(x: typeX + typeWidth / 2, y: center),
                    fontSize: 10.5, color: theme.secondaryText)))
                let nameWidth = measure(attribute.name, 10.5).width
                elements.append(.text(Text(
                    string: attribute.name,
                    center: CGPoint(x: typeX + typeWidth + 8 + nameWidth / 2, y: center),
                    fontSize: 10.5, weight: .medium, color: theme.ink)))
                let badge = attribute.keyBadge
                if !badge.isEmpty {
                    let badgeWidth = measure(badge, 10.5).width
                    elements.append(.text(Text(
                        string: badge,
                        center: CGPoint(x: box.frame.maxX - 10 - badgeWidth / 2, y: center),
                        fontSize: 10.5, weight: .semibold, color: theme.secondaryText)))
                }
                rowY += box.rowHeight
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Crow's-foot cardinality drawn along the edge at `end`, oriented away from
    /// `other` — the platform-free twin of `DiagramRenderer.drawCardinality`.
    /// Ticks for "one", a small circle for "zero", three prongs for "many".
    /// (SVG/Canvas draw butt caps; the CoreGraphics path rounds them — a
    /// sub-pixel difference at the marker tips.)
    private static func cardinalityElements(
        _ card: ERDiagram.Cardinality, at end: CGPoint, from other: CGPoint,
        color: DiagramColor
    ) -> [Element] {
        let angle = atan2(other.y - end.y, other.x - end.x) // inward, up the line
        func p(_ out: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: end.x + out * cos(angle) - side * sin(angle),
                    y: end.y + out * sin(angle) + side * cos(angle))
        }
        let s = Stroke(color: color, width: 1.2)
        var out: [Element] = []
        func tick(_ o: CGFloat, half: CGFloat = 4.5) {
            out.append(.polyline(Polyline(points: [p(o, half), p(o, -half)], stroke: s)))
        }
        func crowsFoot() {
            let apex = p(11, 0)
            var verbs: [PathVerb] = []
            for side in [CGFloat(5), 0, -5] { verbs.append(.move(apex)); verbs.append(.line(p(1, side))) }
            out.append(.shape(Shape(path: .path(verbs), fill: nil, stroke: s)))
        }
        func circle(_ o: CGFloat) {
            let c = p(o, 0)
            out.append(.shape(Shape(
                path: .ellipse(CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                fill: nil, stroke: s)))
        }
        switch card {
        case .one:        tick(6); tick(9.5)
        case .zeroOrOne:  tick(11); circle(5.5)
        case .oneOrMore:  crowsFoot(); tick(14)
        case .zeroOrMore: crowsFoot(); circle(15)
        }
        return out
    }
}
