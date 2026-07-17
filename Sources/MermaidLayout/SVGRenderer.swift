import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A platform-free SVG backend for ``RenderScene``. Emits a standalone
/// `<svg>…</svg>` document that any browser or vector tool can open — the
/// export path (#15) and the reference against which the Android Canvas
/// renderer is checked. Pure string building: no CoreGraphics, no fonts, so it
/// builds and runs identically on Apple and Linux.
public enum SVGRenderer {

    /// Renders `scene` to an SVG document string.
    public static func svg(_ scene: RenderScene) -> String {
        let w = scene.size.width, h = scene.size.height
        var out = ""
        out += #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(num(w))" height="\#(num(h))" "#
        out += #"viewBox="0 0 \#(num(w)) \#(num(h))">"# + "\n"
        // Background.
        out += #"<rect x="0" y="0" width="\#(num(w))" height="\#(num(h))" fill="\#(rgba(scene.background))"/>"# + "\n"

        for element in scene.elements {
            switch element {
            case .shape(let shape):
                out += svgShape(shape) + "\n"
            case .polyline(let line):
                out += svgPolyline(line)
            case .text(let text):
                out += svgText(text)
            }
        }

        out += "</svg>"
        return out
    }

    // MARK: Elements

    private static func svgShape(_ shape: RenderScene.Shape) -> String {
        let paint = paintAttributes(fill: shape.fill, stroke: shape.stroke)
        switch shape.path {
        case .roundedRect(let r, let radius):
            let rx = radius > 0 ? #" rx="\#(num(radius))" ry="\#(num(radius))""# : ""
            return #"<rect x="\#(num(r.minX))" y="\#(num(r.minY))" width="\#(num(r.width))" height="\#(num(r.height))"\#(rx)\#(paint)/>"#
        case .ellipse(let r):
            return #"<ellipse cx="\#(num(r.midX))" cy="\#(num(r.midY))" rx="\#(num(r.width / 2))" ry="\#(num(r.height / 2))"\#(paint)/>"#
        case .polygon(let points):
            return #"<polygon points="\#(pointList(points))"\#(paint)/>"#
        case .path(let verbs):
            return #"<path d="\#(pathData(verbs))"\#(paint)/>"#
        }
    }

    private static func svgPolyline(_ line: RenderScene.Polyline) -> String {
        var out = #"<polyline points="\#(pointList(line.points))" fill="none" stroke="\#(rgba(line.stroke.color))" stroke-width="\#(num(line.stroke.width))""#
        if line.stroke.dashed { out += #" stroke-dasharray="4 3""# }
        out += "/>\n"
        // Arrowheads realized from the segment directions (matches
        // DiagramRenderer.drawArrowhead: length 8.5, half-spread 0.40).
        let pts = line.points
        if line.endArrow, pts.count >= 2 {
            out += arrowhead(tip: pts[pts.count - 1], from: pts[pts.count - 2],
                             color: line.stroke.color) + "\n"
        }
        if line.startArrow, pts.count >= 2 {
            out += arrowhead(tip: pts[0], from: pts[1], color: line.stroke.color) + "\n"
        }
        return out
    }

    private static func arrowhead(tip: CGPoint, from origin: CGPoint, color: DiagramColor) -> String {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let length: CGFloat = 8.5
        let spread: CGFloat = 0.40
        let p2 = CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread))
        let p3 = CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread))
        return #"<polygon points="\#(pointList([tip, p2, p3]))" fill="\#(rgba(color))"/>"#
    }

    private static func svgText(_ text: RenderScene.Text) -> String {
        var out = ""
        // Opaque backing chip (edge labels). No font metrics here, so size it
        // with the same 0.6-em/char heuristic the platform-free measurer uses,
        // plus the renderer's 3pt pad — an approximation of drawEdgeLabel's chip.
        if let backing = text.backing {
            let estWidth = CGFloat(max(text.string.count, 1)) * text.fontSize * 0.6
            let estHeight = text.fontSize + 4
            let pad: CGFloat = 3
            let cw = estWidth + pad * 2, ch = estHeight + pad * 2
            out += #"<rect x="\#(num(text.center.x - cw / 2))" y="\#(num(text.center.y - ch / 2))" width="\#(num(cw))" height="\#(num(ch))" fill="\#(rgba(backing))"/>"# + "\n"
        }
        // A rotated run (swimlane lane titles) spins clockwise about its center;
        // radians → degrees so SVG's rotate(deg cx cy) matches the CG transform.
        var transform = ""
        if text.rotation != 0 {
            let deg = text.rotation * 180 / .pi
            transform = #" transform="rotate(\#(num(deg)) \#(num(text.center.x)) \#(num(text.center.y)))""#
        }
        out += #"<text x="\#(num(text.center.x))" y="\#(num(text.center.y))" font-size="\#(num(text.fontSize))" font-weight="\#(fontWeight(text.weight))" text-anchor="middle" dominant-baseline="central"\#(transform) fill="\#(rgba(text.color))">\#(escape(text.string))</text>"# + "\n"
        return out
    }

    // MARK: Attribute helpers

    private static func paintAttributes(fill: DiagramColor?, stroke: RenderScene.Stroke?) -> String {
        var attrs = fill.map { #" fill="\#(rgba($0))""# } ?? #" fill="none""#
        if let stroke {
            attrs += #" stroke="\#(rgba(stroke.color))" stroke-width="\#(num(stroke.width))""#
            if stroke.dashed { attrs += #" stroke-dasharray="4 3""# }
        }
        return attrs
    }

    private static func pointList(_ points: [CGPoint]) -> String {
        points.map { "\(num($0.x)),\(num($0.y))" }.joined(separator: " ")
    }

    private static func pathData(_ verbs: [RenderScene.PathVerb]) -> String {
        verbs.map { verb in
            switch verb {
            case .move(let p): return "M \(num(p.x)) \(num(p.y))"
            case .line(let p): return "L \(num(p.x)) \(num(p.y))"
            case .quad(let to, let control): return "Q \(num(control.x)) \(num(control.y)) \(num(to.x)) \(num(to.y))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }

    private static func fontWeight(_ weight: RenderScene.FontWeight) -> String {
        switch weight {
        case .regular: return "400"
        case .medium: return "500"
        case .semibold: return "600"
        }
    }

    /// `DiagramColor` → CSS `rgba(r, g, b, a)` — channels 0…255, alpha 0…1.
    static func rgba(_ c: DiagramColor) -> String {
        let r = Int((c.red * 255).rounded())
        let g = Int((c.green * 255).rounded())
        let b = Int((c.blue * 255).rounded())
        return "rgba(\(r), \(g), \(b), \(num(CGFloat(c.alpha))))"
    }

    /// A compact, locale-independent number: up to 3 decimals, trailing zeros
    /// trimmed (`String(format:)` always emits a period, unaffected by locale).
    /// `internal` so tests can reconstruct expected coordinate strings exactly.
    static func num(_ value: CGFloat) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() { return String(Int(rounded.rounded())) }
        var s = String(format: "%.3f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Escapes the five XML predefined entities so labels can't break the doc.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }
}
