import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `RadarLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: RadarLayout, …)`
    /// (MermaidRender/DiagramRenderer+Radar.swift). It emits, in the same
    /// painter's order: an optional title, graticule rings (stroked polygons),
    /// spokes with axis labels, then per curve a translucent filled polygon with
    /// a firm outline and vertex dots, and a swatch/label legend below. The rings
    /// and curves are true `.polygon` primitives (they close automatically); all
    /// colors are flat, so nothing is approximated.
    public static func from(_ layout: RadarLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // Graticule rings.
        for ring in layout.rings {
            elements.append(.shape(Shape(
                path: .polygon(ring.points),
                fill: nil, stroke: Stroke(color: theme.ink.withAlpha(0.14), width: 1))))
        }

        // Spokes + axis labels.
        for spoke in layout.spokes {
            elements.append(.polyline(Polyline(
                points: [layout.center, spoke.end],
                stroke: Stroke(color: theme.ink.withAlpha(0.18), width: 1))))
            if !spoke.label.isEmpty {
                elements.append(.text(Text(
                    string: spoke.label, center: spoke.labelPoint,
                    fontSize: 9.5, color: theme.secondaryText)))
            }
        }

        // Curve polygons: translucent fill + firm outline + vertex dots.
        for curve in layout.curves {
            let color = theme.categoricalColor(curve.colorIndex)
            elements.append(.shape(Shape(
                path: .polygon(curve.points),
                fill: color.withAlpha(0.14),
                stroke: Stroke(color: color.withAlpha(0.9), width: 2))))
            for p in curve.points {
                elements.append(.shape(Shape(
                    path: .ellipse(CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)),
                    fill: color, stroke: nil)))
            }
        }

        // Legend.
        for entry in layout.legend {
            let color = theme.categoricalColor(entry.colorIndex)
            elements.append(.shape(Shape(
                path: .ellipse(CGRect(x: entry.swatchCenter.x - 4, y: entry.swatchCenter.y - 4,
                                      width: 8, height: 8)),
                fill: color, stroke: nil)))
            if !entry.label.isEmpty {
                elements.append(.text(leftText(
                    entry.label, at: entry.labelPoint, fontSize: 10,
                    color: theme.ink, measure: measure)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
