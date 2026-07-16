import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A machine/LLM-readable "perceptual diff" between two diagram layouts —
/// expressed over the semantic scene, not pixels. Answers *what* changed
/// (nodes moved, edges rerouted, canvas resized) and, via the lint delta,
/// *whether it got better* (which layout violations cleared or appeared).
/// This is the level a code change should be judged at, above a pixel pdiff
/// (which sees a heatmap but no meaning) and above a rendered PNG (which I
/// read unreliably).
public struct SceneDelta: Sendable {
    /// Nodes present in both scenes whose centers moved more than
    /// `moveEpsilon`; `delta` is the center displacement in points.
    public var movedNodes: [(id: String, delta: CGVector)] = []
    /// Node ids present only in the after scene.
    public var addedNodes: [String] = []
    /// Node ids present only in the before scene.
    public var removedNodes: [String] = []
    /// Count of index-matched edges whose polylines differ: a vertex moved
    /// more than `moveEpsilon`, or the vertex count changed.
    public var reroutedEdges: Int = 0
    /// Canvas size of the before scene, in points.
    public var sizeBefore: CGSize
    /// Canvas size of the after scene, in points.
    public var sizeAfter: CGSize

    /// True when nothing moved, appeared, disappeared, rerouted, or resized.
    public var isEmpty: Bool {
        movedNodes.isEmpty && addedNodes.isEmpty && removedNodes.isEmpty
            && reroutedEdges == 0 && sizeBefore == sizeAfter
    }

    /// One-line human summary, e.g. "+2 nodes · 3 nodes moved (max 14pt)".
    public var summary: String {
        if isEmpty { return "no scene change" }
        var parts: [String] = []
        if !addedNodes.isEmpty { parts.append("+\(addedNodes.count) nodes") }
        if !removedNodes.isEmpty { parts.append("-\(removedNodes.count) nodes") }
        if !movedNodes.isEmpty {
            let maxMove = movedNodes.map { hypot($0.delta.dx, $0.delta.dy) }.max() ?? 0
            parts.append("\(movedNodes.count) nodes moved (max \(Int(maxMove))pt)")
        }
        if reroutedEdges > 0 { parts.append("\(reroutedEdges) edges rerouted") }
        if sizeBefore != sizeAfter {
            parts.append("canvas \(Int(sizeBefore.width))×\(Int(sizeBefore.height))→\(Int(sizeAfter.width))×\(Int(sizeAfter.height))")
        }
        return parts.joined(separator: " · ")
    }
}

/// The lint-violation change between two scenes — which layout problems a
/// code change fixed and which it introduced.
public struct LintDelta: Sendable {
    /// Violations present before but gone after — fixes.
    public let cleared: [LayoutViolation]
    /// Violations present after but not before — regressions.
    public let introduced: [LayoutViolation]
    /// Error-severity violation count in the before scene.
    public let errorsBefore: Int
    /// Error-severity violation count in the after scene.
    public let errorsAfter: Int

    /// One-line judgment on error counts alone: fixed (now zero), regressed
    /// (new errors introduced), improved (some cleared), or no error change.
    public var verdict: String {
        let clearedErr = cleared.filter { $0.severity == .error }.count
        let newErr = introduced.filter { $0.severity == .error }.count
        if errorsAfter == 0, errorsBefore > 0 { return "✓ fixed (\(errorsBefore) → 0 errors)" }
        if newErr > 0 { return "✗ regressed (+\(newErr) errors)" }
        if clearedErr > 0 { return "↓ improved (\(errorsBefore) → \(errorsAfter) errors)" }
        return "= no error change (\(errorsAfter) errors)"
    }
}

extension DiagramScene {
    /// Structured scene diff, matching nodes by id and edges by index.
    /// Movement at or below `moveEpsilon` (points, default 1) is ignored,
    /// both for node centers and edge vertices.
    public func delta(to after: DiagramScene, moveEpsilon: CGFloat = 1) -> SceneDelta {
        var d = SceneDelta(sizeBefore: size, sizeAfter: after.size)
        let beforeByID = Dictionary(nodes.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        let afterByID = Dictionary(after.nodes.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        for (id, _) in afterByID where beforeByID[id] == nil { d.addedNodes.append(id) }
        for (id, b) in beforeByID {
            guard let a = afterByID[id] else { d.removedNodes.append(id); continue }
            let dx = a.midX - b.midX, dy = a.midY - b.midY
            if hypot(dx, dy) > moveEpsilon { d.movedNodes.append((id, CGVector(dx: dx, dy: dy))) }
        }
        for i in 0..<Swift.min(edges.count, after.edges.count) {
            if !polylinesEqual(edges[i].polyline, after.edges[i].polyline, epsilon: moveEpsilon) {
                d.reroutedEdges += 1
            }
        }
        return d
    }

    private func polylinesEqual(_ a: [CGPoint], _ b: [CGPoint], epsilon: CGFloat) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) <= epsilon }
    }
}

extension DiagramLayoutLinter {
    /// The violations cleared and introduced between two scenes — the
    /// "did this change help?" signal.
    public static func delta(before: DiagramScene, after: DiagramScene) -> LintDelta {
        let b = lint(before), a = lint(after)
        let cleared = b.filter { !a.contains($0) }
        let introduced = a.filter { !b.contains($0) }
        return LintDelta(
            cleared: cleared,
            introduced: introduced,
            errorsBefore: b.filter { $0.severity == .error }.count,
            errorsAfter: a.filter { $0.severity == .error }.count
        )
    }
}
