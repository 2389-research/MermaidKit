import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `QuadrantLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: QuadrantLayout, …)`
    /// (MermaidRender/DiagramRenderer+Quadrant.swift). It emits, in the same
    /// painter's order: an optional title, four categorical tint quarters, the
    /// plot border and center cross, the quadrant/axis labels (y-axis labels
    /// rotated), then accent-filled point dots with left-aligned labels. All
    /// fills/strokes are flat colors; nothing is approximated.
    public static func from(_ layout: QuadrantLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // Tint quarters (Mermaid quadrant order → categorical palette).
        for (index, rect) in layout.quadrantRects.enumerated() {
            elements.append(.shape(Shape(
                path: .roundedRect(rect, radius: 0),
                fill: theme.categoricalColor(index).withAlpha(0.08), stroke: nil)))
        }

        // Plot border and center cross.
        let cross = theme.ink.withAlpha(0.28)
        elements.append(.shape(Shape(
            path: .roundedRect(layout.plotRect, radius: 0),
            fill: nil, stroke: Stroke(color: cross, width: 1))))
        elements.append(.polyline(Polyline(
            points: [CGPoint(x: layout.plotRect.midX, y: layout.plotRect.minY),
                     CGPoint(x: layout.plotRect.midX, y: layout.plotRect.maxY)],
            stroke: Stroke(color: cross, width: 1))))
        elements.append(.polyline(Polyline(
            points: [CGPoint(x: layout.plotRect.minX, y: layout.plotRect.midY),
                     CGPoint(x: layout.plotRect.maxX, y: layout.plotRect.midY)],
            stroke: Stroke(color: cross, width: 1))))

        for label in layout.quadrantLabels {
            elements.append(.text(Text(
                string: label.text, center: label.center,
                fontSize: 10, weight: .semibold, color: theme.tertiaryText)))
        }
        for label in layout.xAxisLabels {
            elements.append(.text(Text(
                string: label.text, center: label.center,
                fontSize: 9.5, color: theme.secondaryText)))
        }
        for label in layout.yAxisLabels {
            elements.append(.text(Text(
                string: label.text, center: label.center,
                fontSize: 9.5, color: theme.secondaryText, rotation: -.pi / 2)))
        }

        for point in layout.points {
            elements.append(.shape(Shape(
                path: .ellipse(CGRect(x: point.position.x - layout.dotRadius,
                                      y: point.position.y - layout.dotRadius,
                                      width: layout.dotRadius * 2, height: layout.dotRadius * 2)),
                fill: theme.accent, stroke: nil)))
            if !point.label.isEmpty {
                elements.append(.text(leftText(
                    point.label, at: point.labelPoint, fontSize: labelSize,
                    color: theme.ink, measure: measure)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    private static let labelSize: CGFloat = 10.5
}
