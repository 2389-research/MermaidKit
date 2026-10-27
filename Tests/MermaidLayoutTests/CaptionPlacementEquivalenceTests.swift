import XCTest
@testable import MermaidLayout

/// The caption placer reads obstacles through a spatial grid, so a caption is
/// scored only against what's near it. It must place every caption exactly
/// where the all-pairs placer did (`ReferenceCaptionPlacer`), bit for bit:
/// output stays byte-identical. Checked over real layouts and over seeded
/// random inputs crowded enough that every term of the score is exercised.
final class CaptionPlacementEquivalenceTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: Double(text.count) * size * 0.55, height: size * 1.2)
    }

    private func assertSamePlacement(
        routes: [[CGPoint]], labelSizes: [CGSize?], nodeFrames: [CGRect],
        headInsets: [CGFloat] = [], tailInsets: [CGFloat] = [], labelRuns: [Int?] = [],
        _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let fast = DiagramLayoutEngine.placeRunLabels(
            routes: routes, labelSizes: labelSizes, nodeFrames: nodeFrames,
            headInsets: headInsets, tailInsets: tailInsets, labelRuns: labelRuns)
        let reference = ReferenceCaptionPlacer.placeRunLabelsReference(
            routes: routes, labelSizes: labelSizes, nodeFrames: nodeFrames,
            headInsets: headInsets, tailInsets: tailInsets, labelRuns: labelRuns)
        // Compare bit patterns: equal values that differ in sign of zero or
        // NaN-ness would still be a different output.
        func bits(_ p: CGPoint?) -> [UInt] { p.map { [$0.x.bitPattern, $0.y.bitPattern] } ?? [] }
        XCTAssertEqual(fast.map(bits), reference.map(bits), name, file: file, line: line)
    }

    /// The placer's inputs, as a laid-out flowchart gives them.
    private func assertSamePlacement(_ source: String, _ name: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else { return }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        let edges = layout.edges
        assertSamePlacement(
            routes: edges.map(\.points),
            labelSizes: edges.map { $0.label.map { measure($0, 12) } },
            nodeFrames: layout.nodes.map(\.frame),
            headInsets: edges.map { $0.hasArrow ? 11.5 : 0 },
            tailInsets: edges.map { $0.backArrow ? 11.5 : 0 },
            name, file: file, line: line)
    }

    func testRealLayoutsPlaceAlike() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = root.appendingPathComponent("Fixtures/diagrams")
        for name in try FileManager.default.contentsOfDirectory(atPath: fixtures.path).sorted() where name.hasSuffix(".mmd") {
            assertSamePlacement(try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8), name)
        }
        let cases = try JSONDecoder().decode(
            [String].self, from: Data(contentsOf: root.appendingPathComponent("tools/mermaid-oracle/cases.json")))
        for (i, source) in cases.enumerated() { assertSamePlacement(source, "oracle case \(i)") }
        // Crowded on purpose: fans and rows of captions, loops, back edges.
        func lines(_ n: Int, _ line: (Int) -> String) -> String { (0..<n).map(line).joined(separator: "\n") }
        var stress: [String] = []
        stress.append("flowchart TD\n" + lines(40) { " R -->|x| N\($0)" })
        stress.append("flowchart LR\n" + lines(40) { " R -->|label \($0)| N\($0)" })
        stress.append("flowchart TD\n" + lines(30) { " R --> N\($0)\n N\($0) -->|x| N\($0)" })
        stress.append("flowchart TD\n A --> T --> B\n" + lines(12) { " T -->|retry \($0)| T" })
        stress.append("flowchart TD\n" + lines(30) { " N\($0) -->|go \($0)| N\($0 + 1)\n N\($0 + 1) -->|back| N\($0 / 2)" })
        stress.append("flowchart LR\n A -->|a| B & C & D -->|b| E\n E -->|c| A\n B -->|d| D")
        for (i, source) in stress.enumerated() { assertSamePlacement(source, "stress \(i)") }
    }

    /// Random axis-aligned routes, boxes and captions, packed into a small
    /// canvas so captions, bends, crossings and arrowheads all collide.
    func testRandomInputsPlaceAlike() {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next(_ n: Int) -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(n))
        }
        func coord() -> CGFloat { CGFloat(next(600)) + CGFloat(next(4)) * 0.25 }
        for trial in 0..<300 {
            let frames = (0..<next(14)).map { _ in
                CGRect(x: coord(), y: coord(), width: CGFloat(20 + next(80)), height: CGFloat(16 + next(40)))
            }
            var routes: [[CGPoint]] = []
            for _ in 0..<(1 + next(24)) {
                var p = CGPoint(x: coord(), y: coord())
                var route = [p]
                for k in 0..<(1 + next(5)) {
                    p = k % 2 == 0 ? CGPoint(x: coord(), y: p.y) : CGPoint(x: p.x, y: coord())
                    route.append(p)
                }
                routes.append(next(10) == 0 ? [] : route)
            }
            let sizes: [CGSize?] = routes.map { _ in
                next(4) == 0 ? nil : CGSize(width: CGFloat(10 + next(90)), height: CGFloat(10 + next(8)))
            }
            let runs: [Int?] = routes.map { r in next(5) == 0 && r.count > 1 ? next(r.count - 1) : nil }
            assertSamePlacement(
                routes: routes, labelSizes: sizes, nodeFrames: frames,
                headInsets: routes.map { _ in next(2) == 0 ? 11.5 : 0 },
                tailInsets: routes.map { _ in next(3) == 0 ? 11.5 : 0 },
                labelRuns: runs, "trial \(trial)")
        }
    }

    /// The crossings the placer avoids are the all-pairs ones, as a multiset
    /// (only how many lie in a caption's way counts), over routes that mix
    /// horizontal, vertical, slanted and zero-length segments, and runs that
    /// share a line, as a fan's do.
    func testCrossingsAreTheAllPairsOnes() {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ n: Int) -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(n))
        }
        func coord() -> CGFloat { CGFloat(next(300)) + CGFloat(next(4)) * 0.25 }
        func key(_ p: CGPoint) -> [UInt] { [p.x.bitPattern, p.y.bitPattern] }
        for trial in 0..<300 {
            var routes: [[CGPoint]] = []
            let bus = coord()
            for _ in 0..<(2 + next(30)) {
                var p = CGPoint(x: coord(), y: next(3) == 0 ? bus : coord())
                var route = [p]
                for _ in 0..<(1 + next(5)) {
                    switch next(5) {
                    case 0: p = CGPoint(x: coord(), y: p.y)
                    case 1: p = CGPoint(x: p.x, y: coord())
                    case 2: p = CGPoint(x: coord(), y: bus)
                    case 3: p = CGPoint(x: coord(), y: coord())   // slanted
                    default: break                                // zero length
                    }
                    route.append(p)
                }
                routes.append(route)
            }
            XCTAssertEqual(DiagramLayoutEngine.routeCrossingPoints(routes).map(key).sorted { $0.lexicographicallyPrecedes($1) },
                           ReferenceCaptionPlacer.referenceCrossingPoints(routes).map(key).sorted { $0.lexicographicallyPrecedes($1) },
                           "trial \(trial)")
        }
    }
}
