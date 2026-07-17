import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `TimelineLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: TimelineLayout, …)`
    /// (MermaidRender/DiagramRenderer+Timeline.swift). It emits, in the same
    /// painter's order: an optional title, section tint bands with their names,
    /// the vertical spine, then per period a spine→card connector, the spine
    /// dot, a right-aligned period label, and section-tinted event cards with
    /// left-aligned text. All fills/strokes are flat colors; nothing is
    /// approximated.
    public static func from(_ layout: TimelineLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        // Section tint bands (and their names) behind the spine and cards.
        for band in layout.sections {
            elements.append(.shape(Shape(
                path: .roundedRect(band.frame, radius: 6),
                fill: theme.categoricalColor(band.colorIndex).withAlpha(0.10), stroke: nil)))
            if !band.name.isEmpty {
                elements.append(.text(leftText(
                    band.name, at: CGPoint(x: band.frame.minX + 8, y: band.frame.minY + 10),
                    fontSize: 9.5, weight: .semibold, color: theme.tertiaryText, measure: measure)))
            }
        }

        // The vertical spine the dots sit on.
        if layout.spineBottom > layout.spineTop {
            elements.append(.polyline(Polyline(
                points: [CGPoint(x: layout.spineX, y: layout.spineTop),
                         CGPoint(x: layout.spineX, y: layout.spineBottom)],
                stroke: Stroke(color: theme.ink.withAlpha(0.25), width: 2))))
        }

        for period in layout.periods {
            // Connector from the spine to the first event card's row.
            if let first = period.events.first {
                elements.append(.polyline(Polyline(
                    points: [period.dot, CGPoint(x: first.frame.minX, y: period.dot.y)],
                    stroke: Stroke(color: theme.ink.withAlpha(0.18), width: 1))))
            }

            // Node dot on the spine.
            let r: CGFloat = 4
            elements.append(.shape(Shape(
                path: .ellipse(CGRect(x: period.dot.x - r, y: period.dot.y - r, width: r * 2, height: r * 2)),
                fill: theme.accent, stroke: nil)))

            // Period label, right-aligned into the gutter.
            if !period.label.isEmpty {
                let measured = measure(period.label, Double(labelSize))
                elements.append(.text(Text(
                    string: period.label,
                    center: CGPoint(x: period.labelPoint.x - measured.width / 2, y: period.labelPoint.y),
                    fontSize: labelSize, weight: .semibold, color: theme.secondaryText)))
            }

            // Event cards, tinted by section (else by period).
            for event in period.events {
                let tint = theme.categoricalColor(event.colorIndex)
                elements.append(.shape(Shape(
                    path: .roundedRect(event.frame, radius: 5),
                    fill: tint.withAlpha(0.16), stroke: nil)))
                elements.append(.shape(Shape(
                    path: .roundedRect(event.frame.insetBy(dx: 0.5, dy: 0.5), radius: 5),
                    fill: nil, stroke: Stroke(color: tint.withAlpha(0.45), width: 1))))
                if !event.text.isEmpty {
                    elements.append(.text(leftText(
                        event.text, at: CGPoint(x: event.frame.minX + 10, y: event.frame.midY),
                        fontSize: labelSize, color: theme.ink, measure: measure)))
                }
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    private static let labelSize: CGFloat = 10.5
}
