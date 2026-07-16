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

    public init(scale: CGFloat = 1, nodeGap: CGFloat? = nil,
                layerGap: CGFloat? = nil, margin: CGFloat? = nil) {
        self.scale = max(scale, 0.4)   // below this, labels physically collide
        self.nodeGap = nodeGap
        self.layerGap = layerGap
        self.margin = margin
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
        return "s\(String(format: "%.2f", scale))|\(f(nodeGap))|\(f(layerGap))|\(f(margin))"
    }

    // Engines resolve their tuned base values through these.
    func resolvedNodeGap(base: CGFloat) -> CGFloat { nodeGap ?? base * scale }
    func resolvedLayerGap(base: CGFloat) -> CGFloat { layerGap ?? base * scale }
    func resolvedMargin(base: CGFloat) -> CGFloat { margin ?? base * scale }
}
