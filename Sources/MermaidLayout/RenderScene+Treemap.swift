import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `TreemapLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: TreemapLayout, …)`
    /// (MermaidRender/DiagramRenderer+Treemap.swift). It emits, in the same
    /// painter's order (groups first, then leaves): for each leaf a tinted fill
    /// plus a stronger hairline border on the half-inset frame, and — only when
    /// the cell is roomy and the label fits — a centered label over a
    /// secondary-text value; for each group an outline (thicker at the top
    /// level) and a left-anchored header label at the top when it fits.
    ///
    /// Colors are flat categorical tints at fixed alpha (no gradient), so no
    /// color is approximated. The width/height guards mirror the CG draw's
    /// exactly so the same labels appear. Any change to the drawn treemap
    /// appearance must land in both.
    public static func from(_ layout: TreemapLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        for cell in layout.cells {
            let tint = theme.categoricalColor(cell.colorIndex)
            if cell.isLeaf {
                let inset = cell.frame.insetBy(dx: 0.5, dy: 0.5)
                elements.append(.shape(Shape(
                    path: .roundedRect(inset, radius: 0),
                    fill: tint.withAlpha(0.30),
                    stroke: Stroke(color: tint.withAlpha(0.6), width: 1))))

                if cell.frame.width > 40, cell.frame.height > 20,
                   measure(cell.label, 10).width <= cell.frame.width - 8 {
                    elements.append(.text(Text(
                        string: cell.label,
                        center: CGPoint(x: cell.frame.midX, y: cell.frame.midY - 5),
                        fontSize: 10, color: theme.ink)))
                    elements.append(.text(Text(
                        string: formatTreemapValue(cell.value),
                        center: CGPoint(x: cell.frame.midX, y: cell.frame.midY + 9),
                        fontSize: 9, color: theme.secondaryText)))
                }
            } else {
                elements.append(.shape(Shape(
                    path: .roundedRect(cell.frame, radius: 0), fill: nil,
                    stroke: Stroke(color: tint.withAlpha(0.7), width: cell.depth == 1 ? 1.5 : 1))))
                if cell.frame.height > 44, cell.frame.width > 40,
                   measure(cell.label, 9.5).width <= cell.frame.width - 12 {
                    elements.append(.text(leftText(
                        cell.label,
                        at: CGPoint(x: cell.frame.minX + 6, y: cell.frame.minY + 10),
                        fontSize: 9.5, weight: .semibold, color: theme.secondaryText,
                        measure: measure)))
                }
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Integer when whole, else one decimal — the treemap value chip's text
    /// (the platform-free twin of `formatTreemapValue`).
    private static func formatTreemapValue(_ value: Double) -> String {
        // Guard non-finite / out-of-Int-range values so `Int(value)` can't trap
        // (the parser already sanitizes numeric input; this keeps the lowering
        // crash-proof regardless).
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
