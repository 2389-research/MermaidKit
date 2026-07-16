import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Lints every diagram in `Fixtures/diagrams/` over its exact geometry (see
/// `DiagramScene` / `DiagramLayoutLinter`) — catching edges behind nodes,
/// overlapping boxes, off-canvas and colliding labels without rendering a
/// pixel. Types that lay out cleanly today are asserted to STAY clean (a real
/// regression guard); types with known layout debt are listed so the test
/// documents the state and fails loudly the day one is fixed (so it graduates
/// to the clean set) or regresses further.
final class LayoutLintTests: XCTestCase {

    /// Deterministic fake measurer — geometry only, no font metrics.
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    /// Types whose complex fixture lays out with ZERO errors. Adding a type
    /// here makes its clean layout load-bearing.
    private let errorFree: Set<String> = [
        "flowchart", "sequence", "gantt", "journey", "kanban", "mindmap",
        "packet", "radar", "timeline", "treemap", "zenuml", "state",
        "block", "c4", "gitgraph", "pie", "quadrant", "requirement",
        "sankey", "xychart", "er", "class", "architecture",
        "treeview", "venn", "cynefin", "wardley",
        "ishikawa", "eventmodeling", "swimlane",
    ]

    /// Known layout debt: empty — every fixture lays out with zero occlusion,
    /// overlap, off-canvas or escaping-mark errors under the honest linter.
    private let knownIssues: Set<String> = []

    private var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
    }

    /// Self-verification for a single type: `MERMAIDKIT_LINT_TYPE=architecture swift
    /// test --filter testLintSingleType` lints only that fixture and FAILS with
    /// the violation list unless it is error-free. The red/green a fix loop
    /// iterates against — no rendering, no vision.
    func testLintSingleType() throws {
        guard let type = ProcessInfo.processInfo.environment["MERMAIDKIT_LINT_TYPE"] else {
            throw XCTSkip("set MERMAIDKIT_LINT_TYPE=<type> to lint one fixture")
        }
        let source = try String(contentsOf: fixturesDir.appendingPathComponent("\(type).mmd"), encoding: .utf8)
        guard let diagram = MermaidParser.parse(source) else { return XCTFail("\(type): did not parse") }
        let violations = DiagramLayoutLinter.lint(DiagramScene.lower(diagram, measure: measure))
        let errors = violations.filter { $0.severity == .error }
        print(DiagramLayoutLinter.report(DiagramScene.lower(diagram, measure: measure)))
        XCTAssertTrue(errors.isEmpty, "\(type): \(errors.count) layout errors remain")
    }

    func testFixtureLayoutsAreClean() throws {
        let files = try FileManager.default.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 20, "expected the full diagram fixture set")

        for url in files {
            let type = url.deletingPathExtension().lastPathComponent
            let source = try String(contentsOf: url, encoding: .utf8)
            guard let diagram = MermaidParser.parse(source) else {
                XCTFail("\(type): fixture did not parse"); continue
            }
            let scene = DiagramScene.lower(diagram, measure: measure)
            let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }

            if errorFree.contains(type) {
                XCTAssertTrue(errors.isEmpty,
                    "\(type) is expected to lay out cleanly but the linter found:\n" +
                    errors.map { "  ✗ [\($0.kind)] \($0.detail)" }.joined(separator: "\n"))
            } else if knownIssues.contains(type), !errors.isEmpty {
                // Documented debt: fine for now. When this list empties, move the
                // type to `errorFree`.
            } else if !errorFree.contains(type) && !knownIssues.contains(type) {
                XCTFail("\(type): unclassified — add it to errorFree or knownIssues")
            }
        }
    }
}
