import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Laid-out Cynefin framework: four fixed quadrants, the central confusion
/// disk, per-domain item text positions, and transition arrows.
public struct CynefinLayout: Sendable {
    public struct Item: Sendable {
        public let text: String
        public let center: CGPoint
    }
    public struct Quadrant: Sendable {
        public let domain: String
        public let name: String
        public let heuristic: String
        public let frame: CGRect
        public let colorIndex: Int
        public let items: [Item]
    }
    public struct Transition: Sendable {
        public let from: CGPoint
        public let to: CGPoint
        public let label: String?
        public let labelCenter: CGPoint
    }
    public let size: CGSize
    public let title: String?
    public let quadrants: [Quadrant]
    /// The central "confusion" disk (nil when the source never mentions it).
    public let center: Quadrant?
    public let centerRadius: CGFloat
    public let transitions: [Transition]
}

extension DiagramLayoutEngine {
    /// Lays out a Cynefin diagram: a fixed 2×2 (complex top-left,
    /// complicated top-right, chaotic bottom-left, clear bottom-right) with
    /// the confusion disk in the middle. Item text stacks under each domain
    /// heading; transitions run between quadrant centers, pulled toward the
    /// shared border so arrows don't cross the middle disk.
    public static func layout(_ diagram: CynefinDiagram, measure: DiagramTextMeasurer) -> CynefinLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = diagram.title == nil ? 0 : 26
        let quadW: CGFloat = 250
        // Height grows with the densest quadrant's item count.
        let maxItems = diagram.items.values.map(\.count).max() ?? 0
        let quadH: CGFloat = max(150, 64 + CGFloat(maxItems) * 17)
        let gap: CGFloat = 4

        let originY = margin + titleHeight
        let placement: [(CynefinDiagram.Domain, Int, Int)] = [
            (.complex, 0, 0), (.complicated, 1, 0), (.chaotic, 0, 1), (.clear, 1, 1),
        ]
        var quadrants: [CynefinLayout.Quadrant] = []
        for (index, (domain, col, row)) in placement.enumerated() {
            let frame = CGRect(
                x: margin + CGFloat(col) * (quadW + gap),
                y: originY + CGFloat(row) * (quadH + gap),
                width: quadW, height: quadH)
            let items = (diagram.items[domain] ?? []).enumerated().map { i, text in
                CynefinLayout.Item(text: text, center: CGPoint(
                    x: frame.midX,
                    y: frame.minY + 52 + CGFloat(i) * 17))
            }
            quadrants.append(.init(
                domain: domain.rawValue, name: domain.rawValue.capitalized,
                heuristic: domain.heuristic, frame: frame,
                colorIndex: index, items: items))
        }

        let full = CGRect(x: margin, y: originY,
                          width: quadW * 2 + gap, height: quadH * 2 + gap)
        let centerRadius: CGFloat = 52
        var center: CynefinLayout.Quadrant?
        let confusionItems = diagram.items[.confusion] ?? []
        if diagram.items.keys.contains(.confusion) || !confusionItems.isEmpty {
            let frame = CGRect(x: full.midX - centerRadius, y: full.midY - centerRadius,
                               width: centerRadius * 2, height: centerRadius * 2)
            let items = confusionItems.prefix(2).enumerated().map { i, text in
                CynefinLayout.Item(text: text, center: CGPoint(
                    x: frame.midX, y: frame.midY + 18 + CGFloat(i) * 15))
            }
            center = .init(domain: "confusion", name: "Confusion",
                           heuristic: CynefinDiagram.Domain.confusion.heuristic,
                           frame: frame, colorIndex: 4, items: Array(items))
        }

        // Transitions: from/to points sit on the segment between the two
        // quadrant centers, inset so arrows live in the border zone.
        func quadrantCenter(_ domain: CynefinDiagram.Domain) -> CGPoint {
            if domain == .confusion { return CGPoint(x: full.midX, y: full.midY) }
            guard let q = quadrants.first(where: { $0.domain == domain.rawValue }) else {
                return CGPoint(x: full.midX, y: full.midY)
            }
            return CGPoint(x: q.frame.midX, y: q.frame.midY)
        }
        let diagramCenter = CGPoint(x: full.midX, y: full.midY)
        let transitions: [CynefinLayout.Transition] = diagram.transitions.map { t in
            let a = quadrantCenter(t.from), b = quadrantCenter(t.to)
            var from = CGPoint(x: a.x + (b.x - a.x) * 0.30, y: a.y + (b.y - a.y) * 0.30)
            var to = CGPoint(x: a.x + (b.x - a.x) * 0.70, y: a.y + (b.y - a.y) * 0.70)
            // Quadrant-to-quadrant arrows shift toward the OUTER edge so they
            // run in the corridor past the item stacks instead of through
            // them; confusion-involved arrows stay on the centerline (short,
            // and the disk's surroundings are clear).
            if t.from != .confusion, t.to != .confusion {
                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                var away = CGVector(dx: mid.x - diagramCenter.x, dy: mid.y - diagramCenter.y)
                let magnitude = max(hypot(away.dx, away.dy), 0.001)
                away.dx /= magnitude
                away.dy /= magnitude
                let shift: CGFloat = min(quadW, quadH) * 0.30
                from.x += away.dx * shift
                from.y += away.dy * shift
                to.x += away.dx * shift
                to.y += away.dy * shift
            }
            return .init(from: from, to: to, label: t.label,
                         labelCenter: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 10))
        }

        return CynefinLayout(
            size: CGSize(width: full.maxX + margin, height: full.maxY + margin),
            title: diagram.title,
            quadrants: quadrants, center: center, centerRadius: centerRadius,
            transitions: transitions)
    }
}
