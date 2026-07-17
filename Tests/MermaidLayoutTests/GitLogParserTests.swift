import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Exercises the `git log` front-end (`GitLogParser`) against the shared
/// `GitGraph` IR — the same target the Mermaid-native `gitGraph` parser builds.
/// It covers the happy paths (linear history; a branch + merge; a `tag:`
/// decoration; multiple branches and their lane order) and, non-negotiably, that
/// malformed/hostile input never crashes or hangs (nil is always acceptable): an
/// empty source, non-git prose, an oversized source, the `maxEdges` cap, pasted
/// `git log --graph` art, and unicode. A final case runs the full parse →
/// layout → scene → lint pipeline and asserts it comes back clean.
final class GitLogParserTests: XCTestCase {

    private let measure: DiagramTextMeasurer = { text, size in
        let lines = text.components(separatedBy: "\n")
        let cols = lines.map { $0.count }.max() ?? 1
        return CGSize(width: CGFloat(max(cols, 1)) * size * 0.6,
                      height: CGFloat(max(lines.count, 1)) * (size + 4))
    }

    private func parse(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> GitGraph {
        guard let g = GitLogParser.parse(s) else {
            XCTFail("expected a parse", file: file, line: line)
            return GitGraph(commits: [], branches: [])
        }
        return g
    }

    /// Asserts the core `GitGraph` invariant: every parent is an index into
    /// `commits` that precedes its child (a valid topological order).
    private func assertTopoValid(_ g: GitGraph, file: StaticString = #filePath, line: UInt = #line) {
        for (i, c) in g.commits.enumerated() {
            for p in c.parents {
                XCTAssertTrue(p >= 0 && p < i,
                              "commit \(i) (\(c.id)) has out-of-order parent index \(p)",
                              file: file, line: line)
            }
        }
    }

    // MARK: happy path — linear history

    func testLinearHistory() {
        // `git log --all --topo-order --reverse --pretty=format:'%H %P%d %s'`:
        // an undecorated root, then two children; the tip carries `HEAD -> main`.
        let src = """
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  first commit
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa second commit
        cccccccccccccccccccccccccccccccccccccccc bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (HEAD -> main) third commit
        """
        let g = parse(src)
        XCTAssertEqual(g.commits.count, 3)
        XCTAssertEqual(g.commits.map(\.id), ["aaaaaaa", "bbbbbbb", "ccccccc"])
        XCTAssertEqual(g.branches, ["main"])
        XCTAssertEqual(g.commits.map(\.parents), [[], [0], [1]])
        XCTAssertFalse(g.commits.contains { $0.isMerge })
        XCTAssertTrue(g.commits.allSatisfy { $0.branch == "main" })
        assertTopoValid(g)
    }

    // MARK: happy path — branch + merge + tag

    /// A real `git log` history: an `init` root, a tagged `second`, a `main C`
    /// on the trunk, `feat A`/`feat B` on a `feature` branch, and a two-parent
    /// merge back onto `main`.
    private let branchAndMerge = """
    8830ab21287bad4ffe7140722e7696937f0e6059  init
    f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 8830ab21287bad4ffe7140722e7696937f0e6059 (tag: v1.0) second
    51d6e7eca179c3629a518774c1809d0571c9f66a f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 main C
    29ecf1d0ceb727b0614998355fccc95a457c2651 f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 feat A
    bcede20350894ba833bdce3f6e4b157112752b70 29ecf1d0ceb727b0614998355fccc95a457c2651 (feature) feat B
    d79597deee56d89a89f58662bcfd0f2bc7f074a4 51d6e7eca179c3629a518774c1809d0571c9f66a bcede20350894ba833bdce3f6e4b157112752b70 (HEAD -> main) merge feature
    """

    func testBranchAndMerge() {
        let g = parse(branchAndMerge)
        XCTAssertEqual(g.commits.count, 6)
        XCTAssertEqual(g.commits.map(\.id),
                       ["8830ab2", "f725795", "51d6e7e", "29ecf1d", "bcede20", "d79597d"])

        // Lane order: the mainline (the default root lane) precedes `feature`.
        XCTAssertEqual(g.branches, ["main", "feature"])

        // The `feature`-decorated tip is assigned to `feature`.
        XCTAssertEqual(g.commits[4].branch, "feature")

        // The final commit is a two-parent merge onto main.
        let merge = g.commits[5]
        XCTAssertTrue(merge.isMerge)
        XCTAssertEqual(merge.parents, [2, 4])
        XCTAssertEqual(merge.branch, "main")

        // Non-merge commits have at most one parent.
        XCTAssertTrue(g.commits.dropLast().allSatisfy { $0.parents.count <= 1 })
        assertTopoValid(g)
    }

    func testTagDecoration() {
        let g = parse(branchAndMerge)
        XCTAssertEqual(g.commits[1].tag, "v1.0")           // `(tag: v1.0)`
        // A tag decoration does not leak into the branch label.
        XCTAssertEqual(g.commits[1].branch, "main")
        // Untagged commits carry no tag.
        XCTAssertNil(g.commits[0].tag)
        XCTAssertNil(g.commits[5].tag)
    }

    // MARK: happy path — multiple branches, lane order

    func testMultipleBranchesLaneOrder() {
        // Two feature lanes branch off main; each tip is decorated. Lane order
        // follows first appearance of a commit on each branch.
        let src = """
        1111111111111111111111111111111111111111  root
        2222222222222222222222222222222222222222 1111111111111111111111111111111111111111 (alpha) a1
        3333333333333333333333333333333333333333 1111111111111111111111111111111111111111 (beta) b1
        4444444444444444444444444444444444444444 1111111111111111111111111111111111111111 (HEAD -> main) m2
        """
        let g = parse(src)
        XCTAssertEqual(g.commits.count, 4)
        // root defaults to main; then alpha, then beta appear (main's own tip is
        // last but main already exists as the root's lane, so it stays first).
        XCTAssertEqual(g.branches, ["main", "alpha", "beta"])
        XCTAssertEqual(g.commits[1].branch, "alpha")
        XCTAssertEqual(g.commits[2].branch, "beta")
        XCTAssertEqual(g.commits[3].branch, "main")
        assertTopoValid(g)
    }

    // MARK: adversarial

    func testEmptyIsNil() {
        XCTAssertNil(GitLogParser.parse(""))
        XCTAssertNil(GitLogParser.parse("   \n  \n"))
    }

    func testNonGitTextIsNil() {
        XCTAssertNil(GitLogParser.parse("this is just some prose, not a git log at all"))
        XCTAssertNil(GitLogParser.parse("The quick brown fox\njumps over\nthe lazy dog"))
        // A leading short word that isn't a 7+ hex hash must not read as a commit.
        XCTAssertNil(GitLogParser.parse("commit abc\nAuthor: someone\n\n    a message"))
    }

    func testOversizedIsNil() {
        let huge = String(repeating: "a", count: MermaidParser.maxTextSize + 1)
        XCTAssertNil(GitLogParser.parse(huge))
    }

    func testEdgeCapIsNil() {
        // A linear history longer than `maxEdges` links exceeds the cap → nil.
        var lines: [String] = []
        func hash(_ n: Int) -> String { String(format: "%040x", n) }
        lines.append("\(hash(0))  root")
        for i in 1...(MermaidParser.maxEdges + 1) {
            lines.append("\(hash(i)) \(hash(i - 1)) commit \(i)")
        }
        XCTAssertNil(GitLogParser.parse(lines.joined(separator: "\n")))

        // One under the cap still parses.
        var ok: [String] = ["\(hash(0))  root"]
        for i in 1...(MermaidParser.maxEdges - 1) {
            ok.append("\(hash(i)) \(hash(i - 1)) commit \(i)")
        }
        XCTAssertNotNil(GitLogParser.parse(ok.joined(separator: "\n")))
    }

    func testGraphArtIsStripped() {
        // Pasted `git log --all --graph …` output, art prefixes and all. It must
        // parse without crashing, strip the `* | \ /` art, and skip the pure
        // connector lines — every emitted id is a clean 7-char hash.
        let src = """
        *   d79597deee56d89a89f58662bcfd0f2bc7f074a4 51d6e7eca179c3629a518774c1809d0571c9f66a bcede20350894ba833bdce3f6e4b157112752b70 (HEAD -> main) merge feature
        |\\
        | * bcede20350894ba833bdce3f6e4b157112752b70 29ecf1d0ceb727b0614998355fccc95a457c2651 (feature) feat B
        | * 29ecf1d0ceb727b0614998355fccc95a457c2651 f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 feat A
        * | 51d6e7eca179c3629a518774c1809d0571c9f66a f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 main C
        |/
        * f725795ff72fcd2532ce3b2f60cb8ae49d492bd3 8830ab21287bad4ffe7140722e7696937f0e6059 (tag: v1.0) second
        * 8830ab21287bad4ffe7140722e7696937f0e6059  init
        """
        let g = parse(src)
        XCTAssertEqual(g.commits.count, 6)
        XCTAssertTrue(g.commits.allSatisfy { $0.id.count == 7 })
        XCTAssertTrue(g.commits.allSatisfy { c in
            !c.id.contains("*") && !c.id.contains("|") && !c.id.contains("\\")
        })
        assertTopoValid(g)
    }

    func testUnicodeSubjectDoesNotBreak() {
        // Unicode in the (dropped) subject and a tag must not trap or corrupt
        // the parse; the commit structure is still recovered.
        let src = """
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  🎉 initial café commit — naïve façade
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa (tag: v1.0-日本語) 日本語のコミット
        """
        let g = parse(src)
        XCTAssertEqual(g.commits.count, 2)
        XCTAssertEqual(g.commits.map(\.parents), [[], [0]])
        XCTAssertEqual(g.commits[1].tag, "v1.0-日本語")
        assertTopoValid(g)
    }

    func testMalformedNeverTraps() {
        // A grab bag of hostile lines: none may crash; nil is acceptable.
        let cases = [
            "(((",
            ")))",
            "abcdef (unterminated",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa deadbeefdeadbeef more words here",
            "\u{0}\u{1}\u{2}",
            String(repeating: "* | \\ /\n", count: 200),
        ]
        for c in cases {
            _ = GitLogParser.parse(c)   // just must not trap
        }
    }

    // MARK: full pipeline — parse → layout → scene lints clean

    func testParseLayoutSceneLintsClean() {
        let g = parse(branchAndMerge)
        let scene = DiagramScene.lower(.gitGraph(g), measure: measure)
        XCTAssertGreaterThan(scene.size.width, 0)
        let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "layout errors: \(errors)")
    }
}
