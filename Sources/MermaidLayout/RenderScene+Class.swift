import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `ClassLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: ClassLayout, …)`
    /// (MermaidRender/DiagramRenderer+Class.swift). It emits class boxes with a
    /// name compartment plus attribute and method compartments (separated by
    /// hairlines), relation shafts (dashed for realization/dependency), and the
    /// kind's end marker — hollow triangle, filled/hollow diamond, or open
    /// arrowhead — resolved to concrete geometry. Any change to the drawn class
    /// appearance must land in both.
    public static func from(_ layout: ClassLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        let stroke = theme.ink.withAlpha(0.35)
        let hairline = theme.ink.withAlpha(0.18)
        let fill = theme.accent.withAlpha(0.06)

        // 1. Relation shafts (dashed for realization/dependency); the marker is
        //    separate geometry so the shaft carries no arrowhead flag.
        for edge in layout.edges {
            elements.append(.polyline(Polyline(
                points: edge.points,
                stroke: Stroke(color: stroke, width: 1, dashed: edge.kind.dashed))))
        }

        // 2. Relation end markers, then the edge label.
        for edge in layout.edges {
            let approach = edge.points.count > 1 ? edge.points[edge.points.count - 2] : edge.start
            elements += relationMarkerElements(edge.kind, at: edge.end, from: approach,
                                                stroke: stroke, canvas: theme.canvas)
            if let label = edge.label, !label.isEmpty {
                let at = edge.labelAnchor ?? DiagramScene.polylineMidpoint(edge.points)
                elements.append(.text(Text(
                    string: label, center: at, fontSize: 10.5,
                    color: theme.secondaryText, backing: theme.canvas)))
            }
        }

        // 3. Class boxes on top: name / attribute / method compartments.
        for box in layout.boxes {
            elements.append(.shape(Shape(
                path: .roundedRect(box.frame, radius: 4), fill: fill,
                stroke: Stroke(color: stroke, width: 1))))
            elements.append(.text(Text(
                string: box.name,
                center: CGPoint(x: box.frame.midX, y: box.frame.minY + box.nameHeight / 2),
                fontSize: 12, weight: .semibold, color: theme.ink)))

            var rowY = box.frame.minY + box.nameHeight
            let textX = box.frame.minX + 12
            func separator() {
                elements.append(.polyline(Polyline(
                    points: [CGPoint(x: box.frame.minX, y: rowY),
                             CGPoint(x: box.frame.maxX, y: rowY)],
                    stroke: Stroke(color: hairline, width: 1))))
            }
            // Left-anchored member rows: a scene Text is centered, so each shifts
            // by half its measured width (mirrors DiagramRenderer.drawTextLeft).
            func member(_ text: String) {
                let w = measure(text, 10.5).width
                elements.append(.text(Text(
                    string: text,
                    center: CGPoint(x: textX + w / 2, y: rowY + box.rowHeight / 2),
                    fontSize: 10.5, color: theme.secondaryText)))
                rowY += box.rowHeight
            }
            if !box.attributes.isEmpty {
                separator(); rowY += 5
                for attribute in box.attributes { member(attribute) }
            }
            if !box.methods.isEmpty {
                separator(); rowY += 5
                for method in box.methods { member(method) }
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// The relation end marker at `end`, oriented along the final segment from
    /// `origin` — the platform-free twin of `DiagramRenderer.drawRelationMarker`.
    /// The glyph stands off the box border by 3pt, exactly as the drawn marker.
    private static func relationMarkerElements(
        _ kind: ClassDiagram.RelationKind, at end: CGPoint, from origin: CGPoint,
        stroke: DiagramColor, canvas: DiagramColor
    ) -> [Element] {
        let angle = atan2(end.y - origin.y, end.x - origin.x)
        let standoff: CGFloat = 3
        let tip = CGPoint(x: end.x - standoff * cos(angle), y: end.y - standoff * sin(angle))
        func point(_ back: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - back * cos(angle) - side * sin(angle),
                    y: tip.y - back * sin(angle) + side * cos(angle))
        }
        let s = Stroke(color: stroke, width: 1)
        switch kind {
        case .inheritance, .realization:
            // Hollow triangle, canvas-filled so the line doesn't show through.
            return [.shape(Shape(path: .polygon([tip, point(11, 6), point(11, -6)]),
                                 fill: canvas, stroke: s))]
        case .composition, .aggregation:
            // Diamond: composition filled with ink, aggregation hollow (canvas).
            return [.shape(Shape(
                path: .polygon([tip, point(7, 4.5), point(14, 0), point(7, -4.5)]),
                fill: kind == .composition ? stroke : canvas, stroke: s))]
        case .association, .dependency:
            // A filled arrowhead (matches drawArrowhead: length 8.5, spread 0.40).
            let a = atan2(tip.y - origin.y, tip.x - origin.x)
            let length: CGFloat = 8.5, spread: CGFloat = 0.40
            let p2 = CGPoint(x: tip.x - length * cos(a - spread), y: tip.y - length * sin(a - spread))
            let p3 = CGPoint(x: tip.x - length * cos(a + spread), y: tip.y - length * sin(a + spread))
            return [.shape(Shape(path: .polygon([tip, p2, p3]), fill: stroke, stroke: nil))]
        case .link:
            return []
        }
    }
}
