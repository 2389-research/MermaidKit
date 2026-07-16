#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
import MermaidLayout

#if canImport(AppKit)
import CoreGraphics
import CoreText
import AppKit
#elseif canImport(UIKit)
import CoreGraphics
import CoreText
import UIKit
#endif

extension DiagramRenderer {

    #if canImport(AppKit) || canImport(UIKit)
    static func font(_ size: CGFloat, weight: PlatformFont.Weight = .regular) -> CTFont {
        PlatformFont.systemFont(ofSize: size, weight: weight) as CTFont
    }
    #endif

    /// Measures `text`, honoring `<br/>`/`\n` line breaks: the width is the
    /// widest line, the height the sum of the line heights. Single-line labels
    /// (the common case) skip the split via a cheap `hasLineBreak` guard.
    static func measure(_ text: String, size: CGFloat, weight: PlatformFont.Weight = .regular) -> CGSize {
        guard hasLineBreak(text) else { return measureLine(text, size: size, weight: weight) }
        let lines = DiagramLayoutEngine.brLines(text)
        switch lines.count {
        case 0: return measureLine("", size: size, weight: weight)
        case 1: return measureLine(lines[0], size: size, weight: weight)
        default:
            let sizes = lines.map { measureLine($0, size: size, weight: weight) }
            return CGSize(width: sizes.map(\.width).max() ?? 0,
                          height: sizes.map(\.height).reduce(0, +))
        }
    }

    /// Measures a single visual line (no line-break handling).
    private static func measureLine(_ text: String, size: CGFloat, weight: PlatformFont.Weight) -> CGSize {
        #if canImport(AppKit) || canImport(UIKit)
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font(size, weight: weight),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        return CGSize(width: width, height: ascent + descent)
        #else
        // Linux: measure with Silica's FontConfig-resolved font metrics.
        // `descent` is negative below the baseline, so height = ascent − descent
        // is the full em span (matching the ascent+descent Apple returns).
        guard let f = linuxFont(weight) else {
            // Last-resort estimate if FontConfig resolves nothing (no font in
            // the image): ~0.6em average glyph advance. Unreached in practice.
            return CGSize(width: CGFloat(text.count) * size * 0.6, height: size + 4)
        }
        return CGSize(width: f.singleLineWidth(text: text, fontSize: size),
                      height: (f.ascent - f.descent) * size)
        #endif
    }

    /// True if `text` might contain a line break — a cheap guard so the common
    /// single-line label skips the `brLines` split. Broad on purpose: a false
    /// positive just takes the (correct) split path, so it only needs to never
    /// MISS a real break (`<br…>`, literal `\n`, or any real newline).
    private static func hasLineBreak(_ text: String) -> Bool {
        text.contains("<br") || text.contains("\\n") || text.contains(where: \.isNewline)
    }

    /// Draws text centered on `center` in a flipped (y-down) context.
    #if DEBUG
    /// Test-only: receives every text rect drawText paints, in layout
    /// coordinates (the CTM applies canvas translation after the fact).
    /// The draw-vs-scene conformance test uses it to prove that everything
    /// the renderer draws is visible to the geometry linter.
    nonisolated(unsafe) static var textCaptureHook: ((String, CGRect) -> Void)?
    /// Suspends capture inside rotated CTMs, where the argument-space rect
    /// would be meaningless.
    nonisolated(unsafe) static var textCaptureSuspended = false
    #endif

    /// Draws `text` centered on `center`, honoring `<br/>`/`\n` line breaks:
    /// lines stack top-to-bottom with the whole block centered on `center`.
    static func drawText(
        _ text: String,
        center: CGPoint,
        size: CGFloat,
        weight: PlatformFont.Weight = .regular,
        color: PlatformColor,
        in context: CGContext
    ) {
        guard !text.isEmpty else { return }
        #if DEBUG
        // One capture for the whole (possibly multi-line) block, so the
        // conformance test sees it against the scene label's block-sized frame.
        if let hook = textCaptureHook, !textCaptureSuspended {
            let measured = measure(text, size: size, weight: weight)
            hook(text, CGRect(x: center.x - measured.width / 2,
                              y: center.y - measured.height / 2,
                              width: measured.width, height: measured.height))
        }
        #endif
        guard hasLineBreak(text) else {
            drawLine(text, center: center, size: size, weight: weight, color: color, in: context)
            return
        }
        let lines = DiagramLayoutEngine.brLines(text)
        switch lines.count {
        case 0: return
        case 1: drawLine(lines[0], center: center, size: size, weight: weight, color: color, in: context)
        default:
            let heights = lines.map { measureLine($0, size: size, weight: weight).height }
            var top = center.y - heights.reduce(0, +) / 2
            for (i, line) in lines.enumerated() {
                drawLine(line, center: CGPoint(x: center.x, y: top + heights[i] / 2),
                         size: size, weight: weight, color: color, in: context)
                top += heights[i]
            }
        }
    }

    /// Draws a single visual line centered on `center` (no line-break handling,
    /// no capture hook).
    private static func drawLine(_ text: String, center: CGPoint, size: CGFloat,
                                 weight: PlatformFont.Weight, color: PlatformColor, in context: CGContext) {
        #if canImport(AppKit) || canImport(UIKit)
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font(size, weight: weight),
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        context.saveGState()
        context.setFillColor(resolvedCGColor(color))
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(
            x: center.x - width / 2,
            y: center.y + (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
        #else
        // Linux: draw with Silica. `show(text:)` treats textMatrix.ty as the
        // text top (it adds ascent·fontSize in a flipped context), so we place
        // the top at center.y − height/2 to vertically center on `center`, and
        // tx at center.x − width/2 to horizontally center.
        guard let f = linuxFont(weight) else { return }
        let width = f.singleLineWidth(text: text, fontSize: size)
        let textH = (f.ascent - f.descent) * size
        context.saveGState()
        context.setFillColor(resolvedCGColor(color))
        context.setFont(f)
        context.fontSize = size
        context.textMatrix = CGAffineTransform(a: 1, b: 0, c: 0, d: 1,
                                               tx: center.x - width / 2,
                                               ty: center.y - textH / 2)
        context.show(text: text)
        context.restoreGState()
        #endif
    }

    /// The true bounding box of everything a box/flowchart diagram draws: the
    /// layout's own `size` (boxes + clamped labels) unioned with every edge
    /// point inflated by the maximum endpoint-marker reach. Markers point
    /// inward along the edge (already inside the point-to-point span) and only
    /// spread a few points perpendicular, so a uniform inflate captures them
    /// without having to know each marker's exact geometry.
    static func contentBounds(size: CGSize, edges: [[CGPoint]]) -> CGRect {
        var box = CGRect(origin: .zero, size: size)
        // Widest perpendicular marker spread across all types: the ER crow's
        // foot / zero-circle and the UML triangle sit within this of the line.
        // Must cover the largest end-marker overhang: arrowheads reach 8.5pt
        // along the edge, ER crow's feet ~18pt along (toward the box, already
        // inside bounds) with ~6pt perpendicular spread. 10pt covers every
        // marker's off-edge spread with margin.
        let markerReach: CGFloat = 10
        for points in edges {
            for p in points {
                box = box.union(CGRect(x: p.x - markerReach, y: p.y - markerReach,
                                       width: markerReach * 2, height: markerReach * 2))
            }
        }
        return box
    }

    /// The standard centred diagram title — one implementation for the nine
    /// chart types that draw one (12.5pt semibold ink, centred at y = 14).
    static func drawDiagramTitle(_ title: String?, width: CGFloat, theme: DiagramTheme, in context: CGContext) {
        guard let title, !title.isEmpty else { return }
        drawText(title, center: CGPoint(x: width / 2, y: 14),
                 size: 12.5, weight: .semibold, color: theme.ink, in: context)
    }

    /// Draws text rotated 90° (reading bottom-to-top) centered on `center`,
    /// for vertical y-axis labels.
    static func drawTextRotated(
        _ text: String, center: CGPoint, size: CGFloat,
        weight: PlatformFont.Weight = .regular, color: PlatformColor, in context: CGContext
    ) {
        guard !text.isEmpty else { return }
        #if DEBUG
        textCaptureSuspended = true
        defer { textCaptureSuspended = false }
        #endif
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -.pi / 2)
        drawText(text, center: .zero, size: size, weight: weight, color: color, in: context)
        context.restoreGState()
    }

    static func drawTextLeft(
        _ text: String, at origin: CGPoint, size: CGFloat,
        weight: PlatformFont.Weight = .regular, color: PlatformColor, in context: CGContext
    ) {
        let measured = measure(text, size: size, weight: weight)
        drawText(text, center: CGPoint(x: origin.x + measured.width / 2, y: origin.y),
                 size: size, weight: weight, color: color, in: context)
    }
}
#endif
