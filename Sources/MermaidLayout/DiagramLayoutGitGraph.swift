import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramLayoutEngine {

    /// Lays out a git graph left-to-right: commits advance along x in history
    /// order, each branch occupies a horizontal lane, and edges connect every
    /// commit to its parents (a curve when it crosses lanes — a branch point or
    /// a merge). Pure geometry — the renderer only draws.
    public static func layout(_ graph: GitGraph, measure: DiagramTextMeasurer) -> GitGraphLayout {
        let margin: CGFloat = 14
        let commitGap: CGFloat = 46
        let laneGap: CGFloat = 46
        let dotRadius: CGFloat = 7

        // Lane label gutter sized to the widest branch name.
        let labelWidth = graph.branches.map { measure($0, labelFontSize).width }.max() ?? 40
        let gutter = margin + min(max(labelWidth, 30), 120) + 10
        let topMargin = margin + 14   // room for a tag above the first lane

        func lane(_ branch: String) -> Int { graph.branches.firstIndex(of: branch) ?? 0 }
        func y(_ branch: String) -> CGFloat { topMargin + CGFloat(lane(branch)) * laneGap }

        // Column positions adapt to label widths: consecutive commits ON THE
        // SAME LANE must sit far enough apart that their id labels (drawn
        // centred under the dots) clear each other — a fixed column pitch
        // collides the moment ids are real words. Cross-lane neighbours don't
        // constrain each other (their labels live on different rows).
        let labels: [String?] = graph.commits.map { $0.hasExplicitID ? $0.id : nil }
        let widths: [CGFloat] = labels.map { $0.map { measure($0, labelFontSize).width } ?? 0 }
        var xs: [CGFloat] = []
        var lastOnLane: [Int: Int] = [:]
        for (order, commit) in graph.commits.enumerated() {
            var x = order == 0 ? gutter + commitGap / 2 : xs[order - 1] + commitGap
            if let prev = lastOnLane[lane(commit.branch)] {
                let needed = (widths[prev] + widths[order]) / 2 + 12
                x = max(x, xs[prev] + max(commitGap, needed))
            }
            xs.append(x)
            lastOnLane[lane(commit.branch)] = order
        }
        func x(_ order: Int) -> CGFloat { xs[order] }

        var commits: [GitGraphLayout.Commit] = []
        for (order, commit) in graph.commits.enumerated() {
            let center = CGPoint(x: x(order), y: y(commit.branch))
            commits.append(GitGraphLayout.Commit(
                center: center,
                colorIndex: lane(commit.branch),
                id: commit.id, label: labels[order],
                labelCenter: labels[order] == nil ? nil : CGPoint(x: center.x, y: center.y + 16),
                tag: commit.tag, isMerge: commit.isMerge))
        }

        // Edges from each commit to its parents, coloured by the child's lane.
        //
        // A same-lane edge is a straight horizontal run. A cross-lane edge (a
        // branch point or a merge) must NOT be drawn as a naive diagonal: that
        // line cuts straight through any commit dot sitting in an intermediate
        // lane at the midpoint column (e.g. the develop→feature/search branch
        // passing through feature/auth's dot). Instead we route it orthogonally
        // with a single right-angle corner, splitting the edge into two
        // collinear legs. Emitting them separately keeps the drawn path
        // identical to the geometry the linter checks: the renderer strokes a
        // same-y leg straight, and its cross-lane curve collapses to a straight
        // line when the two endpoints share an x.
        //
        // Two corner placements are possible; both keep the VERTICAL leg on a
        // commit's own (unique, otherwise-empty) column, so the only occlusion
        // risk is the HORIZONTAL leg running along an occupied lane:
        //   • source route — turn at the PARENT's column: vertical along the
        //     parent's column, then horizontal along the CHILD's lane. Preferred
        //     (a branch visibly leaves its source), and only its final leg lands
        //     on the child's column.
        //   • dest route — turn at the CHILD's column: horizontal along the
        //     PARENT's lane, then vertical up the child's column.
        // Prefer the source route; fall back to the dest route only when the
        // source route's horizontal leg (along the child's lane) would pass over
        // an intervening commit — e.g. a merge landing on a lane that has commits
        // between the two endpoints.
        func laneIsClear(betweenX ax: CGFloat, _ bx: CGFloat, onLaneY laneY: CGFloat) -> Bool {
            let lo = min(ax, bx), hi = max(ax, bx)
            for c in commits where abs(c.center.y - laneY) < 1 {
                if c.center.x > lo + 0.5 && c.center.x < hi - 0.5 { return false }
            }
            return true
        }

        var edges: [GitGraphLayout.Edge] = []
        for (order, commit) in graph.commits.enumerated() {
            let color = lane(commit.branch)
            for parent in commit.parents where parent < commits.count {
                let from = commits[parent].center
                let to = commits[order].center
                if abs(from.y - to.y) < 0.5 {
                    edges.append(GitGraphLayout.Edge(from: from, to: to, colorIndex: color))
                    continue
                }
                // Source route corners at (from.x, to.y); its horizontal leg
                // runs along the child's lane from from.x to to.x.
                let corner = laneIsClear(betweenX: from.x, to.x, onLaneY: to.y)
                    ? CGPoint(x: from.x, y: to.y)   // source route
                    : CGPoint(x: to.x, y: from.y)   // dest route
                edges.append(GitGraphLayout.Edge(from: from, to: corner, colorIndex: color))
                edges.append(GitGraphLayout.Edge(from: corner, to: to, colorIndex: color))
            }
        }

        // A branch/merge leg is a vertical edge segment at a commit's own x;
        // when one occupies the space directly BELOW a labeled dot, the label
        // would sit on the line. Flip such labels above the rail — but only
        // when the space above is genuinely free (no tag chip, no vertical leg
        // rising from an upper lane). If both sides are busy, below wins and
        // the label shifts right of the leg instead.
        commits = commits.enumerated().map { order, commit in
            guard let label = commit.label, let defaultCenter = commit.labelCenter else { return commit }
            func legOccupies(_ yLo: CGFloat, _ yHi: CGFloat) -> Bool {
                edges.contains { edge in
                    abs(edge.from.x - commit.center.x) < 0.5 && abs(edge.to.x - commit.center.x) < 0.5
                        && min(edge.from.y, edge.to.y) < yHi && max(edge.from.y, edge.to.y) > yLo
                }
            }
            let belowBusy = legOccupies(commit.center.y + dotRadius, commit.center.y + 24)
            guard belowBusy else { return commit }
            let aboveBusy = commit.tag != nil
                || legOccupies(commit.center.y - 24, commit.center.y - dotRadius)
            let flipped: CGPoint
            if aboveBusy {
                // Shift right of the descending leg, still under the rail.
                let w = measure(label, labelFontSize).width
                flipped = CGPoint(x: commit.center.x + w / 2 + 10, y: defaultCenter.y)
            } else {
                flipped = CGPoint(x: commit.center.x, y: commit.center.y - 16)
            }
            return GitGraphLayout.Commit(
                center: commit.center, colorIndex: commit.colorIndex,
                id: commit.id, label: label, labelCenter: flipped,
                tag: commit.tag, isMerge: commit.isMerge)
        }

        let laneLabels = graph.branches.enumerated().map { index, name in
            GitGraphLayout.LaneLabel(
                name: name,
                point: CGPoint(x: margin, y: topMargin + CGFloat(index) * laneGap),
                colorIndex: index)
        }

        // The canvas must cover the widest of: the last column plus its half
        // pitch, and every id label's right edge (labels centre under dots and
        // can be wider than the column pitch).
        var rightEdge = graph.commits.isEmpty ? gutter : x(graph.commits.count - 1) + commitGap / 2
        for (order, _) in graph.commits.enumerated() {
            rightEdge = max(rightEdge, x(order) + widths[order] / 2)
        }
        let width = rightEdge + margin
        let height = topMargin + CGFloat(max(graph.branches.count - 1, 0)) * laneGap + dotRadius + 22 + margin
        return GitGraphLayout(
            size: CGSize(width: width, height: height),
            commits: commits,
            edges: edges,
            laneLabels: laneLabels
        )
    }
}
