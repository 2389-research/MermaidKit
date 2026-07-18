import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `MindmapLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: MindmapLayout, …)`
    /// (MermaidRender/DiagramRenderer+Mindmap.swift). It emits, in the same
    /// painter's order: per-branch tinted curved connectors behind everything,
    /// then each node — a filled accent pill for the root (depth 0) and a
    /// rounded, tinted, hairline-bordered card for deeper nodes — with its label
    /// centered (white and semibold on the root, ink and regular elsewhere).
    ///
    /// The CG connector is a single horizontal-tangent cubic Bézier;
    /// `ShapePath` carries no cubic verb, so the S-curve is approximated by a
    /// short chain of `.quad` segments (`cubicQuads`, tangent-intersection
    /// control points) — a faithful match at this scale. The branch stroke's
    /// round line cap has no primitive analogue and is dropped (butt cap); the
    /// difference is a sub-pixel nub at the endpoints. Any change to the drawn
    /// mindmap appearance must land in both.
    public static func from(_ layout: MindmapLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // 1. Curved branch connectors, behind the nodes, tinted per branch.
        for edge in layout.edges {
            let dx = max((edge.to.x - edge.from.x) * 0.5, 8)
            let c1 = CGPoint(x: edge.from.x + dx, y: edge.from.y)
            let c2 = CGPoint(x: edge.to.x - dx, y: edge.to.y)
            var verbs: [PathVerb] = [.move(edge.from)]
            verbs += cubicQuads(from: edge.from, c1: c1, c2: c2, to: edge.to)
            elements.append(.shape(Shape(
                path: .path(verbs), fill: nil,
                stroke: Stroke(color: theme.categoricalColor(edge.colorIndex).withAlpha(0.55),
                               width: 2))))
        }

        // 2. Nodes: an accent pill at the root, tinted rounded cards deeper.
        for node in layout.nodes {
            if node.depth == 0 {
                elements.append(.shape(Shape(
                    path: .roundedRect(node.frame, radius: 8),
                    fill: theme.accent, stroke: nil)))
                elements.append(.text(Text(
                    string: node.label,
                    center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                    fontSize: 10.5, weight: .semibold, color: mindmapRootWhite)))
            } else {
                let tint = theme.categoricalColor(node.colorIndex)
                elements.append(.shape(Shape(
                    path: .roundedRect(node.frame, radius: 7),
                    fill: tint.withAlpha(0.16), stroke: nil)))
                elements.append(.shape(Shape(
                    path: .roundedRect(node.frame.insetBy(dx: 0.5, dy: 0.5), radius: 7),
                    fill: nil, stroke: Stroke(color: tint.withAlpha(0.5), width: 1))))
                elements.append(.text(Text(
                    string: node.label,
                    center: CGPoint(x: node.frame.midX, y: node.frame.midY),
                    fontSize: 10.5, color: theme.ink)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    /// Opaque white — the root label color (`PlatformColor.white` in the CG draw).
    private static let mindmapRootWhite = DiagramColor(red: 1, green: 1, blue: 1)

    /// Approximates the cubic Bézier `from`→`to` (controls `c1`, `c2`) as a
    /// chain of `.quad` verbs — the caller has already emitted a `.move` to
    /// `from`. Each of four segments spans an equal `t`-interval; a segment's
    /// quad control point is the intersection of the cubic's start and end
    /// tangents (falling back to the chord midpoint when the tangents are
    /// parallel), the standard least-error quadratic for a short cubic span.
    static func cubicQuads(from p0: CGPoint, c1: CGPoint, c2: CGPoint,
                           to p3: CGPoint) -> [PathVerb] {
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                           y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = 3 * u * u, b = 6 * u * t, c = 3 * t * t
            return CGPoint(x: a * (c1.x - p0.x) + b * (c2.x - c1.x) + c * (p3.x - c2.x),
                           y: a * (c1.y - p0.y) + b * (c2.y - c1.y) + c * (p3.y - c2.y))
        }
        let steps = 4
        var verbs: [PathVerb] = []
        for i in 0..<steps {
            let t0 = CGFloat(i) / CGFloat(steps)
            let t1 = CGFloat(i + 1) / CGFloat(steps)
            let s0 = point(t0), s1 = point(t1)
            let d0 = tangent(t0), d1 = tangent(t1)
            // Intersect the two tangent lines: s0 + a·d0 = s1 - b·d1.
            let denom = d0.x * d1.y - d0.y * d1.x
            let ctrl: CGPoint
            if abs(denom) < 1e-6 {
                ctrl = CGPoint(x: (s0.x + s1.x) / 2, y: (s0.y + s1.y) / 2)
            } else {
                let a = ((s1.x - s0.x) * d1.y - (s1.y - s0.y) * d1.x) / denom
                ctrl = CGPoint(x: s0.x + a * d0.x, y: s0.y + a * d0.y)
            }
            verbs.append(.quad(to: s1, control: ctrl))
        }
        return verbs
    }
}
