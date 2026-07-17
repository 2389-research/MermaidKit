import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `GanttLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: GanttLayout, …)`
    /// (MermaidRender/DiagramRenderer+Gantt.swift). It emits, in the same
    /// painter's order: an optional title, section tint bands, day-tick
    /// gridlines with base index labels, then one right-aligned task label plus
    /// a status-tinted bar (or milestone diamond) per row.
    ///
    /// All fills are flat colors, so nothing is approximated. The critical
    /// status uses a fixed sRGB systemRed (matching the Linux `PlatformColor`
    /// constant the CG draw resolves to); on Apple the live dynamic systemRed is
    /// a hair different, an intentional platform detail outside the scene's
    /// resolved-color contract.
    public static func from(_ layout: GanttLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // Section tint bands behind everything.
        for band in layout.sections {
            elements.append(.shape(Shape(
                path: .roundedRect(band.frame, radius: 0),
                fill: theme.categoricalColor(band.colorIndex).withAlpha(0.10), stroke: nil)))
        }

        // Day grid: hairline verticals with a small index label at the base.
        for tick in layout.ticks {
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: tick.x, y: tick.top), CGPoint(x: tick.x, y: tick.bottom)],
                stroke: Stroke(color: theme.hairline, width: 1))))
            if !tick.label.isEmpty {
                elements.append(.text(Text(
                    string: tick.label, center: CGPoint(x: tick.x, y: tick.bottom + 9),
                    fontSize: 9, color: theme.tertiaryText)))
            }
        }

        for bar in layout.bars {
            // Task label, right-aligned into the gutter.
            if !bar.label.isEmpty {
                let measured = measure(bar.label, Double(labelSize))
                elements.append(.text(Text(
                    string: bar.label,
                    center: CGPoint(x: bar.labelPoint.x - measured.width / 2, y: bar.labelPoint.y),
                    fontSize: labelSize, color: theme.secondaryText)))
            }

            let fill = ganttFill(bar.status, theme: theme)
            if bar.isMilestone {
                let f = bar.frame
                elements.append(.shape(Shape(
                    path: .polygon([
                        CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.midY),
                        CGPoint(x: f.midX, y: f.maxY), CGPoint(x: f.minX, y: f.midY),
                    ]),
                    fill: fill, stroke: nil)))
            } else {
                elements.append(.shape(Shape(
                    path: .roundedRect(bar.frame, radius: 3), fill: fill, stroke: nil)))
                if bar.status == .critical {
                    elements.append(.shape(Shape(
                        path: .roundedRect(bar.frame.insetBy(dx: 0.75, dy: 0.75), radius: 3),
                        fill: nil, stroke: Stroke(color: ganttCriticalRed, width: 1.5))))
                }
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Bar fill by task status: active is the full accent, normal a lighter
    /// tint, done a muted ink, critical a warm red. Mirrors `ganttFill`.
    private static func ganttFill(_ status: GanttChart.Status, theme: RenderTheme) -> DiagramColor {
        switch status {
        case .normal: return theme.accent.withAlpha(0.55)
        case .active: return theme.accent
        case .done: return theme.ink.withAlpha(0.28)
        case .critical: return ganttCriticalRed.withAlpha(0.85)
        }
    }

    /// Fixed sRGB systemRed — the `PlatformColor.systemRed` the Linux draw uses.
    private static let ganttCriticalRed = DiagramColor(red: 1.0, green: 0.23, blue: 0.19)

    /// The task-label font size — the `DiagramRenderer.labelSize` twin (10.5).
    private static let labelSize: CGFloat = 10.5
}
