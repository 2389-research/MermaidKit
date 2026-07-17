import Foundation
#if canImport(CoreGraphics)
// On Apple platforms the CGRect/CGPoint/CGSize conveniences (midX, init(x:y:…))
// live in CoreGraphics; on Linux swift-corelibs-foundation provides them. Both
// make the CG types `Codable`, so `RenderScene` can derive `Codable` unchanged.
import CoreGraphics
#endif

/// A fully-resolved, platform-free display list that determines the picture.
///
/// `RenderScene` is the shared foundation the SVG backend, the future plugin
/// contract, and the Android (Kotlin Canvas) renderer all consume: shape
/// geometry is resolved exactly ONCE here — when a `*Layout` is lowered — so a
/// backend never re-derives a diamond's vertices or a cylinder's arcs. It just
/// paints primitives in order.
///
/// Coordinates are points in a top-left-origin space (y increases downward),
/// matching every `*Layout` in this module. `elements` are in painter's order
/// (first painted first, so later elements sit on top). Colors are
/// ``DiagramColor`` (sRGB 0…1) — never a platform color — and the whole tree is
/// `Codable` so a scene can cross a process boundary (SVG export, a plugin, a
/// JSON bridge to Kotlin) byte-for-byte.
///
/// Phase 0a lowered the flowchart family; Phase 0b adds state, ER, class, and
/// sequence (one `RenderScene.from(_:theme:measure:)` per family, dispatched by
/// `RenderScene.from(_ diagram:theme:measure:spacing:)`).
public struct RenderScene: Sendable, Codable {

    /// Relative typographic weight, mapped by each backend to its font system.
    public enum FontWeight: String, Sendable, Codable {
        case regular
        case medium
        case semibold
    }

    /// A stroked outline: a color, a line width, and whether it dashes.
    public struct Stroke: Sendable, Codable {
        public var color: DiagramColor
        public var width: CGFloat
        public var dashed: Bool
        public init(color: DiagramColor, width: CGFloat = 1, dashed: Bool = false) {
            self.color = color
            self.width = width
            self.dashed = dashed
        }
    }

    /// One drawing command in an arbitrary (`.path`) outline.
    public enum PathVerb: Sendable, Codable {
        case move(CGPoint)
        case line(CGPoint)
        case quad(to: CGPoint, control: CGPoint)
        case close
    }

    /// The geometry of a filled/stroked shape. Rounded rects, ellipses, and
    /// polygons get first-class cases so a backend can emit its native
    /// primitive (`<rect rx>`, `<ellipse>`, `<polygon>`); anything else — a
    /// cylinder's capped silhouette, a subroutine's double border — is an
    /// explicit verb list in `.path`.
    public enum ShapePath: Sendable, Codable {
        case roundedRect(CGRect, radius: CGFloat)
        case ellipse(CGRect)
        case polygon([CGPoint])
        case path([PathVerb])
    }

    /// A shape: its outline, an optional fill, and an optional stroke. A nil
    /// fill paints no interior; a nil stroke draws no border.
    public struct Shape: Sendable, Codable {
        public var path: ShapePath
        public var fill: DiagramColor?
        public var stroke: Stroke?
        public init(path: ShapePath, fill: DiagramColor?, stroke: Stroke?) {
            self.path = path
            self.fill = fill
            self.stroke = stroke
        }
    }

    /// A connected multi-segment line — an edge route. Arrowheads at either or
    /// both ends are flags the backend realizes from the segment directions, so
    /// the geometry stays a single point list.
    public struct Polyline: Sendable, Codable {
        public var points: [CGPoint]
        public var stroke: Stroke
        public var startArrow: Bool
        public var endArrow: Bool
        public init(points: [CGPoint], stroke: Stroke,
                    startArrow: Bool = false, endArrow: Bool = false) {
            self.points = points
            self.stroke = stroke
            self.startArrow = startArrow
            self.endArrow = endArrow
        }
    }

    /// A text run centered on `center`. `backing`, when set, is an opaque chip
    /// color painted behind the text (edge labels sit on a canvas-colored chip
    /// so the routed line doesn't show through).
    public struct Text: Sendable, Codable {
        public var string: String
        public var center: CGPoint
        public var fontSize: CGFloat
        public var weight: FontWeight
        public var color: DiagramColor
        public var backing: DiagramColor?
        public init(string: String, center: CGPoint, fontSize: CGFloat,
                    weight: FontWeight = .regular, color: DiagramColor,
                    backing: DiagramColor? = nil) {
            self.string = string
            self.center = center
            self.fontSize = fontSize
            self.weight = weight
            self.color = color
            self.backing = backing
        }
    }

    /// One item in the display list.
    public enum Element: Sendable, Codable {
        case shape(Shape)
        case polyline(Polyline)
        case text(Text)
    }

    /// The canvas the whole scene fits in — equal to the source layout's `size`.
    public var size: CGSize
    /// The background fill painted before any element.
    public var background: DiagramColor
    /// Primitives in painter's order (first painted first).
    public var elements: [Element]

    public init(size: CGSize, background: DiagramColor, elements: [Element]) {
        self.size = size
        self.background = background
        self.elements = elements
    }
}

/// The platform-free color surface a `RenderScene` lowering reads — the subset
/// of a theme the flowchart family paints with. A renderer maps its resolved
/// theme (`DiagramTheme.resolved`) into one of these before lowering.
public struct RenderTheme: Sendable, Hashable {
    /// Primary text and stroke color (node borders, arrows, node labels).
    public var ink: DiagramColor
    /// Highlight color; node fills use it at low alpha.
    public var accent: DiagramColor
    /// The diagram background fill.
    public var canvas: DiagramColor
    /// Thin rules — sequence box-band borders and fragment-tab fills wear it.
    public var hairline: DiagramColor
    /// De-emphasized text — the color edge labels wear.
    public var secondaryText: DiagramColor
    /// Most-de-emphasized text — sequence fragment guards and note captions.
    public var tertiaryText: DiagramColor
    /// Categorical hues, cycled by index — sequence box bands and note fills
    /// pick from it (Phase 0b). Empty when a family doesn't need it.
    public var palette: [DiagramColor]

    public init(ink: DiagramColor, accent: DiagramColor, canvas: DiagramColor,
                hairline: DiagramColor, secondaryText: DiagramColor,
                tertiaryText: DiagramColor, palette: [DiagramColor] = []) {
        self.ink = ink
        self.accent = accent
        self.canvas = canvas
        self.hairline = hairline
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.palette = palette
    }

    /// The categorical color for `index`, wrapping the palette — the platform-
    /// free twin of `DiagramTheme.categoricalColor(_:)`. A single accent-tinted
    /// fallback keeps sequence notes/bands drawable when no palette is supplied.
    public func categoricalColor(_ index: Int) -> DiagramColor {
        let count = palette.count
        guard count > 0 else { return accent }
        return palette[((index % count) + count) % count]
    }
}
