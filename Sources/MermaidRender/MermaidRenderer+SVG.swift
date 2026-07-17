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
/// backend. Covers the flowchart family plus the Phase 0b-1 (state, ER, class,
/// sequence), 0b-2 (c4, architecture, block, swimlane, sankey, requirement), and
/// 0b-3a (pie, gantt, timeline, journey, quadrant, xychart, radar, packet,
/// kanban) families; other diagram types return nil until a later slice lowers
/// them.
extension MermaidRenderer {

    /// Lowers Mermaid `source` to a platform-free ``RenderScene``, mapping the
    /// theme's resolved colors into a ``RenderTheme``. Nil when the source isn't
    /// a family that lowers yet (Phase 0a: flowchart; Phase 0b: + state, ER,
    /// class, sequence). The top-level ``RenderScene/from(_:theme:measure:spacing:)``
    /// dispatcher decides which families produce a scene.
    public static func renderScene(source: String, theme: DiagramTheme,
                                   spacing: DiagramSpacing = .regular) -> RenderScene? {
        guard let diagram = MermaidParser.parse(source) else { return nil }
        let renderTheme = RenderTheme(
            ink: theme.resolved.ink,
            accent: theme.resolved.accent,
            canvas: theme.resolved.canvas,
            hairline: theme.resolved.hairline,
            secondaryText: theme.resolved.secondaryText,
            tertiaryText: theme.resolved.tertiaryText,
            palette: theme.resolved.palette,
            prefersDark: theme.prefersDark)
        return RenderScene.from(diagram, theme: renderTheme, measure: textMeasurer, spacing: spacing)
    }

    /// Renders Mermaid `source` to a standalone SVG document string, or nil when
    /// the source isn't a family that lowers yet (Phase 0a + 0b families).
    public static func svg(source: String, theme: DiagramTheme,
                           spacing: DiagramSpacing = .regular) -> String? {
        guard let scene = renderScene(source: source, theme: theme, spacing: spacing) else { return nil }
        return SVGRenderer.svg(scene)
    }
}
#endif
