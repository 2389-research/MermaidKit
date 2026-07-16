import Foundation

extension MermaidParser {

    /// Parses `gitGraph` body commands: `commit [id: "…"] [tag: "…"]`,
    /// `branch <name>` (starts at the current head and becomes current),
    /// `checkout`/`switch <name>`, and `merge <name>` (two-parent commit).
    /// Branches keep creation order; ones that never receive a commit are
    /// dropped. Nil when there are no commits.
    static func parseGitGraph(body: [String]) -> GitGraph? {
        let main = "main"
        var branches = [main]
        var current = main
        var headOfBranch: [String: Int] = [:]   // branch → index of its latest commit
        var commits: [GitGraph.Commit] = []
        var autoID = 0

        /// Extracts a `key: "value"` (or `key: value`) field from a command.
        func field(_ key: String, in line: String) -> String? {
            guard let range = line.range(of: "\(key):") else { return nil }
            var rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("\"") {
                rest = String(rest.dropFirst())
                if let close = rest.firstIndex(of: "\"") { return String(rest[..<close]) }
            }
            return rest.split(separator: " ").first.map(String.init)
        }

        for line in body {
            let tokens = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard let command = tokens.first else { continue }
            switch command {
            case "commit":
                let parent = headOfBranch[current]
                let explicit = field("id", in: line)
                let id = explicit ?? { autoID += 1; return "c\(autoID)" }()
                commits.append(GitGraph.Commit(
                    id: id, branch: current, tag: field("tag", in: line),
                    isMerge: false, parents: parent.map { [$0] } ?? [],
                    hasExplicitID: explicit != nil))
                headOfBranch[current] = commits.count - 1

            case "branch":
                guard tokens.count > 1 else { continue }
                let name = tokens[1].split(separator: " ").first.map(String.init) ?? tokens[1]
                if !branches.contains(name) { branches.append(name) }
                // New branch starts at the current branch's head, then becomes current.
                headOfBranch[name] = headOfBranch[current]
                current = name

            case "checkout", "switch":
                guard tokens.count > 1 else { continue }
                let name = tokens[1].split(separator: " ").first.map(String.init) ?? tokens[1]
                if branches.contains(name) { current = name }

            case "cherry-pick":
                // `cherry-pick id:"X" [tag:"..."]` re-applies commit X on the
                // current branch. The commit must appear on the timeline —
                // skipping the line silently erased it.
                let picked = field("id", in: line) ?? "?"
                autoID += 1
                let id = "cherry-pick \(picked)"
                commits.append(GitGraph.Commit(
                    id: id, branch: current,
                    tag: field("tag", in: line) ?? "cherry-pick: \(picked)",
                    isMerge: false,
                    parents: headOfBranch[current].map { [$0] } ?? [],
                    hasExplicitID: false))
                headOfBranch[current] = commits.count - 1
            case "merge":
                guard tokens.count > 1 else { continue }
                let from = tokens[1].split(separator: " ").first.map(String.init) ?? tokens[1]
                var parents: [Int] = []
                if let head = headOfBranch[current] { parents.append(head) }
                if let sourceHead = headOfBranch[from] { parents.append(sourceHead) }
                autoID += 1
                commits.append(GitGraph.Commit(
                    id: field("id", in: line) ?? "merge\(autoID)", branch: current,
                    tag: field("tag", in: line), isMerge: true, parents: parents,
                    hasExplicitID: field("id", in: line) != nil))
                headOfBranch[current] = commits.count - 1

            default:
                continue
            }
        }

        guard !commits.isEmpty else { return nil }
        // Drop branches that never received a commit (e.g. a lane with no work).
        let used = Set(commits.map(\.branch))
        return GitGraph(commits: commits, branches: branches.filter { used.contains($0) })
    }
}
