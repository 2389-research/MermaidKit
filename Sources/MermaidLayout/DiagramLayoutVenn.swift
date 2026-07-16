import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Laid-out Venn diagram: positioned circles plus set and region label
/// anchor points.
public struct VennLayout: Sendable {
    public struct Circle: Sendable {
        public let id: String
        public let label: String?
        public let center: CGPoint
        public let radius: CGFloat
        public let colorIndex: Int
        /// Where the set's own label sits (pushed away from the overlaps).
        public let labelCenter: CGPoint
    }
    public struct RegionLabel: Sendable {
        public let text: String
        public let center: CGPoint
    }
    public let size: CGSize
    public let circles: [Circle]
    public let regionLabels: [RegionLabel]
}

extension DiagramLayoutEngine {
    /// Lays out a Venn diagram: one, two, or three sets in the classic
    /// arrangements (extra sets fall back to a row — degraded but honest).
    /// Circle area scales with the set's relative size; overlap labels sit at
    /// the region centroids (lens midpoint for pairs, triangle center for the
    /// full triple).
    public static func layout(_ venn: VennDiagram, measure: DiagramTextMeasurer) -> VennLayout {
        let margin: CGFloat = 22
        let baseRadius: CGFloat = 92

        // Radii: area ∝ size, normalized so the mean radius is baseRadius.
        let meanSize = venn.sets.map(\.size).reduce(0, +) / Double(venn.sets.count)
        func radius(_ s: VennDiagram.SetItem) -> CGFloat {
            baseRadius * CGFloat((s.size / meanSize).squareRoot().clamped(0.55, 1.6))
        }

        var centers: [CGPoint] = []
        let radii = venn.sets.map(radius)
        switch venn.sets.count {
        case 1:
            centers = [CGPoint(x: margin + radii[0], y: margin + radii[0])]
        case 2:
            // Overlap: centers separated by 65% of the radius sum.
            let d = 0.65 * (radii[0] + radii[1])
            let y = margin + max(radii[0], radii[1])
            centers = [CGPoint(x: margin + radii[0], y: y),
                       CGPoint(x: margin + radii[0] + d, y: y)]
        case 3:
            // Equilateral-ish triangle, pairwise separation 62% of radius sums.
            let d01 = 0.62 * (radii[0] + radii[1])
            let a = CGPoint(x: margin + radii[0], y: margin + radii[0])
            let b = CGPoint(x: a.x + d01, y: a.y)
            let d02 = 0.62 * (radii[0] + radii[2])
            let midX = (a.x + b.x) / 2
            let c = CGPoint(x: midX, y: a.y + d02 * 0.87)
            centers = [a, b, c]
        default:
            // Degraded fallback: a row of tangent circles.
            var x = margin
            for r in radii {
                centers.append(CGPoint(x: x + r, y: margin + (radii.max() ?? r)))
                x += r * 2 + 12
            }
        }

        // Set labels: pushed away from the repulsion vector of the OTHER
        // circle centers, so each label lands in its circle's private region.
        var circles: [VennLayout.Circle] = []
        for (index, set) in venn.sets.enumerated() {
            let mine = centers[index]
            var push = CGVector(dx: 0, dy: 0)
            for (j, other) in centers.enumerated() where j != index {
                push.dx += mine.x - other.x
                push.dy += mine.y - other.y
            }
            let magnitude = max(hypot(push.dx, push.dy), 0.001)
            let offset = centers.count == 1 ? 0 : radii[index] * 0.45
            let labelCenter = CGPoint(
                x: mine.x + push.dx / magnitude * offset,
                y: mine.y + push.dy / magnitude * offset)
            circles.append(.init(id: set.id, label: set.label ?? set.id,
                                 center: mine, radius: radii[index],
                                 colorIndex: index, labelCenter: labelCenter))
        }

        // Region labels: centroid of the member circles' centers.
        let regionLabels: [VennLayout.RegionLabel] = venn.overlaps.compactMap { overlap in
            let members = overlap.ids.compactMap { id in
                circles.first(where: { $0.id == id })?.center
            }
            guard members.count == overlap.ids.count, !members.isEmpty else { return nil }
            var cx = members.map(\.x).reduce(0, +) / CGFloat(members.count)
            var cy = members.map(\.y).reduce(0, +) / CGFloat(members.count)
            // A PARTIAL overlap's label pushes away from the non-member
            // circles, landing in the pair's private lens instead of on the
            // all-sets center region (where the full-overlap label lives).
            let outsiders = circles.filter { !overlap.ids.contains($0.id) }
            if !outsiders.isEmpty, members.count < circles.count {
                var push = CGVector(dx: 0, dy: 0)
                for other in outsiders {
                    push.dx += cx - other.center.x
                    push.dy += cy - other.center.y
                }
                let magnitude = max(hypot(push.dx, push.dy), 0.001)
                let step = (radii.min() ?? baseRadius) * 0.34
                cx += push.dx / magnitude * step
                cy += push.dy / magnitude * step
            }
            return .init(text: overlap.label, center: CGPoint(x: cx, y: cy))
        }

        let maxX = zip(centers, radii).map { $0.x + $1 }.max() ?? margin
        let maxY = zip(centers, radii).map { $0.y + $1 }.max() ?? margin
        return VennLayout(size: CGSize(width: maxX + margin, height: maxY + margin),
                          circles: circles, regionLabels: regionLabels)
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}
private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
