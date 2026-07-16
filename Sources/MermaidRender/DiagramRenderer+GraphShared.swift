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

extension DiagramRenderer {

    /// Strokes an orthogonal polyline with lightly rounded corners so elbows
    /// read as intentional turns, not kinks. Assumes the caller has set the
    /// stroke colour / width / dash.
    static func strokePolyline(_ points: [CGPoint], in context: CGContext) {
        guard points.count >= 2 else { return }
        context.beginPath()
        appendRoundedPolyline(points, to: context)
        context.strokePath()
    }

    /// Strokes a set of edge shafts, batching by dash style so each group is a
    /// single composite stroke — crossing edges then don't stack their
    /// translucent strokes into darker seams. Each entry is (polyline, dashed).
    static func strokeEdgeShafts(
        _ shafts: [(points: [CGPoint], dashed: Bool)], color: PlatformColor, in context: CGContext
    ) {
        for dashed in [false, true] {
            let group = shafts.filter { $0.dashed == dashed }
            guard !group.isEmpty else { continue }
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(color))
            context.setLineWidth(1)
            if dashed { context.setLineDash(phase: 0, lengths: [4, 3]) }
            context.beginPath()
            for shaft in group { appendRoundedPolyline(shaft.points, to: context) }
            context.strokePath()
            context.restoreGState()
        }
    }

    /// Appends a rounded polyline as a new subpath *without* stroking, so many
    /// edges can be accumulated into one path and stroked in a single pass.
    /// A single stroke composites overlapping segments as one region, so
    /// crossing edges don't stack their alpha into darker seams.
    static func appendRoundedPolyline(_ points: [CGPoint], to context: CGContext) {
        guard points.count >= 2 else { return }
        context.move(to: points[0])
        if points.count > 2 {
            for index in 1..<(points.count - 1) {
                let prev = points[index - 1], corner = points[index], next = points[index + 1]
                let inLen = hypot(corner.x - prev.x, corner.y - prev.y)
                let outLen = hypot(next.x - corner.x, next.y - corner.y)
                // Clamp the corner radius so neither arc consumes more than half
                // of its adjacent segment. Two corners share a middle segment, so
                // capping each at half its length keeps their arcs from eating
                // past each other and pinching into a cusp on short jogs.
                let radius = min(5, inLen / 2, outLen / 2)
                context.addArc(tangent1End: corner, tangent2End: next, radius: radius)
            }
        }
        context.addLine(to: points.last!)
    }

    /// Point at `fraction` of arc length — forwards to the canonical
    /// implementation in MermaidLayout so drawn label anchors and linted
    /// scene labels can never disagree.
    static func polylinePoint(_ points: [CGPoint], fraction: CGFloat) -> CGPoint {
        DiagramScene.polylinePoint(points, fraction: fraction)
    }

    /// Arc-length midpoint — forwards to the canonical implementation.
    static func polylineMidpoint(_ points: [CGPoint]) -> CGPoint {
        DiagramScene.polylineMidpoint(points)
    }

    /// A filled arrowhead at `tip`. The head fills the canvas color first to
    /// erase the shaft beneath it, then the (often translucent) arrow color on
    /// top — otherwise the shaft's alpha adds to the head's and leaves a darker
    /// seam down the middle.
    static func drawArrowhead(
        at tip: CGPoint, from origin: CGPoint, color: PlatformColor, canvas: PlatformColor, in context: CGContext
    ) {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let length: CGFloat = 8.5
        let spread: CGFloat = 0.40
        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
        path.closeSubpath()

        context.saveGState()
        context.setFillColor(resolvedCGColor(canvas))
        context.addPath(path)
        context.fillPath()
        context.setFillColor(resolvedCGColor(color))
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    /// Thin bounding rects along a polyline's segments — used as soft obstacles
    /// so an edge label avoids sitting on *another* edge's line (which, for an
    /// antiparallel pair, pushes each label onto the correct outer side).
    static func edgeSegmentRects(_ points: [CGPoint], halfWidth: CGFloat = 4) -> [CGRect] {
        guard points.count >= 2 else { return [] }
        return (0..<(points.count - 1)).map { i in
            let a = points[i], b = points[i + 1]
            return CGRect(x: min(a.x, b.x) - halfWidth, y: min(a.y, b.y) - halfWidth,
                          width: abs(a.x - b.x) + halfWidth * 2, height: abs(a.y - b.y) + halfWidth * 2)
        }
    }

    /// Picks an anchor for an edge label that avoids the node boxes and any
    /// labels already placed — the draw-time counterpart of the flowchart
    /// layout's placement pass, for the box diagrams (class/ER/state) whose
    /// layouts don't compute a labelPoint. Prefers seating a label on a
    /// horizontal run that can contain it (or beside a vertical run), scored
    /// by overlap; records the choice in `placed` so sibling labels spread.
    static func labelAnchor(
        for points: [CGPoint], label: String, bounds: CGSize,
        obstacles: [CGRect], placed: inout [CGRect]
    ) -> CGPoint {
        let size = measure(label, size: labelSize)
        let w = size.width + 6, h = size.height + 2
        // Keep the whole label inside the canvas so a sideways nudge can't push
        // it off the edge and clip.
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, w / 2), max(w / 2, bounds.width - w / 2)) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, h / 2), max(h / 2, bounds.height - h / 2)) }
        func overlap(_ r1: CGRect, _ r2: CGRect) -> CGFloat {
            let ix = max(0, min(r1.maxX, r2.maxX) - max(r1.minX, r2.minX))
            let iy = max(0, min(r1.maxY, r2.maxY) - max(r1.minY, r2.minY))
            return ix * iy
        }
        // Reserve the marker/arrowhead zone near each endpoint so a label's
        // opaque pad can't cover a crow's-foot, tick, UML marker, or arrowhead:
        // ER crow's feet / zero-circles reach ~18pt off a border, so an 18pt
        // keep-out clears them without shoving the label further than needed
        // (the wider layer gap leaves a centered spot between the two markers).
        var obstacles = obstacles
        for end in [points.first, points.last].compactMap({ $0 }) {
            obstacles.append(CGRect(x: end.x - 18, y: end.y - 18, width: 36, height: 36))
        }
        // Build candidate anchors from the route's own geometry so a long label
        // lands where it actually reads, not on a bend with the L's legs poking
        // out on both sides:
        //   • horizontal runs — seat the label centred on the run (its opaque
        //     chip masks the line); penalise runs narrower than the label, since
        //     that's exactly when the corners show;
        //   • vertical runs — place the label BESIDE the line (either side);
        //   • the midpoint as a last resort.
        let mid = polylineMidpoint(points)
        var candidates: [(pt: CGPoint, bias: CGFloat)] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let c = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let distBias = hypot(c.x - mid.x, c.y - mid.y) * 0.08
            if abs(a.y - b.y) < 1 {                      // horizontal run
                let overflow = max(0, w - abs(b.x - a.x))
                candidates.append((c, overflow * 2.0 + distBias))
            } else if abs(a.x - b.x) < 1 {               // vertical run
                for side in [CGFloat(1), -1] {
                    candidates.append((CGPoint(x: a.x + side * (w / 2 + 6), y: c.y), 6 + distBias))
                }
            }
        }
        candidates.append((mid, 14))

        var best = CGPoint(x: clampX(mid.x), y: clampY(mid.y))
        var bestScore = CGFloat.greatestFiniteMagnitude
        for (pt, bias) in candidates {
            let cx = clampX(pt.x), cy = clampY(pt.y)
            let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            var score = bias
            for o in obstacles { score += overlap(rect, o.insetBy(dx: -3, dy: -3)) * 4 }
            for p in placed { score += overlap(rect, p.insetBy(dx: -4, dy: -4)) * 6 }
            if score < bestScore { bestScore = score; best = CGPoint(x: cx, y: cy) }
        }
        placed.append(CGRect(x: best.x - w / 2, y: best.y - h / 2, width: w, height: h))
        return best
    }

    /// Draws an edge label centered on `mid` over a canvas-colored pad so the
    /// routed line doesn't show through. Callers pick `mid` themselves — via
    /// `labelAnchor` or the layout's own label point.
    static func drawEdgeLabel(_ label: String, at mid: CGPoint, theme: DiagramTheme, in context: CGContext) {
        let size = measure(label, size: labelSize)
        let pad: CGFloat = 3
        context.setFillColor(resolvedCGColor(theme.canvas))
        context.fill(CGRect(
            x: mid.x - size.width / 2 - pad, y: mid.y - size.height / 2 - pad,
            width: size.width + pad * 2, height: size.height + pad * 2
        ))
        drawText(label, center: mid, size: labelSize, color: theme.secondaryTextColor, in: context)
    }

    /// Fills a node/box shape and strokes its border — the shared body for
    /// every diagram shape (rectangle, diamond, stadium, circle) so they stay
    /// visually consistent across flowchart, class, ER, and state diagrams.
    static func fillStrokeShape(
        _ path: CGPath, fill: PlatformColor, stroke: PlatformColor, in context: CGContext
    ) {
        context.saveGState()
        context.setFillColor(resolvedCGColor(fill))
        context.setStrokeColor(resolvedCGColor(stroke))
        context.setLineWidth(1)
        context.addPath(path)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    /// Convenience for the common rounded-rectangle body.
    static func fillStrokeBox(
        _ frame: CGRect, radius: CGFloat, fill: PlatformColor, stroke: PlatformColor, in context: CGContext
    ) {
        fillStrokeShape(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil),
                        fill: fill, stroke: stroke, in: context)
    }

    /// State-machine start terminal: a solid filled dot.
    static func drawStartTerminal(_ frame: CGRect, color: PlatformColor, in context: CGContext) {
        context.setFillColor(resolvedCGColor(color))
        context.fillEllipse(in: frame)
    }

    /// State-machine end terminal: a ring around a solid dot.
    static func drawEndTerminal(_ frame: CGRect, color: PlatformColor, in context: CGContext) {
        context.setStrokeColor(resolvedCGColor(color))
        context.strokeEllipse(in: frame.insetBy(dx: 1, dy: 1))
        context.setFillColor(resolvedCGColor(color))
        context.fillEllipse(in: frame.insetBy(dx: 4.5, dy: 4.5))
    }

    /// A database cylinder: rectangular body with an elliptical top cap and a
    /// bottom front arc. The silhouette (sides + top-back and bottom-front
    /// arcs) is filled and stroked, then the top's visible front rim is drawn.
    /// Returns the cap half-height so the caller can center the label below it.
    @discardableResult
    static func drawCylinder(
        _ f: CGRect, fill: PlatformColor, stroke: PlatformColor, in context: CGContext
    ) -> CGFloat {
        let capH = min(f.height * 0.14, 7)
        let bodyTop = f.minY + capH
        let bodyBottom = f.maxY - capH

        let silhouette = CGMutablePath()
        silhouette.move(to: CGPoint(x: f.minX, y: bodyTop))
        silhouette.addLine(to: CGPoint(x: f.minX, y: bodyBottom))
        silhouette.addQuadCurve(to: CGPoint(x: f.maxX, y: bodyBottom),
                                control: CGPoint(x: f.midX, y: bodyBottom + capH * 2)) // front arc
        silhouette.addLine(to: CGPoint(x: f.maxX, y: bodyTop))
        silhouette.addQuadCurve(to: CGPoint(x: f.minX, y: bodyTop),
                                control: CGPoint(x: f.midX, y: bodyTop - capH * 2))     // back arc
        silhouette.closeSubpath()

        context.saveGState()
        context.setFillColor(resolvedCGColor(fill))
        context.addPath(silhouette)
        context.fillPath()
        context.setStrokeColor(resolvedCGColor(stroke))
        context.setLineWidth(1)
        context.addPath(silhouette)
        context.strokePath()

        // The top cap's visible front rim (bulging down into the body).
        let rim = CGMutablePath()
        rim.move(to: CGPoint(x: f.minX, y: bodyTop))
        rim.addQuadCurve(to: CGPoint(x: f.maxX, y: bodyTop),
                         control: CGPoint(x: f.midX, y: bodyTop + capH * 2))
        context.addPath(rim)
        context.strokePath()
        context.restoreGState()
        return capH
    }

    /// Diamond (decision / choice) path inscribed in `f`.
    static func diamondPath(_ f: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: f.midX, y: f.minY))
        p.addLine(to: CGPoint(x: f.maxX, y: f.midY))
        p.addLine(to: CGPoint(x: f.midX, y: f.maxY))
        p.addLine(to: CGPoint(x: f.minX, y: f.midY))
        p.closeSubpath()
        return p
    }

    /// A self-bracketed horizontal hairline (compartment separators).
    static func strokeHLine(
        y: CGFloat, from x0: CGFloat, to x1: CGFloat, color: PlatformColor, in context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(resolvedCGColor(color))
        context.setLineWidth(1)
        context.beginPath()
        context.move(to: CGPoint(x: x0, y: y))
        context.addLine(to: CGPoint(x: x1, y: y))
        context.strokePath()
        context.restoreGState()
    }
}
#endif
