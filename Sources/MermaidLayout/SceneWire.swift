import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The explicit, language-neutral wire form of a ``RenderScene`` — the JSON
/// contract the Android/Kotlin bridge and the plugin system read.
///
/// ``RenderScene`` itself is `Codable`, but its *synthesized* encoding leaks
/// Swift-compiler quirks that are hostile to a non-Swift consumer: enum cases
/// become single-key objects wrapping an `_0` field, and `CGPoint`/`CGRect`
/// serialize as bare positional arrays (`[x, y]`, `[[x, y], [w, h]]`). A Kotlin
/// or JS reader would need bespoke deserializers keyed on those quirks, and any
/// internal Swift rename would silently break the wire.
///
/// `SceneWire` is the stable contract instead: every element is a **flat object
/// tagged by a `type` discriminator** with named fields, points are
/// `{"x":…,"y":…}`, rects are `{"x":…,"y":…,"w":…,"h":…}`, and colors are
/// `#RRGGBBAA` strings. It reads like a REST payload, so a consumer writes one
/// `@Serializable data class` per shape and no custom serializers. `version`
/// carries the schema revision so the boundary can evolve compatibly.
///
/// It is a lossless projection of ``RenderScene`` (`init(_:)` in, `scene` out)
/// except color, which quantizes to 8 bits per channel — exactly the precision
/// every raster backend (Android `Paint`, CoreGraphics, SVG) draws at.
public struct SceneWire: Codable, Sendable, Equatable {

    /// The current wire schema revision. Bumped on any breaking shape change so
    /// a reader can gate on it (the versioned-bridge contract in android.md).
    public static let currentVersion = 1

    public var version: Int
    public var size: Size
    /// Background fill as `#RRGGBBAA`.
    public var background: String
    /// Elements in painter's order (first painted first).
    public var elements: [Element]

    // MARK: - Value types

    /// A point in the top-left-origin space (y increases downward).
    public struct Point: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// The scene canvas / a shape's bounding box.
    public struct Size: Codable, Sendable, Equatable {
        public var w: Double
        public var h: Double
        public init(w: Double, h: Double) { self.w = w; self.h = h }
    }

    /// An axis-aligned rectangle: top-left corner plus extent.
    public struct Rect: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double
        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }

    /// A stroked outline. `color` is `#RRGGBBAA`.
    public struct Stroke: Codable, Sendable, Equatable {
        public var color: String
        public var width: Double
        public var dashed: Bool
        public init(color: String, width: Double, dashed: Bool) {
            self.color = color; self.width = width; self.dashed = dashed
        }
    }

    // MARK: - Path geometry (discriminated on `type`)

    /// A shape outline: `roundedRect` | `ellipse` | `polygon` | `path`.
    public enum ShapePath: Codable, Sendable, Equatable {
        case roundedRect(rect: Rect, radius: Double)
        case ellipse(rect: Rect)
        case polygon(points: [Point])
        case path(verbs: [PathVerb])

        private enum CodingKeys: String, CodingKey {
            case type, rect, radius, points, verbs
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .roundedRect(rect, radius):
                try c.encode("roundedRect", forKey: .type)
                try c.encode(rect, forKey: .rect)
                try c.encode(radius, forKey: .radius)
            case let .ellipse(rect):
                try c.encode("ellipse", forKey: .type)
                try c.encode(rect, forKey: .rect)
            case let .polygon(points):
                try c.encode("polygon", forKey: .type)
                try c.encode(points, forKey: .points)
            case let .path(verbs):
                try c.encode("path", forKey: .type)
                try c.encode(verbs, forKey: .verbs)
            }
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "roundedRect":
                self = .roundedRect(rect: try c.decode(Rect.self, forKey: .rect),
                                    radius: try c.decode(Double.self, forKey: .radius))
            case "ellipse":
                self = .ellipse(rect: try c.decode(Rect.self, forKey: .rect))
            case "polygon":
                self = .polygon(points: try c.decode([Point].self, forKey: .points))
            case "path":
                self = .path(verbs: try c.decode([PathVerb].self, forKey: .verbs))
            case let other:
                throw wireError(CodingKeys.type, in: c, "unknown ShapePath type \"\(other)\"")
            }
        }
    }

    /// One command in an arbitrary outline: `move` | `line` | `quad` | `close`.
    public enum PathVerb: Codable, Sendable, Equatable {
        case move(point: Point)
        case line(point: Point)
        case quad(to: Point, control: Point)
        case close

        private enum CodingKeys: String, CodingKey {
            case type, point, to, control
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .move(point):
                try c.encode("move", forKey: .type)
                try c.encode(point, forKey: .point)
            case let .line(point):
                try c.encode("line", forKey: .type)
                try c.encode(point, forKey: .point)
            case let .quad(to, control):
                try c.encode("quad", forKey: .type)
                try c.encode(to, forKey: .to)
                try c.encode(control, forKey: .control)
            case .close:
                try c.encode("close", forKey: .type)
            }
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "move": self = .move(point: try c.decode(Point.self, forKey: .point))
            case "line": self = .line(point: try c.decode(Point.self, forKey: .point))
            case "quad": self = .quad(to: try c.decode(Point.self, forKey: .to),
                                      control: try c.decode(Point.self, forKey: .control))
            case "close": self = .close
            case let other:
                throw wireError(CodingKeys.type, in: c, "unknown PathVerb type \"\(other)\"")
            }
        }
    }

    // MARK: - Elements (discriminated on `type`)

    /// One display-list item: `shape` | `polyline` | `text`.
    public enum Element: Codable, Sendable, Equatable {
        case shape(path: ShapePath, fill: String?, stroke: Stroke?)
        case polyline(points: [Point], stroke: Stroke, startArrow: Bool, endArrow: Bool)
        case text(Text)

        private enum CodingKeys: String, CodingKey {
            case type, path, fill, stroke, points, startArrow, endArrow
            case string, center, fontSize, weight, color, backing, rotation
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .shape(path, fill, stroke):
                try c.encode("shape", forKey: .type)
                try c.encode(path, forKey: .path)
                try c.encodeIfPresent(fill, forKey: .fill)
                try c.encodeIfPresent(stroke, forKey: .stroke)
            case let .polyline(points, stroke, startArrow, endArrow):
                try c.encode("polyline", forKey: .type)
                try c.encode(points, forKey: .points)
                try c.encode(stroke, forKey: .stroke)
                try c.encode(startArrow, forKey: .startArrow)
                try c.encode(endArrow, forKey: .endArrow)
            case let .text(text):
                try c.encode("text", forKey: .type)
                try c.encode(text.string, forKey: .string)
                try c.encode(text.center, forKey: .center)
                try c.encode(text.fontSize, forKey: .fontSize)
                try c.encode(text.weight, forKey: .weight)
                try c.encode(text.color, forKey: .color)
                try c.encodeIfPresent(text.backing, forKey: .backing)
                try c.encode(text.rotation, forKey: .rotation)
            }
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "shape":
                self = .shape(path: try c.decode(ShapePath.self, forKey: .path),
                              fill: try c.decodeIfPresent(String.self, forKey: .fill),
                              stroke: try c.decodeIfPresent(Stroke.self, forKey: .stroke))
            case "polyline":
                self = .polyline(points: try c.decode([Point].self, forKey: .points),
                                 stroke: try c.decode(Stroke.self, forKey: .stroke),
                                 startArrow: try c.decode(Bool.self, forKey: .startArrow),
                                 endArrow: try c.decode(Bool.self, forKey: .endArrow))
            case "text":
                self = .text(Text(
                    string: try c.decode(String.self, forKey: .string),
                    center: try c.decode(Point.self, forKey: .center),
                    fontSize: try c.decode(Double.self, forKey: .fontSize),
                    weight: try c.decode(String.self, forKey: .weight),
                    color: try c.decode(String.self, forKey: .color),
                    backing: try c.decodeIfPresent(String.self, forKey: .backing),
                    rotation: try c.decode(Double.self, forKey: .rotation)))
            case let other:
                throw wireError(CodingKeys.type, in: c, "unknown Element type \"\(other)\"")
            }
        }
    }

    /// A text run. `weight` is `regular` | `medium` | `semibold`; colors are
    /// `#RRGGBBAA`; `rotation` is clockwise radians about `center`.
    public struct Text: Codable, Sendable, Equatable {
        public var string: String
        public var center: Point
        public var fontSize: Double
        public var weight: String
        public var color: String
        public var backing: String?
        public var rotation: Double
        public init(string: String, center: Point, fontSize: Double, weight: String,
                    color: String, backing: String?, rotation: Double) {
            self.string = string; self.center = center; self.fontSize = fontSize
            self.weight = weight; self.color = color; self.backing = backing
            self.rotation = rotation
        }
    }

    public init(version: Int, size: Size, background: String, elements: [Element]) {
        self.version = version
        self.size = size
        self.background = background
        self.elements = elements
    }
}

// MARK: - Projection from RenderScene

public extension SceneWire {
    /// Project a resolved ``RenderScene`` into its wire form.
    init(_ scene: RenderScene) {
        self.init(
            version: SceneWire.currentVersion,
            size: Size(w: SceneWire.q(scene.size.width), h: SceneWire.q(scene.size.height)),
            background: SceneWire.hex(scene.background),
            elements: scene.elements.map(SceneWire.element))
    }

    /// Quantize a coordinate to an exact 1/256 (2⁻⁸) grid before it enters the
    /// wire. This is the CROSS-PLATFORM byte-stability seam: raw `Double`s from
    /// layout arithmetic serialize differently across Foundation implementations
    /// (Darwin emits the shortest round-trip, e.g. `111.8`; swift-corelibs on
    /// Linux/Android/WASM emits full precision, `111.80000000000001`), so the
    /// same scene would not be byte-identical across platforms. An exact binary
    /// fraction has ONE shortest representation every encoder agrees on, so
    /// snapping to a 2⁻⁸ grid (~0.004 px — sub-pixel, imperceptible) makes the
    /// wire JSON identical on macOS, Linux, Android, WASM, and Windows. SVG is
    /// unaffected (it formats its own numbers via `SVGRenderer.num`).
    static func q(_ value: CGFloat) -> Double {
        (Double(value) * 256).rounded() / 256
    }

    private static func hex(_ c: DiagramColor) -> String { "#" + c.hexString }

    private static func point(_ p: CGPoint) -> Point {
        Point(x: q(p.x), y: q(p.y))
    }

    private static func rect(_ r: CGRect) -> Rect {
        Rect(x: q(r.origin.x), y: q(r.origin.y),
             w: q(r.size.width), h: q(r.size.height))
    }

    private static func stroke(_ s: RenderScene.Stroke) -> Stroke {
        Stroke(color: hex(s.color), width: q(s.width), dashed: s.dashed)
    }

    private static func shapePath(_ p: RenderScene.ShapePath) -> ShapePath {
        switch p {
        case let .roundedRect(r, radius): return .roundedRect(rect: rect(r), radius: q(radius))
        case let .ellipse(r):             return .ellipse(rect: rect(r))
        case let .polygon(pts):           return .polygon(points: pts.map(point))
        case let .path(verbs):            return .path(verbs: verbs.map(pathVerb))
        }
    }

    private static func pathVerb(_ v: RenderScene.PathVerb) -> PathVerb {
        switch v {
        case let .move(p):               return .move(point: point(p))
        case let .line(p):               return .line(point: point(p))
        case let .quad(to, control):     return .quad(to: point(to), control: point(control))
        case .close:                     return .close
        }
    }

    private static func element(_ e: RenderScene.Element) -> Element {
        switch e {
        case let .shape(s):
            return .shape(path: shapePath(s.path),
                          fill: s.fill.map(hex),
                          stroke: s.stroke.map(stroke))
        case let .polyline(p):
            return .polyline(points: p.points.map(point), stroke: stroke(p.stroke),
                             startArrow: p.startArrow, endArrow: p.endArrow)
        case let .text(t):
            return .text(Text(string: t.string, center: point(t.center),
                              fontSize: q(t.fontSize), weight: t.weight.rawValue,
                              color: hex(t.color), backing: t.backing.map(hex),
                              rotation: q(t.rotation)))
        }
    }
}

// MARK: - Reconstruction to RenderScene (round-trip / Swift-side consumers)

public extension SceneWire {
    /// Errors from reconstructing a ``RenderScene`` — a malformed color string
    /// or an unrecognized enum tag in the payload.
    enum DecodeError: Error, Equatable {
        case badColor(String)
        case badWeight(String)
    }

    /// Rebuild a ``RenderScene`` from this wire value (the inverse of
    /// `init(_:)`, modulo the 8-bit color quantization). Used by round-trip
    /// tests and any Swift consumer that reads wire JSON (e.g. a plugin).
    func scene() throws -> RenderScene {
        RenderScene(
            size: CGSize(width: size.w, height: size.h),
            background: try SceneWire.color(background),
            elements: try elements.map(SceneWire.renderElement))
    }

    private static func color(_ s: String) throws -> DiagramColor {
        guard let c = DiagramColor(hexString: s) else { throw DecodeError.badColor(s) }
        return c
    }

    private static func cgPoint(_ p: Point) -> CGPoint { CGPoint(x: p.x, y: p.y) }
    private static func cgRect(_ r: Rect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.w, height: r.h)
    }

    private static func renderStroke(_ s: Stroke) throws -> RenderScene.Stroke {
        RenderScene.Stroke(color: try color(s.color), width: CGFloat(s.width), dashed: s.dashed)
    }

    private static func renderPath(_ p: ShapePath) -> RenderScene.ShapePath {
        switch p {
        case let .roundedRect(r, radius): return .roundedRect(cgRect(r), radius: CGFloat(radius))
        case let .ellipse(r):             return .ellipse(cgRect(r))
        case let .polygon(pts):           return .polygon(pts.map(cgPoint))
        case let .path(verbs):            return .path(verbs.map(renderVerb))
        }
    }

    private static func renderVerb(_ v: PathVerb) -> RenderScene.PathVerb {
        switch v {
        case let .move(p):           return .move(cgPoint(p))
        case let .line(p):           return .line(cgPoint(p))
        case let .quad(to, control): return .quad(to: cgPoint(to), control: cgPoint(control))
        case .close:                 return .close
        }
    }

    private static func renderElement(_ e: Element) throws -> RenderScene.Element {
        switch e {
        case let .shape(path, fill, stroke):
            return .shape(RenderScene.Shape(
                path: renderPath(path),
                fill: try fill.map(color),
                stroke: try stroke.map(renderStroke)))
        case let .polyline(points, stroke, startArrow, endArrow):
            return .polyline(RenderScene.Polyline(
                points: points.map(cgPoint), stroke: try renderStroke(stroke),
                startArrow: startArrow, endArrow: endArrow))
        case let .text(t):
            guard let weight = RenderScene.FontWeight(rawValue: t.weight) else {
                throw DecodeError.badWeight(t.weight)
            }
            return .text(RenderScene.Text(
                string: t.string, center: cgPoint(t.center), fontSize: CGFloat(t.fontSize),
                weight: weight, color: try color(t.color),
                backing: try t.backing.map(color), rotation: CGFloat(t.rotation)))
        }
    }
}

// MARK: - Helpers

/// A uniform decode error for an unknown discriminator, tagged with the coding
/// path so a malformed payload points at the offending element.
private func wireError<K: CodingKey>(_ key: K, in container: KeyedDecodingContainer<K>,
                                     _ message: String) -> DecodingError {
    DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: message)
}
