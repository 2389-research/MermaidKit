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

/// The full color surface a Mermaid diagram render needs — the sole external
/// seam. Host apps build one (or use the light/dark presets).
public struct DiagramTheme: Sendable {
    /// Primary text and stroke color (node borders, arrows, main labels).
    public let ink: PlatformColor
    /// De-emphasized text: member rows, message text, legend entries.
    public let secondaryTextColor: PlatformColor
    /// Most-muted text: tick captions, section headers, bit indices.
    public let tertiaryTextColor: PlatformColor
    /// The diagram background fill.
    public let canvas: PlatformColor
    /// Highlight color: node fills (at low alpha), markers, single-hue accents.
    public let accent: PlatformColor
    /// Thin rules: gridlines, lifelines, box dividers.
    public let hairline: PlatformColor
    /// Whether the theme targets a dark canvas (drives tint/contrast choices).
    public let prefersDark: Bool
    /// Categorical accents — the colors data series actually wear: node
    /// tints, pie slices, sankey bands, gantt sections, git branches.
    /// Cycled by index via `categoricalColor(_:)`. Override to re-skin every
    /// diagram type at once.
    public let palette: [PlatformColor]

    /// The default categorical palette: six hues tuned to stay distinct on
    /// both light and dark canvases.
    public static let defaultPalette: [PlatformColor] = [
        rgbStatic(0x5B8FF9), // blue
        rgbStatic(0x5AD8A6), // green
        rgbStatic(0xF6BD16), // gold
        rgbStatic(0xE8684A), // coral
        rgbStatic(0x6DC8EC), // sky
        rgbStatic(0x9270CA), // purple
    ]

    /// A stable digest of every color in the theme — the render-cache key
    /// component, so two themes with the same appearance but different colors
    /// can never serve each other's cached renders. Computed ONCE at init,
    /// with dynamic colors resolved under the SAME appearance the renderer
    /// pins while drawing — resolving under the ambient appearance instead
    /// would make the key drift between call contexts (main thread vs
    /// detached task, light vs dark ambient) and collide across appearances.
    public let fingerprint: String

    /// The theme's colors as platform-free sRGB values, resolved once at init
    /// under the same pinned appearance as `fingerprint` (so dynamic platform
    /// colors land on their `prefersDark` variants). This is the surface a
    /// platform-free backend (SVG emission, draw-list goldens) consumes; the
    /// rare platform color that refuses sRGB conversion (pattern/catalog)
    /// resolves to opaque black — it can't be represented as components.
    public struct Resolved: Hashable, Sendable {
        public let ink: DiagramColor
        public let secondaryText: DiagramColor
        public let tertiaryText: DiagramColor
        public let canvas: DiagramColor
        public let accent: DiagramColor
        public let hairline: DiagramColor
        public let palette: [DiagramColor]
    }
    /// See ``Resolved``.
    public let resolved: Resolved

    /// One pinned-appearance pass converts every color; the fingerprint and
    /// `resolved` are both derived from it so they can never disagree.
    private static func resolveAll(
        prefersDark: Bool, colors: [PlatformColor]
    ) -> (resolved: [DiagramColor], fingerprint: String) {
        func convert(_ c: PlatformColor) -> (DiagramColor, digest: String) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if canImport(AppKit)
            guard let converted = c.usingColorSpace(.sRGB) else {
                // Pattern/catalog colors that refuse sRGB conversion: digest
                // by description rather than as zeros (which would collide
                // every unconvertible color).
                return (DiagramColor(red: 0, green: 0, blue: 0), "(\(c.description))")
            }
            converted.getRed(&r, green: &g, blue: &b, alpha: &a)
            #else
            guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else {
                return (DiagramColor(red: 0, green: 0, blue: 0), "(\(c.description))")
            }
            #endif
            let color = DiagramColor(red: r, green: g, blue: b, alpha: a)
            return (color, color.hexString)
        }
        var pairs: [(DiagramColor, digest: String)] = []
        #if canImport(AppKit)
        let appearance = NSAppearance(named: prefersDark ? .darkAqua : .aqua)
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                pairs = colors.map(convert)
            }
        } else {
            pairs = colors.map(convert)
        }
        #elseif canImport(UIKit)
        let traits = UITraitCollection(userInterfaceStyle: prefersDark ? .dark : .light)
        pairs = colors.map { convert($0.resolvedColor(with: traits)) }
        #else
        // Linux: no appearance system; colors are already fixed sRGB values.
        pairs = colors.map(convert)
        #endif
        return (pairs.map(\.0), (prefersDark ? "d" : "l") + pairs.map(\.digest).joined())
    }

    /// The palette color for a categorical index (wraps around).
    public func categoricalColor(_ index: Int) -> PlatformColor {
        let count = palette.count
        guard count > 0 else { return accent }
        return palette[((index % count) + count) % count]
    }

    /// Memberwise init for a fully custom theme; parameters mirror the stored
    /// properties. `palette` defaults to `defaultPalette`.
    public init(ink: PlatformColor, secondaryTextColor: PlatformColor,
                tertiaryTextColor: PlatformColor, canvas: PlatformColor,
                accent: PlatformColor, hairline: PlatformColor, prefersDark: Bool,
                palette: [PlatformColor] = DiagramTheme.defaultPalette) {
        self.ink = ink; self.secondaryTextColor = secondaryTextColor
        self.tertiaryTextColor = tertiaryTextColor; self.canvas = canvas
        self.accent = accent; self.hairline = hairline; self.prefersDark = prefersDark
        self.palette = palette
        let all = Self.resolveAll(
            prefersDark: prefersDark,
            colors: [ink, secondaryTextColor, tertiaryTextColor, canvas, accent, hairline] + palette)
        self.fingerprint = all.fingerprint
        let r = all.resolved
        self.resolved = Resolved(
            ink: r[0], secondaryText: r[1], tertiaryText: r[2],
            canvas: r[3], accent: r[4], hairline: r[5],
            palette: Array(r.dropFirst(6)))
    }

    /// The built-in preset: a near-black (light) or near-white (dark) ink
    /// ramp at 100/55/38% alpha, white or near-black canvas, the system
    /// accent color, 12% hairlines, and the default palette.
    public init(prefersDark: Bool) {
        let fg: UInt32 = prefersDark ? 0xF2F2F4 : 0x1D1D1F
        #if canImport(AppKit)
        let sys = PlatformColor.controlAccentColor
        #else
        let sys = PlatformColor.tintColor
        #endif
        self.init(
            ink: rgbStatic(fg),
            secondaryTextColor: rgbStatic(fg, alpha: 0.55),
            tertiaryTextColor: rgbStatic(fg, alpha: 0.38),
            canvas: rgbStatic(prefersDark ? 0x1B1B1D : 0xFFFFFF),
            accent: sys,
            hairline: rgbStatic(prefersDark ? 0xFFFFFF : 0x000000, alpha: 0.12),
            prefersDark: prefersDark)
    }
}
#endif
