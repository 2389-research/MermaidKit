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
/// backend. Every one of the 30 diagram types lowers to a scene and renders to
/// SVG; these entry points return nil only when `source` fails to parse.
extension MermaidRenderer {

    /// Lowers Mermaid `source` to a platform-free ``RenderScene``, mapping the
    /// theme's resolved colors into a ``RenderTheme``. Every diagram type lowers,
    /// so this is nil only when `source` fails to parse. The top-level
    /// ``RenderScene/from(_:theme:measure:spacing:)`` dispatcher builds the scene.
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
    /// `source` fails to parse (every diagram type renders to SVG).
    public static func svg(source: String, theme: DiagramTheme,
                           spacing: DiagramSpacing = .regular) -> String? {
        guard let scene = renderScene(source: source, theme: theme, spacing: spacing) else { return nil }
        return SVGRenderer.svg(scene)
    }
}
#endif
