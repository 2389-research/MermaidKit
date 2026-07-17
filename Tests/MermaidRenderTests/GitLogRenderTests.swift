// A `git log` history parsed to `GitGraph` must render to a PNG (commit dots,
// branch lanes, merge links, tags) in both themes without trapping — the same
// "never trap on a parsed diagram" contract the other front-ends hold.
#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
@testable import MermaidRender
@testable import MermaidLayout

final class GitLogRenderTests: XCTestCase {

    func testGitLogGraphRendersBothThemes() throws {
        // `git log --all --topo-order --reverse --pretty=format:'%H %P%d %s'`
        // with a branch, a two-parent merge, and a tag.
        let src = """
        8830ab21287bad4ffe7140722e7696937f0e6059  init
        f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 8830ab21287bad4ffe7140722e7696937f0e6059 (tag: v1.0) second
        51d6e7eca179c3629a518774c1809d0571c9f66a f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 main C
        29ecf1d0ceb727b0614998355fccc95a457c2651 f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 feat A
        bcede20350894ba833bdce3f6e4b157112752b70 29ecf1d0ceb727b0614998355fccc95a457c2651 (feature) feat B
        d79597deee56d89a89f58662bcfd0f2bc7f074a4 51d6e7eca179c3629a518774c1809d0571c9f66a bcede20350894ba833bdce3f6e4b157112752b70 (HEAD -> main) merge feature
        """
        let graph = try XCTUnwrap(GitLogParser.parse(src), "git log failed to parse")
        let diagram = MermaidDiagram.gitGraph(graph)
        for prefersDark in [false, true] {
            let theme = DiagramTheme(prefersDark: prefersDark)
            let png = try XCTUnwrap(
                MermaidRenderer.pngData(diagram: diagram, theme: theme),
                "git log-derived GitGraph rendered nil (prefersDark=\(prefersDark))")
            XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47],
                           "not a PNG (prefersDark=\(prefersDark))")
        }
    }
}
#endif
