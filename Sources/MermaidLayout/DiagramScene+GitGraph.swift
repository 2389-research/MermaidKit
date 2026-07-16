import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a git graph to the common scene IR: each commit becomes a
    /// dot-sized node around its centre, parent→child connectors become
    /// two-point edges, and branch lane names plus commit tags become
    /// free-standing labels.
    static func from(_ layout: GitGraphLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        // The real dot radius used by DiagramLayoutEngine.layout(_ :GitGraph:).
        let dotRadius: CGFloat = 7

        // Every commit is a point; synthesise a dot-sized box around its centre.
        let nodes: [DiagramScene.Node] = layout.commits.map { commit in
            DiagramScene.Node(
                id: commit.id,
                frame: CGRect(
                    x: commit.center.x - dotRadius,
                    y: commit.center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2),
                isContainer: false)
        }

        // Parent→child connectors (branch points and merges included).
        let edges: [DiagramScene.Edge] = layout.edges.map { edge in
            DiagramScene.Edge(polyline: [edge.from, edge.to], label: nil)
        }

        // Free-standing labels: lane (branch-name) labels in the left gutter,
        // plus any commit tags, which float above their dot.
        var labels: [DiagramScene.Label] = layout.laneLabels.map { lane in
            let w = measuredLabelSize(measure, lane.name).width
            // The lane label point is left-anchored at the gutter margin.
            return DiagramScene.Label(
                text: lane.name,
                frame: CGRect(x: lane.point.x, y: lane.point.y - 7, width: w, height: 14))
        }
        // Commit id labels (explicit ones only — they're what the renderer
        // draws, centred 16pt below each dot). Lowering them is what lets the
        // linter SEE id-label collisions; they were invisible to it before,
        // which is how a fixed column pitch shipped colliding labels.
        for commit in layout.commits {
            guard let label = commit.label, !label.isEmpty,
                  let at = commit.labelCenter else { continue }
            let w = measuredLabelSize(measure, label).width
            labels.append(DiagramScene.Label(
                text: label,
                frame: CGRect(x: at.x - w / 2, y: at.y - 7, width: w, height: 14)))
        }
        for commit in layout.commits {
            guard let tag = commit.tag, !tag.isEmpty else { continue }
            let w = measuredLabelSize(measure, tag).width
            labels.append(DiagramScene.Label(
                text: tag,
                frame: CGRect(
                    x: commit.center.x - w / 2,
                    y: commit.center.y - dotRadius - 18,
                    width: w,
                    height: 14)))
        }

        return DiagramScene(
            name: "gitgraph",
            size: layout.size,
            nodes: nodes,
            edges: edges,
            labels: labels
        )
    }
}