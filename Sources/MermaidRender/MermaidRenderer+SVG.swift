#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
#if canImport(AppKit)
import CoreGraphics
import AppKit
#elseif canImport(UIKit)
import CoreGraphics
import UIKit
#endif
import MermaidLayout

/// End-to-end SVG / `RenderScene` entry points — the bridge from Mermaid source
/// to the platform-free scene IR (MermaidLayout/RenderScene) and its SVG
/// backend. This slice covers the flowchart family; other diagram types return
/// nil until Phase 0b lowers them.
extension MermaidRenderer {

    /// Lowers Mermaid `source` to a platform-free ``RenderScene``, mapping the
    /// theme's resolved colors into a ``RenderTheme``. Nil when the source isn't
    /// a supported diagram (this slice: flowchart / graph only).
    public static func renderScene(source: String, theme: DiagramTheme,
                                   spacing: DiagramSpacing = .regular) -> RenderScene? {
        guard let diagram = MermaidParser.parse(source) else { return nil }
        let renderTheme = RenderTheme(
            ink: theme.resolved.ink,
            accent: theme.resolved.accent,
            canvas: theme.resolved.canvas,
            hairline: theme.resolved.hairline,
            secondaryText: theme.resolved.secondaryText)
        switch diagram {
        case .flowchart(let chart):
            let layout = DiagramLayoutEngine.layout(chart, measure: textMeasurer, spacing: spacing)
            return RenderScene.from(layout, theme: renderTheme, measure: textMeasurer)
        // Phase 0b: sequence, class, state, ER, … lower here.
        default:
            return nil
        }
    }

    /// Renders Mermaid `source` to a standalone SVG document string, or nil when
    /// the source isn't a supported diagram (this slice: flowchart / graph).
    public static func svg(source: String, theme: DiagramTheme,
                           spacing: DiagramSpacing = .regular) -> String? {
        guard let scene = renderScene(source: source, theme: theme, spacing: spacing) else { return nil }
        return SVGRenderer.svg(scene)
    }
}
#endif
