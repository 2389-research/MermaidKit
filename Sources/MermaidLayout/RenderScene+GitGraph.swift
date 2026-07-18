import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `GitGraphLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: GitGraphLayout, …)`
    /// (MermaidRender/DiagramRenderer+GitGraph.swift). It emits, in the same
    /// painter's order: per-lane tinted connectors behind the dots (a straight
    /// segment within a lane, a horizontal-tangent curve when crossing lanes at a
    /// branch or merge), left-anchored lane labels, then each commit — a filled
    /// dot (a canvas-cored ring for a merge), an optional id below, and an
    /// optional accent-chipped tag above.
    ///
    /// A cross-lane connector is a cubic Bézier in the CG draw; `ShapePath`
    /// carries no cubic verb, so it is approximated by a short `.quad` chain
    /// (`cubicQuads`) — as in the mindmap lowering. The connector's round line
    /// cap has no primitive analogue and is dropped (butt cap); the difference is
    /// a sub-pixel nub. Any change to the drawn git graph appearance must land in
    /// both.
    public static func from(_ layout: GitGraphLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        var elements: [Element] = []

        // 1. Connectors behind the dots.
        for edge in layout.edges {
            let color = theme.categoricalColor(edge.colorIndex).withAlpha(0.8)
            if abs(edge.from.y - edge.to.y) < 0.5 {
                elements.append(.polyline(Polyline(
                    points: [edge.from, edge.to],
                    stroke: Stroke(color: color, width: 2.5))))
            } else {
                let dx = (edge.to.x - edge.from.x) * 0.5
                let c1 = CGPoint(x: edge.from.x + dx, y: edge.from.y)
                let c2 = CGPoint(x: edge.to.x - dx, y: edge.to.y)
                var verbs: [PathVerb] = [.move(edge.from)]
                verbs += cubicQuads(from: edge.from, c1: c1, c2: c2, to: edge.to)
                elements.append(.shape(Shape(
                    path: .path(verbs), fill: nil, stroke: Stroke(color: color, width: 2.5))))
            }
        }

        // 2. Lane labels.
        for label in layout.laneLabels {
            elements.append(.text(leftText(
                label.name, at: label.point, fontSize: 10.5, weight: .semibold,
                color: theme.categoricalColor(label.colorIndex), measure: measure)))
        }

        // 3. Commit nodes.
        for commit in layout.commits {
            let color = theme.categoricalColor(commit.colorIndex)
            let r: CGFloat = commit.isMerge ? 5.5 : 6.5
            elements.append(.shape(Shape(
                path: .ellipse(CGRect(x: commit.center.x - r, y: commit.center.y - r,
                                      width: r * 2, height: r * 2)),
                fill: color, stroke: nil)))
            if commit.isMerge {
                elements.append(.shape(Shape(
                    path: .ellipse(CGRect(x: commit.center.x - 2.5, y: commit.center.y - 2.5,
                                          width: 5, height: 5)),
                    fill: theme.canvas, stroke: nil)))
            }

            if let label = commit.label, let at = commit.labelCenter {
                elements.append(.text(Text(
                    string: label, center: at, fontSize: 8.5, color: theme.secondaryText)))
            }
            if let tag = commit.tag {
                let width = measure(tag, 8.5).width
                let chip = CGRect(x: commit.center.x - width / 2 - 4,
                                  y: commit.center.y - 15 - 6, width: width + 8, height: 13)
                elements.append(.shape(Shape(
                    path: .roundedRect(chip, radius: 3),
                    fill: theme.accent.withAlpha(0.16), stroke: nil)))
                elements.append(.text(Text(
                    string: tag, center: CGPoint(x: chip.midX, y: chip.midY),
                    fontSize: 8.5, weight: .medium, color: theme.ink)))
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }
}
