import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `TreeViewLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: TreeViewLayout, …)`
    /// (MermaidRender/DiagramRenderer+NewTypes.swift). It emits, in the same
    /// painter's order: hairline elbow guide lines under everything, then per row
    /// a folder or file glyph and a left-anchored label (semibold for a
    /// directory) plus an optional muted description after it.
    ///
    /// The folder glyph is a filled+stroked tab and body; the file glyph is a
    /// folded-corner outline (a `.path` silhouette plus a small fold stroke) —
    /// both exact replicas of the CG draw. No color or curve is approximated.
    /// Any change to the drawn tree view appearance must land in both.
    public static func from(_ layout: TreeViewLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // 1. Guide lines first, under everything.
        for connector in layout.connectors where connector.count >= 2 {
            elements.append(.polyline(Polyline(
                points: connector, stroke: Stroke(color: theme.hairline, width: 1))))
        }

        // 2. Rows: glyph + label (+ description).
        for row in layout.rows {
            elements += treeGlyphElements(row: row, theme: theme)
            elements.append(.text(leftText(
                row.label, at: row.textOrigin, fontSize: 12,
                weight: row.isDirectory ? .semibold : .regular, color: theme.ink,
                measure: measure)))
            if let description = row.description, let at = row.descriptionOrigin {
                elements.append(.text(leftText(
                    description, at: at, fontSize: 10.5, color: theme.tertiaryText,
                    measure: measure)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// The folder / folded-corner file glyph for a tree row — the platform-free
    /// twin of `DiagramRenderer.drawTreeGlyph`.
    private static func treeGlyphElements(row: TreeViewLayout.Row, theme: RenderTheme) -> [Element] {
        let f = row.glyphFrame
        if row.isDirectory {
            let tint = theme.accent
            let tab = CGRect(x: f.minX, y: f.minY + 1, width: f.width * 0.45, height: 3)
            let body = CGRect(x: f.minX, y: f.minY + 3, width: f.width, height: f.height - 4)
            return [
                .shape(Shape(path: .roundedRect(tab, radius: 1),
                             fill: tint.withAlpha(0.28), stroke: Stroke(color: tint, width: 1))),
                .shape(Shape(path: .roundedRect(body, radius: 2),
                             fill: tint.withAlpha(0.28), stroke: Stroke(color: tint, width: 1))),
            ]
        }
        let fold: CGFloat = 4
        let stroke = Stroke(color: theme.secondaryText, width: 1)
        return [
            .shape(Shape(path: .path([
                .move(CGPoint(x: f.minX + 1, y: f.minY)),
                .line(CGPoint(x: f.maxX - fold, y: f.minY)),
                .line(CGPoint(x: f.maxX - 1, y: f.minY + fold)),
                .line(CGPoint(x: f.maxX - 1, y: f.maxY)),
                .line(CGPoint(x: f.minX + 1, y: f.maxY)),
                .close,
            ]), fill: theme.canvas, stroke: stroke)),
            .shape(Shape(path: .path([
                .move(CGPoint(x: f.maxX - fold, y: f.minY)),
                .line(CGPoint(x: f.maxX - fold, y: f.minY + fold)),
                .line(CGPoint(x: f.maxX - 1, y: f.minY + fold)),
            ]), fill: nil, stroke: stroke)),
        ]
    }
}
