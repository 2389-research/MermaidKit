import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers an `ArchitectureLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: ArchitectureLayout, …)`
    /// (MermaidRender/DiagramRenderer+Architecture.swift). It emits, in the same
    /// painter's order: tinted group containers with left-anchored icon + title,
    /// orthogonal wires (45%-ink, round-joined) with 55%-ink arrowheads, and
    /// service boxes / junction dots on top, each labelled (a captioned icon
    /// sits below the label). Any change to the drawn appearance must land in
    /// both.
    public static func from(_ layout: ArchitectureLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // A left-anchored text run: the scene Text is centered, so shift by half
        // its measured width (mirrors DiagramRenderer.drawTextLeft; the platform-
        // free measurer ignores weight, as the box families already do).
        func leftText(_ string: String, at origin: CGPoint, fontSize: CGFloat,
                      weight: FontWeight, color: DiagramColor) {
            let w = measure(string, fontSize).width
            elements.append(.text(Text(
                string: string, center: CGPoint(x: origin.x + w / 2, y: origin.y),
                fontSize: fontSize, weight: weight, color: color)))
        }

        // 1. Group containers behind everything: a tinted rounded box, then the
        //    (optional) icon + semibold title left-anchored at the header.
        for group in layout.groups {
            let tint = theme.categoricalColor(group.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(group.frame, radius: 8),
                fill: tint.withAlpha(theme.prefersDark ? 0.12 : 0.08),
                stroke: Stroke(color: tint.withAlpha(0.55), width: 1))))
            if !group.label.isEmpty {
                var origin = group.titleOrigin
                if !group.icon.isEmpty {
                    leftText(group.icon, at: origin, fontSize: 9, weight: .regular,
                             color: theme.tertiaryText)
                    origin.x += measure(group.icon, 9).width + 6
                }
                leftText(group.label, at: origin, fontSize: 11, weight: .semibold,
                         color: theme.ink)
            }
        }

        // 2. Wires beneath the service boxes so they tuck under the nodes.
        for edge in layout.edges where !edge.points.isEmpty {
            elements.append(.polyline(Polyline(
                points: edge.points, stroke: Stroke(color: theme.ink.withAlpha(0.45), width: 1.25))))
            if edge.arrow, edge.points.count >= 2 {
                elements += filledArrowheadElements(
                    at: edge.points[edge.points.count - 1], from: edge.points[edge.points.count - 2],
                    color: theme.ink)
            }
        }

        // 3. Service boxes / junction dots on top.
        for svc in layout.services {
            let tint = theme.categoricalColor(svc.colorIndex)
            if svc.isJunction {
                let f = svc.frame
                elements.append(.shape(Shape(
                    path: .ellipse(f), fill: theme.canvas, stroke: nil)))
                elements.append(.shape(Shape(
                    path: .ellipse(f.insetBy(dx: 0.75, dy: 0.75)),
                    fill: nil, stroke: Stroke(color: theme.ink.withAlpha(0.55), width: 1.25))))
                elements.append(.shape(Shape(
                    path: .ellipse(f.insetBy(dx: f.width * 0.32, dy: f.height * 0.32)),
                    fill: theme.ink.withAlpha(0.55), stroke: nil)))
                continue
            }

            elements.append(.shape(Shape(
                path: .roundedRect(svc.frame, radius: 6),
                fill: tint.withAlpha(theme.prefersDark ? 0.22 : 0.14),
                stroke: Stroke(color: tint.withAlpha(0.65), width: 1))))

            let f = svc.frame
            if svc.icon.isEmpty {
                elements.append(.text(Text(
                    string: svc.label, center: CGPoint(x: f.midX, y: f.midY),
                    fontSize: 11.5, weight: .medium, color: theme.ink)))
            } else {
                elements.append(.text(Text(
                    string: svc.label, center: CGPoint(x: f.midX, y: f.midY - 5),
                    fontSize: 11.5, weight: .medium, color: theme.ink)))
                elements.append(.text(Text(
                    string: svc.icon, center: CGPoint(x: f.midX, y: f.maxY - 9),
                    fontSize: 8.5, color: theme.tertiaryText)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
