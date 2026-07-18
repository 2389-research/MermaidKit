import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers an `IshikawaLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: IshikawaLayout, …)`
    /// (MermaidRender/DiagramRenderer+MethodDiagrams.swift). It emits, in the
    /// same painter's order: the horizontal spine with an arrowhead into the
    /// problem head box, the accent-tinted head box + problem text, then per
    /// major cause an angled tinted rib with a chipped bold label and its
    /// hairline sub-cause twigs with chipped labels.
    ///
    /// Ribs and twigs are straight segments and the spine head lowers to an
    /// `endArrow` polyline whose head matches `drawArrowhead`, so no geometry is
    /// approximated. Rib/twig labels lower to `backing`-chipped runs (canvas at
    /// 88%), the twin of `drawChippedText`. Any change to the drawn ishikawa
    /// appearance must land in both.
    public static func from(_ layout: IshikawaLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // 1. Spine with an arrowhead into the head box.
        elements.append(.polyline(Polyline(
            points: [layout.spineStart, layout.spineEnd],
            stroke: Stroke(color: theme.ink, width: 2), endArrow: true)))

        // 2. Head box (the problem).
        elements.append(.shape(Shape(
            path: .roundedRect(layout.headFrame, radius: 6),
            fill: theme.accent.withAlpha(0.16), stroke: Stroke(color: theme.accent, width: 1.4))))
        elements.append(.text(Text(
            string: layout.problem,
            center: CGPoint(x: layout.headFrame.midX, y: layout.headFrame.midY),
            fontSize: 12, weight: .semibold, color: theme.ink)))

        // 3. Ribs + twigs.
        for rib in layout.ribs {
            let tint = theme.categoricalColor(rib.colorIndex)
            elements.append(.polyline(Polyline(
                points: [rib.from, rib.to], stroke: Stroke(color: tint, width: 1.6))))
            elements.append(.text(Text(
                string: rib.label, center: rib.labelCenter, fontSize: 10.5,
                weight: .semibold, color: theme.ink, backing: theme.canvas.withAlpha(0.88))))
            for twig in rib.twigs {
                elements.append(.polyline(Polyline(
                    points: [twig.from, twig.to], stroke: Stroke(color: theme.hairline, width: 1))))
                elements.append(.text(Text(
                    string: twig.label, center: twig.labelCenter, fontSize: 10.5,
                    color: theme.secondaryText, backing: theme.canvas.withAlpha(0.88))))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
