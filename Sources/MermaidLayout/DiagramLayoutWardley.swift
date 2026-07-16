import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Laid-out Wardley map: the plot frame with evolution bands, positioned
/// component dots, dependency links, evolve arrows, and collision-staggered
/// labels.
public struct WardleyLayout: Sendable {
    public struct Node: Sendable {
        public let name: String
        public let center: CGPoint
        public let isAnchor: Bool
        public let inertia: Bool
        public let decorator: String?
        /// Label frame, staggered clear of neighboring labels.
        public let labelFrame: CGRect
    }
    public struct Link: Sendable {
        public let from: CGPoint
        public let to: CGPoint
        public let isFlow: Bool
    }
    public struct Evolve: Sendable {
        public let from: CGPoint
        public let to: CGPoint
    }
    public struct Note: Sendable {
        public let text: String
        public let center: CGPoint
    }
    public let size: CGSize
    public let title: String?
    public let plotFrame: CGRect
    /// Evolution band boundaries (x positions inside the plot) and names.
    public let bands: [(x: CGFloat, name: String)]
    public let nodes: [Node]
    public let links: [Link]
    public let evolves: [Evolve]
    public let notes: [Note]
}

extension DiagramLayoutEngine {
    /// Lays out a Wardley map. No graph layout: coordinates are the author's
    /// (x = evolution, y = 1 − visibility). The engine's work is axis chrome,
    /// evolve targets, and label collision staggering.
    public static func layout(_ map: WardleyMap, measure: DiagramTextMeasurer) -> WardleyLayout {
        let margin: CGFloat = 14
        let axisGutter: CGFloat = 24
        let titleHeight: CGFloat = map.title == nil ? 0 : 26
        let plotW: CGFloat = 560
        let plotH: CGFloat = 400
        let plot = CGRect(x: margin + axisGutter, y: margin + titleHeight,
                          width: plotW, height: plotH)

        func point(visibility: Double, evolution: Double) -> CGPoint {
            CGPoint(x: plot.minX + CGFloat(evolution) * plot.width,
                    y: plot.minY + CGFloat(1 - visibility) * plot.height)
        }

        let bands: [(x: CGFloat, name: String)] = [
            (plot.minX, "Genesis"),
            (plot.minX + plot.width * 0.25, "Custom Built"),
            (plot.minX + plot.width * 0.50, "Product (+rental)"),
            (plot.minX + plot.width * 0.75, "Commodity (+utility)"),
        ]

        // Geometry first, labels second: every dot position, link segment,
        // and evolve arrow is known BEFORE any label is placed, so placement
        // can avoid lines instead of stamping text on top of them.
        var centerOf: [String: CGPoint] = [:]
        for component in map.components {
            centerOf[component.name] = point(visibility: component.visibility,
                                             evolution: component.evolution)
        }
        let links: [WardleyLayout.Link] = map.links.compactMap { link in
            guard let a = centerOf[link.from], let b = centerOf[link.to] else { return nil }
            return .init(from: a, to: b, isFlow: link.isFlow)
        }
        let evolves: [WardleyLayout.Evolve] = map.evolves.compactMap { evolve in
            guard let from = centerOf[evolve.name] else { return nil }
            return .init(from: from,
                         to: CGPoint(x: plot.minX + CGFloat(evolve.target) * plot.width,
                                     y: from.y))
        }
        var segments: [(CGPoint, CGPoint)] = links.map { ($0.from, $0.to) }
        segments.append(contentsOf: evolves.map { ($0.from, $0.to) })

        // Label placement: eight candidate anchors around each dot, scored by
        // how much line length runs through the candidate rect (the failure
        // mode this replaces: labels stamped onto links), collisions with
        // already-placed labels (hard reject), other dots, and canvas edges.
        // Ties break toward the classic upper-right.
        var placed: [CGRect] = []
        var nodes: [WardleyLayout.Node] = []
        let allCenters = Array(centerOf.values)
        for component in map.components {
            let center = centerOf[component.name]!
            let size = measure(component.name, labelFontSize)
            let w = size.width, h = size.height
            let candidates: [CGRect] = [
                CGRect(x: center.x + 7, y: center.y - h - 4, width: w, height: h),   // upper right
                CGRect(x: center.x + 7, y: center.y + 4, width: w, height: h),        // lower right
                CGRect(x: center.x - w / 2, y: center.y - h - 8, width: w, height: h), // above
                CGRect(x: center.x - w / 2, y: center.y + 8, width: w, height: h),     // below
                CGRect(x: center.x - w - 7, y: center.y - h - 4, width: w, height: h), // upper left
                CGRect(x: center.x - w - 7, y: center.y + 4, width: w, height: h),     // lower left
                CGRect(x: center.x + 9, y: center.y - h / 2, width: w, height: h),     // right
                CGRect(x: center.x - w - 9, y: center.y - h / 2, width: w, height: h), // left
            ]
            var best: (frame: CGRect, score: CGFloat)?
            for (index, raw) in candidates.enumerated() {
                var frame = raw
                frame.origin.x = min(max(frame.origin.x, 1), plot.maxX + margin - w)
                frame.origin.y = min(max(frame.origin.y, 1), plot.maxY + margin - h)
                if placed.contains(where: { $0.intersects(frame.insetBy(dx: -2, dy: -2)) }) {
                    continue   // hard reject: never overlap another label
                }
                var score: CGFloat = CGFloat(index) * 3   // prefer earlier candidates
                let inner = frame.insetBy(dx: 1, dy: 1)
                for segment in segments {
                    score += DiagramLayoutLinter.segmentInsideLength(segment.0, segment.1, inner) * 2
                }
                for other in allCenters where other != center {
                    let dot = CGRect(x: other.x - 5, y: other.y - 5, width: 10, height: 10)
                    if frame.intersects(dot) { score += 40 }
                }
                if frame != raw { score += 10 }   // clamped = squeezed, mild penalty
                if best == nil || score < best!.score { best = (frame, score) }
            }
            // Every candidate overlapped a placed label: fall back to the
            // classic spot, clamped — the chip backstop keeps it readable.
            let frame = best?.frame ?? {
                var f = candidates[0]
                f.origin.x = min(max(f.origin.x, 1), plot.maxX + margin - w)
                return f
            }()
            placed.append(frame)
            nodes.append(.init(name: component.name, center: center,
                               isAnchor: component.isAnchor, inertia: component.inertia,
                               decorator: component.decorator?.rawValue,
                               labelFrame: frame))
        }
        let notes: [WardleyLayout.Note] = map.notes.map { note in
            var center = point(visibility: note.visibility, evolution: note.evolution)
            // Clamp so the measured text stays on canvas (author coordinates
            // near 0/1 would otherwise push half the note off the edge).
            let half = measure(note.text, labelFontSize).width / 2
            center.x = min(max(center.x, half + 2), plot.maxX + margin - half - 2)
            return .init(text: note.text, center: center)
        }

        return WardleyLayout(
            size: CGSize(width: plot.maxX + margin, height: plot.maxY + margin + 20),
            title: map.title, plotFrame: plot, bands: bands,
            nodes: nodes, links: links, evolves: evolves, notes: notes)
    }
}
