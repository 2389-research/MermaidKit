import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `VennLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: VennLayout, …)`
    /// (MermaidRender/DiagramRenderer+NewTypes.swift). It emits, in the same
    /// painter's order: translucent set fills first (so overlaps blend), then
    /// each circle's rim, then the set labels and region (overlap) labels, both
    /// on opaque-ish canvas chips.
    ///
    /// The overlap "blend" is not an approximation here: the CG draw layers
    /// `.withAlphaComponent(0.26)` ellipse fills and relies on alpha compositing
    /// to darken the lens regions; painting the same translucent `.ellipse`
    /// primitives in the same order reproduces that compositing exactly under the
    /// SVG backend. Labels lower to `backing`-chipped text (canvas at 88%), the
    /// established twin of `drawLabelChip`. Any change to the drawn venn
    /// appearance must land in both.
    public static func from(_ layout: VennLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        func rect(_ c: VennLayout.Circle) -> CGRect {
            CGRect(x: c.center.x - c.radius, y: c.center.y - c.radius,
                   width: c.radius * 2, height: c.radius * 2)
        }

        // 1. Translucent fills first (overlaps blend via compositing).
        for circle in layout.circles {
            elements.append(.shape(Shape(
                path: .ellipse(rect(circle)),
                fill: theme.categoricalColor(circle.colorIndex).withAlpha(0.26), stroke: nil)))
        }
        // 2. Rims.
        for circle in layout.circles {
            elements.append(.shape(Shape(
                path: .ellipse(rect(circle)), fill: nil,
                stroke: Stroke(color: theme.categoricalColor(circle.colorIndex), width: 1.5))))
        }
        // 3. Set labels.
        for circle in layout.circles {
            guard let label = circle.label, !label.isEmpty else { continue }
            elements.append(labelChip(label, center: circle.labelCenter,
                                      weight: .semibold, color: theme.ink, theme: theme))
        }
        // 4. Region (overlap) labels.
        for region in layout.regionLabels {
            elements.append(labelChip(region.text, center: region.center,
                                      weight: .regular, color: theme.secondaryText, theme: theme))
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Text on an opaque-ish canvas chip — the platform-free twin of
    /// `DiagramRenderer.drawLabelChip` (backing canvas at 88%). Used by venn and
    /// cynefin labels.
    static func labelChip(_ text: String, center: CGPoint, weight: FontWeight,
                          color: DiagramColor, theme: RenderTheme) -> Element {
        .text(Text(string: text, center: center, fontSize: 10.5, weight: weight,
                   color: color, backing: theme.canvas.withAlpha(0.88)))
    }
}
