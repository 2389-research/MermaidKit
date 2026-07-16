import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Canonical polyline arc-length helpers. Every layout engine, scene
// lowering, and renderer that needs "the point partway along a route" calls
// these — there is deliberately exactly ONE implementation (Euclidean arc
// length). Six near-copies once coexisted, two measuring Manhattan distance,
// which made label anchors disagree between the drawn route and the linted
// scene on any diagonal segment.
extension DiagramScene {

    /// The point at `fraction` (0…1) of the polyline's arc length.
    public static func polylinePoint(_ points: [CGPoint], fraction: CGFloat) -> CGPoint {
        guard let first = points.first else { return .zero }
        guard points.count > 1 else { return first }
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        guard total > 0 else { return first }
        var remaining = total * min(max(fraction, 0), 1)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if remaining <= seg || i == points.count - 1 {
                let t = seg == 0 ? 0 : remaining / seg
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            remaining -= seg
        }
        return points[points.count - 1]
    }

    /// The polyline's arc-length midpoint — where an edge label sits.
    public static func polylineMidpoint(_ points: [CGPoint]) -> CGPoint {
        polylinePoint(points, fraction: 0.5)
    }

    /// The estimated frame of a label known only by its text and center —
    /// the single width-per-character heuristic the scene lowerings use so
    /// the linter sees one consistent metric (6pt/char × 14pt line).
    public static func estimatedLabelFrame(_ text: String, center: CGPoint) -> CGRect {
        let size = estimatedLabelSize(text)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// See `estimatedLabelFrame`.
    public static func estimatedLabelSize(_ text: String) -> CGSize {
        CGSize(width: CGFloat(max(text.count, 1)) * 6, height: 14)
    }
}
