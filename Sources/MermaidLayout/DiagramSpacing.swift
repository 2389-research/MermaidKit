import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The density knob — one coherent spacing model instead of per-engine magic
/// numbers (ELK models spacing the same way: a small set of named gaps the
/// algorithms consult).
///
/// `scale` multiplies every engine's tuned base gaps; the optional fields
/// pin a specific gap to an absolute value when a host needs exact control.
///
/// ```swift
/// MermaidView(source, spacing: .compact)          // dense docs sidebar
/// DiagramSpacing(scale: 1.0, layerGap: 90)        // extra row breathing room
/// ```
///
/// Currently consulted by the layered family (flowchart, class, ER, state)
/// and architecture; the remaining chart types have fixed proportions and
/// ignore it (documented per engine).
public struct DiagramSpacing: Hashable, Sendable {
    /// Multiplier applied to every base gap (0.75 ≈ compact, 1.35 ≈ airy).
    public var scale: CGFloat
    /// Absolute gap between sibling nodes in a layer/row, overriding `scale`.
    public var nodeGap: CGFloat?
    /// Absolute gap between layers/rows, overriding `scale`.
    public var layerGap: CGFloat?
    /// Absolute canvas margin, overriding `scale`.
    public var margin: CGFloat?
    /// When set (points), snaps a flowchart's laid-out geometry onto a grid of
    /// this pitch (the internal `GridQuantizer`). Opt-in and off by default; 4 is
    /// the natural unit. Other diagram types ignore it today.
    public var gridSnap: CGFloat?
    /// Multiplier on every label's point size — Dynamic Type for diagrams.
    /// Unlike scaling the finished image, text is laid out at the larger size:
    /// boxes, rows, the gaps labels sit in and canvases grow to fit it, while
    /// lines and markers keep their weight. The default size (1) lays out
    /// exactly as before. `MermaidView` sets it from the environment's Dynamic
    /// Type size; other hosts pass their text size over the default (20/17
    /// for body text at 20pt). Clamped to 0.5…3, about the span of Dynamic
    /// Type's sizes; a non-finite value is the default size. Every entry point
    /// that takes a spacing honors it — the renderers, `RenderScene`,
    /// `DiagramLayoutEngine.layout(_:measure:spacing:)` and
    /// `DiagramScene.lower(_:measure:spacing:)` — so headless geometry and lint
    /// match the image.
    public var textScale: CGFloat {
        didSet { textScale = Self.clampedTextScale(textScale) }
    }

    static func clampedTextScale(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(max(value, 0.5), 3) : (value.isNaN ? 1 : (value > 0 ? 3 : 0.5))
    }

    public init(scale: CGFloat = 1, nodeGap: CGFloat? = nil,
                layerGap: CGFloat? = nil, margin: CGFloat? = nil,
                gridSnap: CGFloat? = nil, textScale: CGFloat = 1) {
        self.scale = max(scale, 0.4)   // below this, labels physically collide
        self.nodeGap = nodeGap
        self.layerGap = layerGap
        self.margin = margin
        self.gridSnap = gridSnap.map { max($0, 0) }
        self.textScale = Self.clampedTextScale(textScale)
    }

    /// The tuned defaults every fixture and benchmark runs at.
    public static let regular = DiagramSpacing()
    /// ~25% tighter — dense sidebars, thumbnails, small windows.
    public static let compact = DiagramSpacing(scale: 0.75)
    /// ~35% airier — presentations, large canvases.
    public static let comfortable = DiagramSpacing(scale: 1.35)

    /// A stable digest for render-cache keys.
    public var fingerprint: String {
        func f(_ v: CGFloat?) -> String { v.map { String(format: "%.1f", $0) } ?? "-" }
        return "s\(String(format: "%.2f", scale))|\(f(nodeGap))|\(f(layerGap))|\(f(margin))|g\(f(gridSnap))"
            + "|t\(Double(textScale))"   // full precision: close scales render differently
    }

    /// `measure`, asked for every size at `textScale` times it, so a layout
    /// sizes its boxes for the text as drawn.
    func scaling(_ measure: @escaping DiagramTextMeasurer) -> DiagramTextMeasurer {
        let k = Double(textScale)
        guard k != 1 else { return measure }
        return { text, size in measure(text, size * k) }
    }

    // Engines resolve their tuned base values through these.
    // (Text scale: see `DiagramTextScale`.)
    func resolvedNodeGap(base: CGFloat) -> CGFloat { nodeGap ?? base * scale }
    func resolvedLayerGap(base: CGFloat) -> CGFloat { layerGap ?? base * scale }
    func resolvedMargin(base: CGFloat) -> CGFloat { margin ?? base * scale }
}

/// The text scale of the layout in progress. Every entry point that takes a
/// ``DiagramSpacing`` runs its layout through ``run(_:_:_:)``, which applies
/// `spacing.textScale` to the measurer once and records it here, so the tuned
/// lengths layouts and renderers place text by (``DiagramLayoutEngine/grown(_:fontSize:_:)``)
/// grow by exactly the text's scale. Nested entry points (a renderer calling
/// the public layout engine) find it already applied and don't scale twice.
package enum DiagramTextScale {
    @TaskLocal package static var current: CGFloat = 1

    /// Runs `body` with `measure` scaled for `spacing.textScale` — unless the
    /// caller is already inside a layout at that scale, whose measurer is
    /// already scaled.
    ///
    /// Invariant: text is scaled exactly once. Outside any layout `current` is
    /// 1 and `measure` is plain, so `body` gets `measure` scaled by k and
    /// `current` = k. Inside a layout at k, `measure` is already scaled by k,
    /// so a nested entry point at the same k passes it through. A nested entry
    /// point at a *different* scale would leave `measure` scaled by the outer
    /// k while `current` claimed the inner one — only library code can be
    /// nested here, so that's a bug, and it traps in debug builds.
    package static func run<T>(_ spacing: DiagramSpacing, _ measure: DiagramTextMeasurer,
                               _ body: (DiagramTextMeasurer) -> T) -> T {
        let k = spacing.textScale
        assert(current == 1 || k == current,
               "a layout at text scale \(k) nested inside one at \(current): pass the caller's spacing")
        return withoutActuallyEscaping(measure) { measure in
            k == current ? body(measure) : $current.withValue(k) { body(spacing.scaling(measure)) }
        }
    }
}

