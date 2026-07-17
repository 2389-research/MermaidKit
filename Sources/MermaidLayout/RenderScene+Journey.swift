import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `JourneyLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: JourneyLayout, …)`
    /// (MermaidRender/DiagramRenderer+Journey.swift). It emits, in the same
    /// painter's order: an optional title, section tint bands with their names,
    /// then per task a graded satisfaction badge with its digit, a left-aligned
    /// task label, and a muted actor list.
    ///
    /// The badge colors (1 red → 5 green) are fixed sRGB constants matching the
    /// Linux `PlatformColor` system colors the CG draw resolves to; on Apple the
    /// live dynamic system colors differ slightly, an intentional platform
    /// detail. All fills are flat, so nothing else is approximated.
    public static func from(_ layout: JourneyLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

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

        for task in layout.tasks {
            // Satisfaction badge: color graded 1 (red) → 5 (green), digit inside.
            let radius = layout.scoreDiameter / 2
            elements.append(.shape(Shape(
                path: .ellipse(CGRect(x: task.scoreCenter.x - radius, y: task.scoreCenter.y - radius,
                                      width: layout.scoreDiameter, height: layout.scoreDiameter)),
                fill: journeyScoreColor(task.score), stroke: nil)))
            elements.append(.text(Text(
                string: "\(task.score)", center: task.scoreCenter,
                fontSize: 11, weight: .semibold, color: scoreDigitWhite)))

            // Task label.
            if !task.label.isEmpty {
                elements.append(.text(leftText(
                    task.label, at: task.labelPoint, fontSize: labelSize,
                    color: theme.ink, measure: measure)))
            }

            // Actors, muted.
            if !task.actors.isEmpty {
                elements.append(.text(leftText(
                    task.actors, at: task.actorsPoint, fontSize: labelSize,
                    color: theme.tertiaryText, measure: measure)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Satisfaction badge color: 1 red, 2 orange, 3 amber, 4 lime, 5 green —
    /// the fixed sRGB twin of `journeyScoreColor`.
    private static func journeyScoreColor(_ score: Int) -> DiagramColor {
        switch score {
        case 1: return DiagramColor(red: 1.0, green: 0.23, blue: 0.19)
        case 2: return DiagramColor(red: 1.0, green: 0.58, blue: 0.0)
        case 3: return DiagramColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 0.95)
        case 4: return DiagramColor(red: 0.52, green: 0.72, blue: 0.20)
        default: return DiagramColor(red: 0.20, green: 0.78, blue: 0.35)
        }
    }

    private static let scoreDigitWhite = DiagramColor(red: 1, green: 1, blue: 1)
    private static let labelSize: CGFloat = 10.5
}
