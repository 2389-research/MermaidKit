#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
#if canImport(AppKit)
import CoreGraphics
import CoreText
import AppKit
import ImageIO
import UniformTypeIdentifiers
#elseif canImport(UIKit)
import CoreGraphics
import CoreText
import UIKit
#endif
import MermaidLayout

/// Public entry points for host apps.
public enum MermaidRenderer {

    /// Renders Mermaid source to a native image, or nil if the source isn't a
    /// recognized Mermaid diagram. The image auto-sizes to the diagram bounds.
    public static func image(source: String, theme: DiagramTheme,
                             spacing: DiagramSpacing = .regular) -> PlatformImage? {
        // Apple pulls the image back out of the cached attachment string; Linux
        // has no NSTextAttachment, so it renders directly (and uncached) via the
        // Silica backend. Same return type, different path.
        #if canImport(AppKit) || canImport(UIKit)
        guard let attr = attachmentString(source: source, theme: theme, spacing: spacing),
              attr.length > 0,
              let attachment = attr.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        else { return nil }
        return attachment.image
        #else
        return DiagramRenderer.renderImage(source: source, theme: theme, spacing: spacing)
        #endif
    }

    /// Renders off the calling thread — for hosts batching many diagrams or
    /// staying paranoid about main-thread time (a single cold render is
    /// under ten milliseconds for most types; the worst dense fixture is
    /// ~25 ms rasterized). Shares the sync API's render cache. Deliberately
    /// NOT an overload of `image`: a same-name async twin silently captures
    /// every call in async contexts, making the cheap sync cache-hit path
    /// unreachable there. Cancelling the calling task cancels the render.
    public static func renderImage(source: String, theme: DiagramTheme,
                                   spacing: DiagramSpacing = .regular) async -> sending PlatformImage? {
        // NSImage's Sendable conformance is explicitly unavailable, so the
        // image crosses the task boundary in a transfer box. This is sound:
        // the value is either freshly rendered in this task or a fresh COPY
        // from the cache (see attributedString(for:)), so the box holds the
        // only reference. (Also keeps the code compiling across Swift 6.0-6.2,
        // whose region-transfer inference differs here.)
        struct Transfer: @unchecked Sendable { let image: PlatformImage? }
        let task = Task.detached(priority: .userInitiated) { () -> Transfer in
            guard !Task.isCancelled else { return Transfer(image: nil) }
            return Transfer(image: image(source: source, theme: theme, spacing: spacing))
        }
        return await withTaskCancellationHandler {
            await task.value.image
        } onCancel: {
            task.cancel()
        }
    }

    #if canImport(AppKit) || canImport(UIKit)
    /// The diagram as a single-attachment attributed string, for embedding in
    /// a text view (how a markdown editor embeds it). Nil when not Mermaid.
    /// Apple platforms only (NSTextAttachment); on Linux use ``image`` and its
    /// `pngData()`.
    public static func attachmentString(source: String, theme: DiagramTheme,
                                        spacing: DiagramSpacing = .regular) -> NSAttributedString? {
        DiagramRenderer.attachmentString(source: source, theme: theme, spacing: spacing)
    }
    #endif

    /// A VoiceOver-ready description of the diagram (type, scale, leading
    /// content) — what ``MermaidView`` reads to assistive technologies.
    /// Nil when the source doesn't parse.
    public static func altText(source: String) -> String? {
        MermaidAltText.describe(source: source)
    }

    /// The diagram as PNG-encoded bytes, or nil when the source doesn't parse
    /// or encoding fails. Reuses the full rasterizer (``image``), so this is the
    /// exact desktop render — the transport for the terminal Kitty-graphics path.
    /// UIKit vends `UIImage.pngData()` and Linux `PlatformImage.pngData()`
    /// directly; AppKit's `NSImage` has none, so the CGImage is encoded through
    /// `CGImageDestination`.
    public static func pngData(source: String, theme: DiagramTheme,
                               spacing: DiagramSpacing = .regular) -> Data? {
        guard let img = image(source: source, theme: theme, spacing: spacing) else { return nil }
        return encodePNG(img)
    }

    /// Renders an already-parsed diagram (e.g. from ``DOTParser``) to a native
    /// image, bypassing the Mermaid parser so a non-Mermaid front-end reuses the
    /// exact same layout/draw pipeline. Uncached (no source string to key on).
    public static func image(diagram: MermaidDiagram, theme: DiagramTheme,
                             spacing: DiagramSpacing = .regular) -> PlatformImage? {
        #if canImport(AppKit) || canImport(UIKit)
        return DiagramRenderer.image(for: diagram, title: nil, theme: theme, spacing: spacing)
        #elseif canImport(SilicaCairo)
        return DiagramRenderer.renderImage(diagram: diagram, title: nil, theme: theme, spacing: spacing)
        #else
        return nil
        #endif
    }

    /// PNG bytes for an already-parsed diagram — the Kitty-graphics transport
    /// for a DOT source.
    public static func pngData(diagram: MermaidDiagram, theme: DiagramTheme,
                               spacing: DiagramSpacing = .regular) -> Data? {
        guard let img = image(diagram: diagram, theme: theme, spacing: spacing) else { return nil }
        return encodePNG(img)
    }

    private static func encodePNG(_ img: PlatformImage) -> Data? {
        #if canImport(AppKit)
        var rect = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
        #elseif canImport(UIKit)
        return img.pngData()
        #else
        return img.pngData()
        #endif
    }

    /// The diagram rasterized to an opaque RGBA pixel grid sized for the
    /// half-block terminal renderer (Tier 3). `targetWidth` is the pixel width
    /// (= terminal columns); the height is derived to preserve the diagram's
    /// aspect (each half-cell is roughly square), rounded to the nearest pixel
    /// and then bumped up to an even count so every cell owns a full top/bottom
    /// pixel pair.
    ///
    /// The image is composited over `background` (the theme canvas color) so the
    /// returned pixels are fully opaque. The backing buffer is `premultipliedLast`,
    /// but with every pixel at alpha 255 the RGB values equal their straight-alpha
    /// form — transparent margins take the theme canvas and carry no surprises.
    /// Returns the flat RGBA byte buffer plus its dimensions, or nil when the
    /// source doesn't render or the platform lacks a CGImage path.
    public static func rgbaRaster(source: String, theme: DiagramTheme,
                                  spacing: DiagramSpacing = .regular,
                                  targetWidth: Int,
                                  background: (r: UInt8, g: UInt8, b: UInt8))
        -> (pixels: [UInt8], width: Int, height: Int)? {
        #if canImport(AppKit) || canImport(UIKit)
        guard let img = image(source: source, theme: theme, spacing: spacing) else { return nil }
        return raster(from: img, targetWidth: targetWidth, background: background)
        #else
        return nil
        #endif
    }

    /// Half-block RGBA raster for an already-parsed diagram — the Tier-3
    /// terminal path for a DOT source.
    public static func rgbaRaster(diagram: MermaidDiagram, theme: DiagramTheme,
                                  spacing: DiagramSpacing = .regular,
                                  targetWidth: Int,
                                  background: (r: UInt8, g: UInt8, b: UInt8))
        -> (pixels: [UInt8], width: Int, height: Int)? {
        #if canImport(AppKit) || canImport(UIKit)
        guard let img = image(diagram: diagram, theme: theme, spacing: spacing) else { return nil }
        return raster(from: img, targetWidth: targetWidth, background: background)
        #else
        return nil
        #endif
    }

    /// Upper bound (pixels) on a raster's width and derived height — a cap in
    /// the spirit of `MermaidParser.maxTextSize`/`maxEdges` that keeps a hostile
    /// `targetWidth` from trapping or exhausting memory.
    static let maxRasterDimension = 4096

    #if canImport(AppKit) || canImport(UIKit)
    private static func raster(from img: PlatformImage, targetWidth: Int,
                               background: (r: UInt8, g: UInt8, b: UInt8))
        -> (pixels: [UInt8], width: Int, height: Int)? {
        // Cap the requested width like the parser input caps: an unbounded
        // `targetWidth` would trap on the `Double`→`Int` height conversion or
        // exhaust memory allocating `bytesPerRow * h`. A terminal is at most a
        // few hundred columns wide, so 4096 px is comfortably generous.
        guard (1...maxRasterDimension).contains(targetWidth) else { return nil }
        #if canImport(AppKit)
        var rect = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        #else
        guard let cg = img.cgImage else { return nil }
        #endif
        let srcW = cg.width, srcH = cg.height
        guard srcW > 0, srcH > 0 else { return nil }

        let w = targetWidth
        // Derive height in `Double` and reject any non-finite / out-of-range
        // result before the `Int` conversion so an extreme aspect ratio can't
        // trap or blow the allocation.
        let hd = (Double(w) * Double(srcH) / Double(srcW)).rounded()
        guard hd.isFinite, hd <= Double(maxRasterDimension) else { return nil }
        var h = Int(hd)
        if h < 2 { h = 2 }
        if h % 2 != 0 { h += 1 }  // even → whole top/bottom cell pairs

        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Pre-fill with the theme canvas so anti-aliased/transparent pixels
            // composite over the right color and come out opaque.
            ctx.setFillColor(red: CGFloat(background.r) / 255.0,
                             green: CGFloat(background.g) / 255.0,
                             blue: CGFloat(background.b) / 255.0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // CGContext is bottom-left origin; flip so buffer row 0 is the image
            // top (the order the half-block renderer walks).
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        return (buffer, w, h)
    }
    #endif

    /// The diagram as single-page vector PDF data — same layout and drawing
    /// as ``image(source:theme:spacing:)``, but resolution-independent: the
    /// export/print path. Nil when the source doesn't parse.
    public static func pdfData(source: String, theme: DiagramTheme,
                               spacing: DiagramSpacing = .regular) -> Data? {
        DiagramRenderer.pdfData(source: source, theme: theme, spacing: spacing)
    }

    /// The CoreText measurer the renderer itself uses — pass to
    /// `DiagramLayoutEngine.layout`/`DiagramScene.lower` so layout geometry and
    /// lint checks see the same text metrics the render does.
    public static let textMeasurer: @Sendable (String, Double) -> CGSize = { text, size in
        DiagramRenderer.measure(text, size: CGFloat(size))
    }
}
#endif
