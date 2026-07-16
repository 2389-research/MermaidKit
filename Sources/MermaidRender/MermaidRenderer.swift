#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
#if canImport(AppKit)
import CoreGraphics
import CoreText
import AppKit
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
