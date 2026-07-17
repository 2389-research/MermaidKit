import Foundation

// A Swift front-end for `git log` that targets the existing `GitGraph` IR — the
// SAME target the Mermaid-native `gitGraph` parser builds (see
// `MermaidParser+GitGraph`) — so a pasted history flows through the identical
// layered layout → DiagramScene → renderer stack as a Mermaid `gitGraph`, a
// `.dot` graph, or a Dippin workflow.
//
// It parses the output of:
//
//     git log --all --topo-order --reverse --pretty=format:'%H %P%d %s'
//
// where each line is `<hash> <parenthashes…> (<refs>)? <subject>`:
//   • `%H` — the commit's full hash (first token).
//   • `%P` — space-separated parent hashes: empty (a root), one (normal), or
//     two+ (a merge — `isMerge`, keeping the first two parents).
//   • `%d` — the ref decoration `(HEAD -> main, tag: v1.0, origin/main)`, or
//     absent. `HEAD -> ` is stripped, a `tag: X` becomes the commit's `tag`,
//     a local branch name wins over an `origin/`-style remote.
//   • `%s` — the subject line. The `GitGraph` IR has no message field, so the
//     subject is intentionally dropped (folding it into every commit's `tag`
//     would bury the graph under callouts); each commit is instead identified
//     by its short hash, which reads like a real git graph.
//
// Branch/lane derivation: a commit takes the branch named by its ref
// decoration; an undecorated commit inherits its first parent's branch
// (carried forward along the first-parent chain — `--topo-order --reverse`
// guarantees parents are emitted before children, so the inherited branch is
// already known). `branches` collects names in first-appearance (lane) order,
// so the mainline — typically the root's lane — sits first.
//
// Parent hashes resolve to `commits` indices via a hash→index map built as the
// walk proceeds; a parent hash never seen (which topo+reverse should preclude)
// is dropped defensively rather than trapped.
//
// It also tolerates `git log --graph` output: the leading graph art
// (`* | / \ _` runs) is stripped from each line, and connector-only lines
// collapse to empty and are skipped, so a pasted `--graph` history doesn't
// break the parse.
//
// Like the other front-ends it degrades gracefully: an empty, non-git,
// oversized, or otherwise unparseable source returns `nil`, and the shared
// `maxTextSize`/`maxEdges` caps hold. It never crashes or hangs — every scan
// makes forward progress.
public enum GitLogParser {

    /// Parses `git log` output into the `GitGraph` IR; `nil` for an empty,
    /// non-git, oversized, or otherwise unparseable source.
    public static func parse(_ source: String) -> GitGraph? {
        guard source.count <= MermaidParser.maxTextSize else { return nil }
        return GitLogParserImpl(source: source).run()
    }
}

// MARK: - Implementation

private final class GitLogParserImpl {

    private let source: String

    // IR accumulators.
    private var commits: [GitGraph.Commit] = []
    private var branches: [String] = []
    private var indexOfHash: [String: Int] = [:]   // full hash → commits index
    private var branchOfIndex: [String] = []        // branch name per emitted commit

    /// Running edge count (sum of resolved parent links) for the `maxEdges` cap.
    private var edgeCount = 0

    /// Ultimate fallback lane for an undecorated root commit.
    private let defaultBranch = "main"

    init(source: String) { self.source = source }

    func run() -> GitGraph? {
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = raw
            if line.hasSuffix("\r") { line = line.dropLast() }
            let stripped = stripGraphArt(String(line))
            if stripped.isEmpty { continue }        // blank / connector-only line
            guard let commit = parseCommit(stripped) else { continue }
            let idx = commits.count
            commits.append(commit.commit)
            indexOfHash[commit.hash] = idx
            branchOfIndex.append(commit.commit.branch)
            registerBranch(commit.commit.branch)
            edgeCount += commit.commit.parents.count
            if edgeCount > MermaidParser.maxEdges { return nil }
        }
        guard !commits.isEmpty else { return nil }
        return GitGraph(commits: commits, branches: branches)
    }

    // MARK: line parsing

    private struct ParsedCommit { let hash: String; let commit: GitGraph.Commit }

    /// Parses one already-art-stripped line into a commit, or `nil` when its
    /// leading token isn't a hash (a non-git / prose line).
    private func parseCommit(_ line: String) -> ParsedCommit? {
        var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let hash = tokens.first, isHash(hash) else { return nil }
        tokens.removeFirst()

        // Consume leading hash-shaped tokens as parents (stops at the decoration
        // `(…)` or the subject). `--topo-order --reverse` puts parents ahead of
        // children, so each is already in `indexOfHash`; an unseen hash is
        // dropped defensively.
        var parentIndices: [Int] = []
        var isMerge = false
        var parentCount = 0
        while let t = tokens.first, isHash(t) {
            tokens.removeFirst()
            parentCount += 1
            // A merge is two-or-more parents; we keep only the first two links.
            if parentCount <= 2, let pIdx = indexOfHash[t] { parentIndices.append(pIdx) }
        }
        if parentCount >= 2 { isMerge = true }

        // Ref decoration: a leading `(…)` group (which may itself span several
        // whitespace tokens, e.g. `(HEAD -> main, origin/main)`).
        var tagName: String?
        var decoratedBranch: String?
        if let first = tokens.first, first.hasPrefix("(") {
            var decoTokens: [String] = []
            while let t = tokens.first {
                tokens.removeFirst()
                decoTokens.append(t)
                if t.hasSuffix(")") { break }
            }
            var deco = decoTokens.joined(separator: " ")
            if deco.hasPrefix("(") { deco.removeFirst() }
            if deco.hasSuffix(")") { deco.removeLast() }
            let refs = parseDecoration(deco)
            decoratedBranch = refs.branch
            tagName = refs.tag
        }
        // Remaining tokens are the subject — intentionally dropped (no IR field).

        // Branch: decoration wins; else inherit first parent's lane; else the
        // default mainline for an undecorated root.
        let branch = decoratedBranch
            ?? parentIndices.first.map { branchOfIndex[$0] }
            ?? defaultBranch

        let commit = GitGraph.Commit(
            id: shortHash(hash), branch: branch, tag: tagName,
            isMerge: isMerge, parents: parentIndices, hasExplicitID: true)
        return ParsedCommit(hash: hash, commit: commit)
    }

    // MARK: decoration

    private struct DecodedRefs { let branch: String?; let tag: String? }

    /// Resolves a ref-decoration body (`HEAD -> main, tag: v1.0, origin/main`)
    /// into a preferred local branch name and an optional tag. Preference:
    /// the `HEAD -> …` branch, then a plain local branch, then a remote's
    /// trailing name; `tag: X` yields the tag; bare `HEAD` (detached) is ignored.
    private func parseDecoration(_ body: String) -> DecodedRefs {
        var headBranch: String?
        var localBranch: String?
        var remoteBranch: String?
        var tag: String?

        for rawRef in body.split(separator: ",") {
            let ref = rawRef.trimmingCharacters(in: .whitespaces)
            if ref.isEmpty { continue }
            if let arrow = ref.range(of: "->") {
                // `HEAD -> main`
                let name = String(ref[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, headBranch == nil { headBranch = name }
                continue
            }
            if ref.hasPrefix("tag:") {
                let name = String(ref.dropFirst("tag:".count)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, tag == nil { tag = name }
                continue
            }
            if ref == "HEAD" { continue }                       // detached HEAD
            if let slash = ref.firstIndex(of: "/") {
                // A remote-tracking (or namespaced) ref like `origin/main`.
                let name = String(ref[ref.index(after: slash)...])
                if !name.isEmpty, name != "HEAD", remoteBranch == nil { remoteBranch = name }
                continue
            }
            if localBranch == nil { localBranch = ref }         // plain local branch
        }
        let branch = headBranch ?? localBranch ?? remoteBranch
        return DecodedRefs(branch: branch, tag: tag)
    }

    private func registerBranch(_ name: String) {
        if !branches.contains(name) { branches.append(name) }
    }

    // MARK: lexical helpers

    /// Strips a leading run of `git log --graph` art (`* | / \ _` and spaces)
    /// from a line, leaving the commit content (or empty for a connector line).
    private func stripGraphArt(_ line: String) -> String {
        let art: Set<Character> = ["*", "|", "/", "\\", "_", " ", "\t"]
        var idx = line.startIndex
        while idx < line.endIndex, art.contains(line[idx]) { idx = line.index(after: idx) }
        return String(line[idx...]).trimmingCharacters(in: .whitespaces)
    }

    /// True when a token looks like a git object hash: 7+ hex digits, all hex.
    /// (Full `%H`/`%P` hashes are 40 chars; the lower bound tolerates abbreviated
    /// output while keeping ordinary subject words from reading as parents.)
    private func isHash(_ s: String) -> Bool {
        guard s.count >= 7 else { return false }
        for ch in s where !ch.isHexDigit { return false }
        return true
    }

    /// A short, display-friendly 7-char hash prefix (the commit's drawn id).
    private func shortHash(_ hash: String) -> String {
        String(hash.prefix(7))
    }
}
