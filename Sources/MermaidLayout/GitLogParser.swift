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
// Topology is resolved in two passes, so the parse never depends on the caller
// having run `--topo-order --reverse`. The FIRST pass parses every line into a
// raw record and records its full hash → index; the SECOND pass resolves each
// record's parent hashes against that complete map and stably topologically
// orders the records (Kahn's algorithm, lowest ready index first) so every
// parent precedes its child — the `GitGraph.parents` index invariant. An
// already-ordered source comes back unchanged; a `git log --graph` paste (which
// emits children before parents) is reordered rather than silently dropping
// links; a cyclic/unresolvable topology returns `nil`. A parent hash absent
// from the paste (truncated history) is dropped defensively, never trapped.
//
// Branch/lane derivation: a commit takes the branch named by its ref
// decoration; an undecorated commit inherits its first parent's lane; a root
// falls back to `main`. Each decorated branch is then propagated BACKWARD along
// its first-parent ancestry (newest tip first), so a feature branch's interior
// commits share the tip's lane instead of inheriting the mainline — a shared
// ancestor is kept by the most-recent (mainline) tip that reaches it.
// `branches` collects names in first-appearance (lane) order, so the mainline —
// typically the root's lane — sits first.
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

    /// Ultimate fallback lane for an undecorated root commit.
    private let defaultBranch = "main"

    init(source: String) { self.source = source }

    /// One parsed source line, before topology is resolved. Parent *hashes* are
    /// retained verbatim (capped at the first two — the linked parents); they
    /// become `commits` indices only once every record is known.
    private struct RawRecord {
        let hash: String
        let parentHashes: [String]   // first two parent hashes (the linked ones)
        let branch: String?          // decorated branch name, else nil
        let tag: String?
        var isMerge: Bool { parentHashes.count >= 2 }
    }

    func run() -> GitGraph? {
        // First pass: parse every line into a raw record and index its hash.
        // Ordering is NOT assumed — a `git log --graph` paste emits children
        // before parents, so parents are resolved against the *full* map below.
        var records: [RawRecord] = []
        var indexOfHash: [String: Int] = [:]        // full hash → raw record index
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = raw
            if line.hasSuffix("\r") { line = line.dropLast() }
            let stripped = stripGraphArt(String(line))
            if stripped.isEmpty { continue }        // blank / connector-only line
            guard let rec = parseRecord(stripped) else { continue }
            if indexOfHash[rec.hash] != nil { continue }   // ignore a duplicate hash
            indexOfHash[rec.hash] = records.count
            records.append(rec)
        }
        guard !records.isEmpty else { return nil }

        // Resolve each record's parents to *raw* indices (a dangling parent —
        // truncated history — is dropped defensively, never trapped) and hold
        // the shared `maxEdges` cap.
        var linkedParents: [[Int]] = []             // raw parent indices per record
        linkedParents.reserveCapacity(records.count)
        var totalEdges = 0
        for rec in records {
            let resolved = rec.parentHashes.compactMap { indexOfHash[$0] }
            totalEdges += resolved.count
            if totalEdges > MermaidParser.maxEdges { return nil }
            linkedParents.append(resolved)
        }

        // Second pass: a stable topological order (parents before children) so
        // the `parents` index invariant holds even for unordered input; a cycle
        // yields nil.
        guard let order = topologicalOrder(linkedParents: linkedParents) else { return nil }

        // Map raw index → final (emission) index, then rebuild parent links.
        var finalOf = [Int](repeating: 0, count: records.count)
        for (fi, rawIdx) in order.enumerated() { finalOf[rawIdx] = fi }
        var parentsOf = [[Int]](repeating: [], count: records.count)   // by final index
        var firstParentOf = [Int?](repeating: nil, count: records.count)
        for rawIdx in order {
            let fi = finalOf[rawIdx]
            let ps = linkedParents[rawIdx].map { finalOf[$0] }
            parentsOf[fi] = ps
            firstParentOf[fi] = ps.first
        }

        // Branch lanes (decoration → first-parent inheritance → backward
        // propagation from decorated tips), then emit in final order collecting
        // lane names in first-appearance order.
        let branchOf = assignBranches(order: order, records: records,
                                      firstParentOf: firstParentOf)
        var commits: [GitGraph.Commit] = []
        var branches: [String] = []
        commits.reserveCapacity(records.count)
        for (fi, rawIdx) in order.enumerated() {
            let rec = records[rawIdx]
            let branch = branchOf[fi]
            if !branches.contains(branch) { branches.append(branch) }
            commits.append(GitGraph.Commit(
                id: shortHash(rec.hash), branch: branch, tag: rec.tag,
                isMerge: rec.isMerge, parents: parentsOf[fi], hasExplicitID: true))
        }
        return GitGraph(commits: commits, branches: branches)
    }

    // MARK: topology

    /// A stable topological ordering of the raw records (every parent before its
    /// child) using the resolved parent links. Kahn's algorithm always emits the
    /// lowest ready raw index, so a source that is already topologically ordered
    /// comes back unchanged; a cycle (no valid order) yields `nil`.
    private func topologicalOrder(linkedParents: [[Int]]) -> [Int]? {
        let n = linkedParents.count
        var indegree = [Int](repeating: 0, count: n)
        var children = [[Int]](repeating: [], count: n)
        for (child, parents) in linkedParents.enumerated() {
            for p in parents {
                children[p].append(child)
                indegree[child] += 1
            }
        }
        var ready: [Int] = []
        for i in 0..<n where indegree[i] == 0 { ready.append(i) }   // ascending
        var order: [Int] = []
        order.reserveCapacity(n)
        var head = 0
        while head < ready.count {
            let node = ready[head]; head += 1
            order.append(node)
            for child in children[node] {
                indegree[child] -= 1
                if indegree[child] == 0 {
                    // Insert keeping `ready[head...]` ascending (lowest emits next).
                    var lo = head, hi = ready.count
                    while lo < hi {
                        let mid = (lo + hi) / 2
                        if ready[mid] < child { lo = mid + 1 } else { hi = mid }
                    }
                    ready.insert(child, at: lo)
                }
            }
        }
        return order.count == n ? order : nil       // short ⇒ a cycle remains
    }

    /// Computes each commit's branch lane (indexed by final position). Base
    /// rule, applied in topological order (a parent is always settled before its
    /// child): a decorated commit takes its ref's branch; an undecorated commit
    /// inherits its first parent's lane; a root falls back to the default. Then
    /// every decorated branch is propagated backward along its first-parent
    /// ancestry — processed newest-first so a shared ancestor is kept by the
    /// most-recent (mainline) tip that reaches it, leaving a feature branch's
    /// interior commits on the tip's lane rather than the mainline.
    private func assignBranches(order: [Int], records: [RawRecord],
                                firstParentOf: [Int?]) -> [String] {
        let n = order.count
        var branch = [String](repeating: defaultBranch, count: n)
        var decorated = [Bool](repeating: false, count: n)
        for (fi, rawIdx) in order.enumerated() {
            if let b = records[rawIdx].branch {
                branch[fi] = b
                decorated[fi] = true
            } else if let fp = firstParentOf[fi] {
                branch[fi] = branch[fp]
            }
        }
        var claimed = decorated
        for fi in stride(from: n - 1, through: 0, by: -1) {
            guard decorated[fi] else { continue }
            let b = branch[fi]
            var cur = firstParentOf[fi]
            while let p = cur, !claimed[p] {
                branch[p] = b
                claimed[p] = true
                cur = firstParentOf[p]
            }
        }
        return branch
    }

    // MARK: line parsing

    /// Parses one already-art-stripped line into a raw record, or `nil` when its
    /// leading token isn't a hash (a non-git / prose line).
    private func parseRecord(_ line: String) -> RawRecord? {
        var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let hash = tokens.first, isHash(hash) else { return nil }
        tokens.removeFirst()

        // Leading hash-shaped tokens are parent hashes (they stop at the `(…)`
        // decoration or the subject). Keep only the first two as links; a 3+-parent
        // octopus therefore still records two hashes, and `RawRecord.isMerge`
        // (count ≥ 2) reads true for it just as for an ordinary two-parent merge.
        var parentHashes: [String] = []
        while let t = tokens.first, isHash(t) {
            tokens.removeFirst()
            if parentHashes.count < 2 { parentHashes.append(t) }
        }

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

        return RawRecord(hash: hash, parentHashes: parentHashes,
                         branch: decoratedBranch, tag: tagName)
    }

    // MARK: decoration

    private struct DecodedRefs { let branch: String?; let tag: String? }

    /// Resolves a ref-decoration body (`HEAD -> main, tag: v1.0, origin/main`)
    /// into a preferred local branch name and an optional tag. Preference:
    /// the `HEAD -> …` branch, then a plain local branch, then a remote's
    /// trailing name; `tag: X` yields the tag; bare `HEAD` (detached) is ignored.
    /// A slash does NOT mark a remote — a local branch like `feature/login` or
    /// `release/1.2` keeps its full name; only the default `origin/` remote
    /// prefix is stripped, and solely to form the remote fallback name.
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
            if ref.hasPrefix("origin/") {
                // A remote-tracking ref like `origin/main`; use only its trailing
                // name, and only as a fallback. A slash alone does NOT signal a
                // remote — a local branch such as `feature/login` keeps its full
                // name (handled by the plain-local case below), so we strip the
                // prefix solely for the default `origin` remote.
                let name = String(ref.dropFirst("origin/".count))
                if !name.isEmpty, name != "HEAD", remoteBranch == nil { remoteBranch = name }
                continue
            }
            if localBranch == nil { localBranch = ref }         // plain local branch (slashes kept)
        }
        let branch = headBranch ?? localBranch ?? remoteBranch
        return DecodedRefs(branch: branch, tag: tag)
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
