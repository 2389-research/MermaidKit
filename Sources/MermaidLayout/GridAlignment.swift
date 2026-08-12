import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Grid-alignment metric (issue: editorial-quality diagrams keep coordinates on a
// small pixel grid so nothing reads as accidental). This MEASURES how aligned a
// laid-out box-family diagram already is — it does not move anything. It is the
// "lint-first" half of the grid work: a baseline CI can ratchet against before a
// `GridQuantizer` post-layout pass snaps geometry onto the grid.
//
// Deliberately NOT emitted as a `LayoutViolation`: today every box-family diagram
// sits well below full alignment, so a per-diagram warning would fire on all of
// them and drown the correctness stream. It lives as a separate measurement the
// ratchet test tracks, and surfaces in `report()` for human eyes.

extension DiagramLayoutLinter {

    /// Diagram families whose orthogonal box layouts a pixel grid actually helps.
    /// Radial/temporal types (pie, radar, timeline, sequence) gain nothing from a
    /// grid, so the metric is undefined (nil) for them.
    public static let gridFamilies: Set<String> = [
        "flowchart", "block", "c4", "architecture", "er", "class", "state",
    ]

    /// The natural grid unit for MermaidKit's box layouts. Empirically, node
    /// coordinates cluster near 4px multiples (8px alignment is too sparse to be
    /// the natural unit); see docs/notes and the layout-R&D artifact.
    public static let gridUnit: CGFloat = 4

    /// How aligned a laid-out diagram's node boxes are to a pixel grid.
    public struct GridAlignment: Sendable, Equatable {
        /// The grid unit the fractions are measured against (points).
        public let unit: CGFloat
        /// Node boxes considered (all `scene.nodes`, containers included).
        public let nodes: Int
        /// Boxes whose every coordinate (x, y, w, h) lands on the grid.
        public let nodesOnGrid: Int
        /// Individual coordinates on the grid, out of `coordsTotal` (= nodes × 4).
        public let coordsOnGrid: Int
        public let coordsTotal: Int

        /// Fraction of boxes fully on the grid (all four coordinates). Strict;
        /// starts near 0 for un-snapped layouts.
        public var nodeFraction: Double { nodes == 0 ? 1 : Double(nodesOnGrid) / Double(nodes) }
        /// Fraction of individual coordinates on the grid. The smoother metric the
        /// ratchet tracks — small layout improvements register here.
        public var coordFraction: Double { coordsTotal == 0 ? 1 : Double(coordsOnGrid) / Double(coordsTotal) }

        /// One-line human summary, e.g. `42% of node coords on the 4px grid (5/12 boxes)`.
        public var summary: String {
            let pct = Int((coordFraction * 100).rounded())
            return "\(pct)% of node coords on the \(Int(unit))px grid (\(nodesOnGrid)/\(nodes) boxes fully aligned)"
        }
    }

    /// Measures node-box grid alignment for a box-family scene, or `nil` if the
    /// diagram family isn't one a grid applies to (see `gridFamilies`) or has no
    /// boxes. A coordinate counts as on-grid when it is within half a point of a
    /// grid multiple (sub-pixel).
    public static func gridAlignment(_ scene: DiagramScene, unit: CGFloat = gridUnit) -> GridAlignment? {
        guard unit > 0, gridFamilies.contains(scene.name), !scene.nodes.isEmpty else { return nil }

        func onGrid(_ v: CGFloat) -> Bool {
            abs(v - (v / unit).rounded() * unit) < 0.5
        }

        var coordsOn = 0, nodesOn = 0
        for node in scene.nodes {
            let f = node.frame
            let flags = [onGrid(f.minX), onGrid(f.minY), onGrid(f.width), onGrid(f.height)]
            let hits = flags.filter { $0 }.count
            coordsOn += hits
            if hits == 4 { nodesOn += 1 }
        }
        return GridAlignment(unit: unit, nodes: scene.nodes.count, nodesOnGrid: nodesOn,
                             coordsOnGrid: coordsOn, coordsTotal: scene.nodes.count * 4)
    }
}
