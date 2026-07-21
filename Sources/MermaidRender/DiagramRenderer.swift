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

/// Draws parsed Mermaid diagrams in the Graphite design language: SF
/// labels, hairline strokes, radius-8 blocks, semantic tints. Layout comes
/// from the platform-free MermaidLayout engine; this file only draws.
enum DiagramRenderer {

    // Render cache is Apple-only: it is NSCache-backed and entered via the
    // attachmentString/NSTextAttachment path. The Linux backend renders directly
    // and uncached (see `renderImage`); a host batching many diagrams there
    // should cache the returned PlatformImage itself.
    #if canImport(AppKit) || canImport(UIKit)
    private final class Entry {
        let image: PlatformImage
        /// VoiceOver description, attached to the image so accessibility
        /// survives the cache round-trip.
        let altText: String?
        init(image: PlatformImage, altText: String?) {
            self.image = image
            self.altText = altText
        }
    }

    /// Cache key that hashes its inputs ONCE (in `init`) and keeps the source
    /// by reference for exact equality. The old key interpolated the full
    /// source into a fresh `"mermaid|…|\(source)"` string on every call — an
    /// O(source length) allocation + copy paid even on cache *hits* (each
    /// SwiftUI `body` pass). This keeps the source `String` (copy-on-write, no
    /// copy), precomputes the hash so `NSCache` bucket lookup is O(1), and only
    /// walks the source in `isEqual:` on an actual hash collision or a true
    /// match — so hit/miss semantics are byte-for-byte the old key's, just
    /// without the per-call concatenation.
    private final class RenderKey: NSObject, NSCopying {
        let source: String
        let theme: String
        let spacing: String
        private let precomputedHash: Int
        init(source: String, theme: String, spacing: String) {
            self.source = source
            self.theme = theme
            self.spacing = spacing
            var hasher = Hasher()
            hasher.combine(theme)
            hasher.combine(spacing)
            hasher.combine(source)
            self.precomputedHash = hasher.finalize()
            super.init()
        }
        override var hash: Int { precomputedHash }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? RenderKey else { return false }
            return precomputedHash == other.precomputedHash
                && theme == other.theme && spacing == other.spacing && source == other.source
        }
        // Immutable, so a "copy" (NSCache retains keys via NSCopying) is self.
        func copy(with zone: NSZone? = nil) -> Any { self }
    }

    /// NSCache is documented thread-safe ("you can add, remove, and query
    /// items in the cache from different threads without having to lock the
    /// cache yourself") but predates Sendable; this wrapper carries that
    /// guarantee into strict concurrency, and bounds the cache so a host
    /// rendering many large diagrams can't accumulate unbounded image memory
    /// (NSCache also evicts under system memory pressure).
    private final class RenderCache: @unchecked Sendable {
        private let store = NSCache<RenderKey, Entry>()
        init(totalCostLimit: Int) { store.totalCostLimit = totalCostLimit }
        func object(forKey key: RenderKey) -> Entry? { store.object(forKey: key) }
        func setObject(_ entry: Entry, forKey key: RenderKey, cost: Int) {
            store.setObject(entry, forKey: key, cost: cost)
        }
    }

    /// ~64 MB of rendered diagrams (cost = estimated decoded bytes).
    private static let cache = RenderCache(totalCostLimit: 64 << 20)
    #endif

    /// A rendered attachment for mermaid source, or nil when the dialect
    /// isn't supported yet (caller keeps the styled-source fallback).

    /// The per-type layout + draw plan every output backend shares: raster
    /// (attachmentString/image) and PDF both consume it, so a new diagram
    /// type wired here reaches every format at once.
    static func renderPlan(
        for diagram: MermaidDiagram, theme: DiagramTheme, spacing: DiagramSpacing
    ) -> (size: CGSize, edgePolylines: [[CGPoint]], draw: (CGContext) -> Void) {
        let measure: DiagramTextMeasurer = { text, fontSize in
            Self.measure(text, size: CGFloat(fontSize))
        }
        let size: CGSize
        let draw: (CGContext) -> Void
        // Edge polylines whose routes or endpoint markers can reach past the
        // layout's own `size`; folded into the content bounds below so they
        // never clip. Self-contained types (pie/sequence/gantt) leave this
        // empty — their `size` already covers everything they draw.
        var edgePolylines: [[CGPoint]] = []
        switch diagram {
        case .flowchart(let chart):
            let layout = DiagramLayoutEngine.layout(chart, measure: measure, spacing: spacing)
            size = layout.size
            edgePolylines = layout.edges.map(\.points)
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .sequence(let sequence):
            let layout = DiagramLayoutEngine.layout(sequence, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .pie(let pie):
            let layout = DiagramLayoutEngine.layout(pie, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .classDiagram(let classDiagram):
            let layout = DiagramLayoutEngine.layout(classDiagram, measure: measure, spacing: spacing)
            size = layout.size
            edgePolylines = layout.edges.map(\.points)
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .er(let er):
            let layout = DiagramLayoutEngine.layout(er, measure: measure, spacing: spacing)
            size = layout.size
            edgePolylines = layout.edges.map(\.points)
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .state(let state):
            let layout = DiagramLayoutEngine.layout(state, measure: measure, spacing: spacing)
            size = layout.size
            edgePolylines = layout.edges.map(\.points)
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .gantt(let gantt):
            let layout = DiagramLayoutEngine.layout(gantt, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .timeline(let timeline):
            let layout = DiagramLayoutEngine.layout(timeline, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .mindmap(let mindmap):
            let layout = DiagramLayoutEngine.layout(mindmap, measure: measure)
            size = layout.size
            edgePolylines = layout.edges.map { [$0.from, $0.to] }
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .journey(let journey):
            let layout = DiagramLayoutEngine.layout(journey, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .quadrant(let quadrant):
            let layout = DiagramLayoutEngine.layout(quadrant, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .packet(let packet):
            let layout = DiagramLayoutEngine.layout(packet, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .xychart(let chart):
            let layout = DiagramLayoutEngine.layout(chart, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .kanban(let board):
            let layout = DiagramLayoutEngine.layout(board, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .radar(let radar):
            let layout = DiagramLayoutEngine.layout(radar, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .treemap(let treemap):
            let layout = DiagramLayoutEngine.layout(treemap, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .gitGraph(let graph):
            let layout = DiagramLayoutEngine.layout(graph, measure: measure)
            size = layout.size
            edgePolylines = layout.edges.map { [$0.from, $0.to] }
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .sankey(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .requirement(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .zenuml(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .c4(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .architecture(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure, spacing: spacing)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .block(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .treeView(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .venn(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .cynefin(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            edgePolylines = layout.transitions.map { [$0.from, $0.to] }
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .wardley(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .ishikawa(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .eventModeling(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        case .swimlane(let d):
            let layout = DiagramLayoutEngine.layout(d, measure: measure)
            size = layout.size
            edgePolylines = layout.edges.map(\.points)
            draw = { context in Self.draw(layout, theme: theme, in: context) }
        }
        return (size, edgePolylines, draw)
    }

    /// Canvas geometry shared by all backends: layout size unioned with
    /// marker-inflated edge routes, padded, with the translation that maps
    /// content into it. Nil when the diagram is empty or implausibly large.
    static func paddedCanvas(
        size: CGSize, edgePolylines: [[CGPoint]]
    ) -> (canvasSize: CGSize, originX: CGFloat, originY: CGFloat)? {
        guard size.width > 0, size.height > 0, size.width < 4000, size.height < 4000 else { return nil }
        let bounds = contentBounds(size: size, edges: edgePolylines)
        guard bounds.width < 4000, bounds.height < 4000 else { return nil }
        let pad: CGFloat = 6
        return (CGSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2),
                pad - bounds.minX, pad - bounds.minY)
    }

    /// Wraps a render plan in a caption band when the source carries a
    /// front-matter `title:` — the centred title above the diagram that
    /// mermaid.js draws, in the standard `drawDiagramTitle` ink (12.5pt
    /// semibold `theme.ink`, so it rides the DiagramTheme seam). Types whose
    /// dialect already draws its own title (pie, gantt, …) pass through
    /// untouched — the title must never double. Both output backends
    /// (raster and PDF) consume the wrapped plan, so captions reach every
    /// format at once.
    static func captionedPlan(
        _ plan: (size: CGSize, edgePolylines: [[CGPoint]], draw: (CGContext) -> Void),
        caption: String?, diagram: MermaidDiagram, theme: DiagramTheme
    ) -> (size: CGSize, edgePolylines: [[CGPoint]], draw: (CGContext) -> Void) {
        // `caption` is the front-matter `title:` the parser already extracted
        // (threaded in via `parseWithMetadata`), not a re-scan of the source.
        guard diagram.titleText == nil, let caption
        else { return plan }
        let band: CGFloat = 26
        let width = max(plan.size.width, measure(caption, size: 12.5, weight: .semibold).width + 16)
        let dx = (width - plan.size.width) / 2
        let size = CGSize(width: width, height: plan.size.height + band)
        // Shift the overflow-tracking polylines with the content, or the
        // padded canvas would clip the moved routes.
        let edgePolylines = plan.edgePolylines.map { line in
            line.map { CGPoint(x: $0.x + dx, y: $0.y + band) }
        }
        let draw: (CGContext) -> Void = { context in
            drawDiagramTitle(caption, width: width, theme: theme, in: context)
            context.saveGState()
            context.translateBy(x: dx, y: band)
            plan.draw(context)
            context.restoreGState()
        }
        return (size, edgePolylines, draw)
    }

    #if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
    /// Linux raster backend: renders `source` to a Cairo-backed `PlatformImage`
    /// (PNG-exportable), sharing the exact `renderPlan`/`captionedPlan`/
    /// `paddedCanvas` pipeline the Apple backends use — only the surface and
    /// output type differ.
    static func renderImage(source: String, theme: DiagramTheme,
                            spacing: DiagramSpacing = .regular) -> PlatformImage? {
        guard let (diagram, metadata) = MermaidParser.parseWithMetadata(source) else { return nil }
        return renderImage(diagram: diagram, title: metadata.title, theme: theme, spacing: spacing)
    }

    /// Linux raster backend for an already-parsed diagram (the DOT/terminal
    /// path) — same Cairo pipeline as the source-string entry, no Mermaid parse.
    static func renderImage(diagram: MermaidDiagram, title: String?,
                            theme: DiagramTheme, spacing: DiagramSpacing = .regular) -> PlatformImage? {
        let (size, edgePolylines, draw) = captionedPlan(
            renderPlan(for: diagram, theme: theme, spacing: spacing),
            caption: title, diagram: diagram, theme: theme)
        guard let (canvasSize, originX, originY) = paddedCanvas(size: size, edgePolylines: edgePolylines) else { return nil }
        // The bitmap surface is whole pixels (ceil), so canvasSize is fractional
        // slightly smaller than the surface. Fill the FULL pixel rect, not
        // canvasSize, or a <1px transparent strip is left along the right/bottom
        // edges of the ARGB32 output.
        let pixelW = canvasSize.width.rounded(.up), pixelH = canvasSize.height.rounded(.up)
        guard let surface = try? Cairo.Surface.Image(format: .argb32, width: Int(pixelW), height: Int(pixelH)),
              let context = try? CairoContext(surface: surface, size: canvasSize, flipped: true)
        else { return nil }
        // Paint the theme canvas, then the diagram (translated into the pad).
        context.setFillColor(resolvedCGColor(theme.canvas))
        context.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        context.saveGState()
        context.translateBy(x: originX, y: originY)
        draw(context)
        context.restoreGState()
        var image = PlatformImage(surface: surface, size: canvasSize)
        image.accessibilityDescription = MermaidAltText.describe(diagram)
        return image
    }
    #endif

    #if canImport(AppKit) || canImport(UIKit)
    /// Rasterizes an already-parsed diagram (no Mermaid parse, no cache) to a
    /// native image, sharing the exact `renderPlan`/`captionedPlan`/`paddedCanvas`
    /// pipeline used for a Mermaid source. The DOT/terminal render path.
    static func image(for diagram: MermaidDiagram, title: String?,
                      theme: DiagramTheme, spacing: DiagramSpacing = .regular) -> PlatformImage? {
        let (size, edgePolylines, draw) = captionedPlan(
            renderPlan(for: diagram, theme: theme, spacing: spacing),
            caption: title, diagram: diagram, theme: theme)
        guard let (canvasSize, originX, originY) = paddedCanvas(size: size, edgePolylines: edgePolylines) else { return nil }
        #if canImport(AppKit)
        let appearance = NSAppearance(named: theme.prefersDark ? .darkAqua : .aqua)
        let image = NSImage(size: canvasSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: originX, y: originY)
            let render = { draw(context) }
            if let appearance { appearance.performAsCurrentDrawingAppearance(render) } else { render() }
            return true
        }
        image.accessibilityDescription = MermaidAltText.describe(diagram)
        #else
        let traits = UITraitCollection(userInterfaceStyle: theme.prefersDark ? .dark : .light)
        var format = UIGraphicsImageRendererFormat.preferred()
        traits.performAsCurrent { format = .preferred() }
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { rendererContext in
            traits.performAsCurrent {
                rendererContext.cgContext.translateBy(x: originX, y: originY)
                draw(rendererContext.cgContext)
            }
        }
        #endif
        return image
    }

    static func attachmentString(source: String, theme: DiagramTheme,
                                 spacing: DiagramSpacing = .regular) -> NSAttributedString? {
        // Cache first: a hit must not pay a re-parse of up-to-50KB source
        // (MermaidView evaluates this on every SwiftUI body pass).
        let key = RenderKey(source: source, theme: theme.fingerprint, spacing: spacing.fingerprint)
        if let cached = cache.object(forKey: key) {
            return attributedString(for: cached)
        }
        guard let (diagram, metadata) = MermaidParser.parseWithMetadata(source) else { return nil }

        let entry: Entry
        do {
            let (size, edgePolylines, draw) = captionedPlan(
                renderPlan(for: diagram, theme: theme, spacing: spacing),
                caption: metadata.title, diagram: diagram, theme: theme)
            guard let (canvasSize, originX, originY) = paddedCanvas(size: size, edgePolylines: edgePolylines) else { return nil }

            #if canImport(AppKit)
            let appearance = NSAppearance(named: theme.prefersDark ? .darkAqua : .aqua)
            let image = NSImage(size: canvasSize, flipped: true) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.translateBy(x: originX, y: originY)
                let render = { draw(context) }
                if let appearance {
                    appearance.performAsCurrentDrawingAppearance(render)
                } else {
                    render()
                }
                return true
            }
            #else
            // Pin trait resolution to the theme's appearance: without this,
            // dynamic colors (tintColor, host semantic colors) rasterize under
            // whatever UITraitCollection.current happens to be — wrong under
            // an explicit opposite-appearance theme, and unspecified on the
            // async path's detached thread.
            let traits = UITraitCollection(userInterfaceStyle: theme.prefersDark ? .dark : .light)
            // `preferred()` snapshots UITraitCollection.current, so resolve it
            // under the pinned traits (the format type has no trait property).
            var format = UIGraphicsImageRendererFormat.preferred()
            traits.performAsCurrent { format = .preferred() }
            let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
            let image = renderer.image { rendererContext in
                traits.performAsCurrent {
                    rendererContext.cgContext.translateBy(x: originX, y: originY)
                    draw(rendererContext.cgContext)
                }
            }
            #endif
            entry = Entry(image: image, altText: MermaidAltText.describe(diagram))
            // Cost = actual backing bytes, not point-size bytes: UIKit
            // rasterizes at screen scale; AppKit's handler-backed NSImage caches
            // a rep per destination scale (2x assumed) on first draw.
            #if canImport(AppKit)
            let scale: CGFloat = 2
            #else
            let scale = image.scale
            #endif
            let pixels = Int(image.size.width * scale * image.size.height * scale)
            cache.setObject(entry, forKey: key, cost: pixels * 4)
        }
        return attributedString(for: entry)
    }

    /// Wraps a cached render as a fresh single-attachment string. On AppKit
    /// the image is COPIED: NSImage is mutable, and handing the cache's own
    /// instance out lets an innocent `image.size = fitted` poison every future
    /// cache hit. (UIImage is immutable; no copy needed.)
    private static func attributedString(for entry: Entry) -> NSAttributedString {
        #if canImport(AppKit)
        let image = (entry.image.copy() as? NSImage) ?? entry.image
        #else
        let image = entry.image
        #endif
        if let altText = entry.altText {
            #if canImport(AppKit)
            image.accessibilityDescription = altText
            #else
            // UIImage.accessibilityLabel is @MainActor in the iOS SDK (NSImage's
            // accessibilityDescription is not). Text-view embedding happens on
            // the main thread in practice, so set it when that's true and skip
            // otherwise — MermaidView's own accessibility label (set at the
            // SwiftUI layer, always main-actor) covers the view path regardless.
            if Thread.isMainThread {
                MainActor.assumeIsolated { image.accessibilityLabel = altText }
            }
            #endif
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: image.size)
        return NSAttributedString(attachment: attachment)
    }

    /// The attachment string for an already-parsed diagram (a non-Mermaid
    /// front-end), with an optional `title` caption — the format-aware attachment
    /// path. Uncached (no source string to key on); reuses `image(for:)` and the
    /// exact same accessible-attachment wrapping as the Mermaid `source` path, so
    /// DOT/Dippin/SQL/git-log embeds get identical sizing, theming, and narration.
    static func attachmentString(diagram: MermaidDiagram, title: String?, theme: DiagramTheme,
                                 spacing: DiagramSpacing = .regular) -> NSAttributedString? {
        guard let image = image(for: diagram, title: title, theme: theme, spacing: spacing) else { return nil }
        return attributedString(for: Entry(image: image, altText: MermaidAltText.describe(diagram)))
    }

    /// Cached format-aware attachment. Keyed on the source TAGGED by format (so a
    /// DOT and a Mermaid source with the same text can't collide) plus theme and
    /// spacing — the same cache the Mermaid `source:` path uses, so a live editor
    /// re-rendering a DOT/Dippin block on every SwiftUI body pass pays the
    /// parse+render once. `parse` is evaluated only on a cache miss.
    static func attachmentString(source: String, formatTag: String, theme: DiagramTheme,
                                 spacing: DiagramSpacing,
                                 parse: () -> MermaidDiagram?) -> NSAttributedString? {
        let key = RenderKey(source: "\(formatTag)\u{1}\(source)",
                            theme: theme.fingerprint, spacing: spacing.fingerprint)
        if let cached = cache.object(forKey: key) { return attributedString(for: cached) }
        guard let diagram = parse(),
              let image = image(for: diagram, title: nil, theme: theme, spacing: spacing) else { return nil }
        let entry = Entry(image: image, altText: MermaidAltText.describe(diagram))
        #if canImport(AppKit)
        let scale: CGFloat = 2
        #else
        let scale = image.scale
        #endif
        let pixels = Int(image.size.width * scale * image.size.height * scale)
        cache.setObject(entry, forKey: key, cost: pixels * 4)
        return attributedString(for: entry)
    }
    #endif

    // MARK: - Pie

    // MARK: - Gantt

    static let labelSize: CGFloat = 10.5

}
#endif
