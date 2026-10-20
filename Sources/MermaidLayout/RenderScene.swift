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
/// Every diagram type lowers: one `RenderScene.from(_:theme:measure:)` per
/// family, dispatched by `RenderScene.from(_ diagram:theme:measure:spacing:)`.
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
    /// the geometry stays a single point list. Other end marks (a flowchart's
    /// `--o` circle or `--x` cross) arrive as their own `.shape` elements, and the
    /// line stops where the mark begins.
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

    /// A text run centered on `center` — one visual line: a lowered scene
    /// never holds a line break in `string` (see `lines(of:measure:)`).
    /// `backing`, when set, is an opaque chip color painted behind the text
    /// (edge labels sit on a canvas-colored chip so the routed line doesn't
    /// show through). `rotation` is a clockwise angle
    /// in radians about `center` (0 for the common horizontal run) — swimlane
    /// lane titles read bottom-to-top at −π/2, matching `drawTextRotated`.
    public struct Text: Sendable, Codable {
        public var string: String
        public var center: CGPoint
        public var fontSize: CGFloat
        public var weight: FontWeight
        public var color: DiagramColor
        public var backing: DiagramColor?
        public var rotation: CGFloat
        public init(string: String, center: CGPoint, fontSize: CGFloat,
                    weight: FontWeight = .regular, color: DiagramColor,
                    backing: DiagramColor? = nil, rotation: CGFloat = 0) {
            self.string = string
            self.center = center
            self.fontSize = fontSize
            self.weight = weight
            self.color = color
            self.backing = backing
            self.rotation = rotation
        }

        // `rotation` was added after the wire format shipped, so decode it
        // if-present and default to 0 — scene JSON written before the field
        // existed (the Android JNI boundary, versioned plugin/golden contract)
        // must still decode. The synthesized encoding is unchanged: every
        // field, `rotation` included, is always written.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            string = try c.decode(String.self, forKey: .string)
            center = try c.decode(CGPoint.self, forKey: .center)
            fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
            weight = try c.decode(FontWeight.self, forKey: .weight)
            color = try c.decode(DiagramColor.self, forKey: .color)
            backing = try c.decodeIfPresent(DiagramColor.self, forKey: .backing)
            rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
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

    /// The scene a family lowering returns: `elements` with every text run
    /// broken into its visual lines (`lines(of:measure:)`). Every
    /// `from(_ layout:…)` builds its scene through this, so no family can ship
    /// a `<br/>` to SVG or the wire as literal text.
    init(size: CGSize, background: DiagramColor, elements: [Element],
         measure: DiagramTextMeasurer) {
        var out: [Element] = []
        out.reserveCapacity(elements.count)
        for element in elements {
            guard case .text(let text) = element else { out.append(element); continue }
            let lines = Self.lines(of: text, measure: measure)
            guard lines.count != 1, let backing = text.backing else { out += lines.map(Element.text); continue }
            // The raster draws ONE chip behind the whole block (the label's
            // measured size plus a 3pt pad), then the lines; a chip per line
            // would paint over the line above's descenders. A label that is
            // only breaks measures as one empty line there, and still masks
            // the edge under it.
            let sizes = lines.isEmpty ? [measure("", Double(text.fontSize))]
                : lines.map { measure($0.string, Double(text.fontSize)) }
            let width: CGFloat = sizes.map(\.width).max() ?? 0
            let height: CGFloat = sizes.map(\.height).reduce(0, +)
            let pad: CGFloat = 3
            let hw = width / 2 + pad, hh = height / 2 + pad
            let path: ShapePath
            if text.rotation == 0 {
                path = .roundedRect(CGRect(x: text.center.x - hw, y: text.center.y - hh,
                                           width: hw * 2, height: hh * 2), radius: 0)
            } else {
                let c: CGFloat = cos(text.rotation), s: CGFloat = sin(text.rotation)
                func corner(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: text.center.x + x * c - y * s, y: text.center.y + x * s + y * c)
                }
                path = .polygon([corner(-hw, -hh), corner(hw, -hh), corner(hw, hh), corner(-hw, hh)])
            }
            out.append(.shape(Shape(path: path, fill: backing, stroke: nil)))
            out += lines.map { line in var line = line; line.backing = nil; return .text(line) }
        }
        self.init(size: size, background: background, elements: out)
    }

    /// Breaks `text` into one run per visual line — the ONE line split every
    /// family's text goes through on its way into a scene.
    ///
    /// Invariant: the raster path is the reference, and this reproduces it.
    /// `DiagramRenderer.drawText` splits on `DiagramLayoutEngine.brLines`
    /// (any `<br…>`, a literal `\n`, any real newline), stacks the lines
    /// top-to-bottom at their measured heights, and centers the block on the
    /// run's center; so does this, in the run's rotated frame. Each line keeps
    /// the run's size, weight, color, backing and rotation (the measured init
    /// then trades a multi-line run's per-line backing for one block chip). A run with no
    /// break comes back untouched; one that is only breaks draws nothing.
    /// Lines stay separate runs, so the wire format (one string per text
    /// element) and every backend that paints it are unchanged.
    static func lines(of text: Text, measure: DiagramTextMeasurer) -> [Text] {
        // drawText's own test: what it leaves unsplit, so does this.
        guard DiagramLayoutEngine.hasLineBreak(text.string) else { return [text] }
        let lines = DiagramLayoutEngine.brLines(text.string)
        let heights = lines.map { measure($0, Double(text.fontSize)).height }
        var top = -heights.reduce(0, +) / 2
        return zip(lines, heights).map { line, height in
            // Offset along the run's own vertical axis, turned by its rotation.
            let dy = top + height / 2
            top += height
            var run = text
            run.string = line
            run.center = CGPoint(x: text.center.x - dy * sin(text.rotation),
                                 y: text.center.y + dy * cos(text.rotation))
            return run
        }
    }
}

/// The platform-free color surface every `RenderScene` lowering reads. A renderer maps its resolved
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
    /// Whether the theme targets a dark canvas. A handful of Phase 0b-2 fills
    /// (architecture/block tints, sankey bands) lift their alpha on dark so the
    /// tint reads — the platform-free twin of `DiagramTheme.prefersDark`.
    public var prefersDark: Bool

    public init(ink: DiagramColor, accent: DiagramColor, canvas: DiagramColor,
                hairline: DiagramColor, secondaryText: DiagramColor,
                tertiaryText: DiagramColor, palette: [DiagramColor] = [],
                prefersDark: Bool = false) {
        self.ink = ink
        self.accent = accent
        self.canvas = canvas
        self.hairline = hairline
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.palette = palette
        self.prefersDark = prefersDark
    }

    /// Phase 0a compatibility overload: keeps the original five-color
    /// initializer source-compatible for callers that predate `tertiaryText`
    /// and `palette`. Falls back to `secondaryText` for the tertiary tier and
    /// an empty palette.
    public init(ink: DiagramColor, accent: DiagramColor, canvas: DiagramColor,
                hairline: DiagramColor, secondaryText: DiagramColor) {
        self.init(ink: ink, accent: accent, canvas: canvas, hairline: hairline,
                  secondaryText: secondaryText, tertiaryText: secondaryText)
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
