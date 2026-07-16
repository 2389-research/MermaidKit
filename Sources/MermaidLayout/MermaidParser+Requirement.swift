import Foundation

/// A Mermaid `requirementDiagram`: typed requirement boxes, element boxes, and
/// verb-labelled relationships between them. Requirement blocks carry an id,
/// descriptive text, a risk level, and a verification method; element blocks
/// carry a type and optional document reference.
public struct RequirementDiagram: Hashable, Sendable {

    /// The six requirement flavours Mermaid recognises. The raw value is the
    /// block keyword, which doubles as the box stereotype.
    public enum Kind: String, Hashable, Sendable {
        case requirement = "requirement"
        case functional = "functionalRequirement"
        case performance = "performanceRequirement"
        case interface = "interfaceRequirement"
        case physical = "physicalRequirement"
        case designConstraint = "designConstraint"
    }

    /// One requirement box, keyed by `name`. All body properties are nil
    /// when the block omits them.
    public struct Requirement: Hashable, Sendable {
        public let name: String
        public let kind: Kind
        public let id: String?
        public let text: String?
        public let risk: String?
        public let verifyMethod: String?
        /// Memberwise initializer.
        public init(name: String, kind: Kind, id: String?, text: String?,
                    risk: String?, verifyMethod: String?) {
            self.name = name
            self.kind = kind
            self.id = id
            self.text = text
            self.risk = risk
            self.verifyMethod = verifyMethod
        }
    }

    /// One element box (a design artifact that relations tie to
    /// requirements), keyed by `name`; `type`/`docRef` are nil when omitted.
    public struct Element: Hashable, Sendable {
        public let name: String
        public let type: String?
        public let docRef: String?
        /// Memberwise initializer.
        public init(name: String, type: String?, docRef: String?) {
            self.name = name
            self.type = type
            self.docRef = docRef
        }
    }

    /// The relationship verb; the raw value is drawn as the arrow label.
    public enum RelationKind: String, Hashable, Sendable {
        case satisfies, traces, derives, refines, contains, copies, verifies
    }

    /// A verb-labelled arrow; `source`/`dest` are requirement or element
    /// names.
    public struct Relation: Hashable, Sendable {
        public let source: String
        public let dest: String
        public let kind: RelationKind
        /// Memberwise initializer.
        public init(source: String, dest: String, kind: RelationKind) {
            self.source = source
            self.dest = dest
            self.kind = kind
        }
    }

    public var requirements: [Requirement]
    public var elements: [Element]
    public var relations: [Relation]

    /// Memberwise initializer.
    public init(requirements: [Requirement], elements: [Element], relations: [Relation]) {
        self.requirements = requirements
        self.elements = elements
        self.relations = relations
    }
}

extension MermaidParser {

    /// Parses a `requirementDiagram`. Requirement/element blocks are
    /// brace-delimited `key: value` bodies (either multi-line or with content
    /// trailing the `{`); relationships are `src - verb -> dst` lines (the
    /// reversed `dst <- verb - src` form is also accepted). The shared `parse`
    /// already trims each line, which is fine here — only braces and arrows are
    /// significant, not indentation.
    static func parseRequirement(body: [String]) -> RequirementDiagram? {
        var requirements: [RequirementDiagram.Requirement] = []
        var elements: [RequirementDiagram.Element] = []
        var relations: [RequirementDiagram.Relation] = []

        // Accumulated inner `key: value` lines of the block currently open.
        var openKeyword: String?
        var openName: String?
        var openInner: [String] = []

        func kindFor(_ keyword: String) -> RequirementDiagram.Kind? {
            RequirementDiagram.Kind(rawValue: keyword)
        }

        func property(_ inner: [String], _ key: String) -> String? {
            for line in inner {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                if k == key {
                    let v = line[line.index(after: colon)...]
                        .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'."))
                    return v.isEmpty ? nil : v
                }
            }
            return nil
        }

        func finishBlock() {
            defer { openKeyword = nil; openName = nil; openInner = [] }
            guard let keyword = openKeyword, let name = openName else { return }
            if keyword == "element" {
                elements.append(RequirementDiagram.Element(
                    name: name,
                    type: property(openInner, "type"),
                    docRef: property(openInner, "docref")))
            } else if let kind = kindFor(keyword) {
                requirements.append(RequirementDiagram.Requirement(
                    name: name,
                    kind: kind,
                    id: property(openInner, "id"),
                    text: property(openInner, "text"),
                    risk: property(openInner, "risk"),
                    verifyMethod: property(openInner, "verifymethod")))
            }
        }

        /// Splits `header` (text before `{`) into (keyword, name).
        func headerTokens(_ header: String) -> (String, String)? {
            let toks = header.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard toks.count >= 2 else { return nil }
            return (toks[0], toks[1])
        }

        func parseRelation(_ line: String) -> RequirementDiagram.Relation? {
            func makeVerb(_ raw: String) -> RequirementDiagram.RelationKind? {
                let v = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t<>-"))
                    .lowercased()
                return RequirementDiagram.RelationKind(rawValue: v)
            }
            // Forward: src - verb -> dst
            if let arrow = line.range(of: "->") {
                let left = String(line[..<arrow.lowerBound])
                let dst = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard let dash = left.range(of: "-") else { return nil }
                let src = String(left[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
                guard let verb = makeVerb(String(left[dash.upperBound...])),
                      !src.isEmpty, !dst.isEmpty else { return nil }
                return RequirementDiagram.Relation(source: src, dest: dst, kind: verb)
            }
            // Reversed: dst <- verb - src
            if let arrow = line.range(of: "<-") {
                let dst = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(line[arrow.upperBound...])
                guard let dash = right.range(of: "-") else { return nil }
                let verb = makeVerb(String(right[..<dash.lowerBound]))
                let src = String(right[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard let verb, !src.isEmpty, !dst.isEmpty else { return nil }
                return RequirementDiagram.Relation(source: src, dest: dst, kind: verb)
            }
            return nil
        }

        for rawLine in body {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }

            if openKeyword != nil {
                // Inside a block: collect key:value lines until the closing brace.
                if let close = line.firstIndex(of: "}") {
                    let inner = line[..<close].trimmingCharacters(in: .whitespaces)
                    if !inner.isEmpty { openInner.append(inner) }
                    finishBlock()
                } else {
                    openInner.append(line)
                }
                continue
            }

            if let open = line.firstIndex(of: "{") {
                let header = line[..<open].trimmingCharacters(in: .whitespaces)
                guard let (keyword, name) = headerTokens(header) else { continue }
                openKeyword = keyword
                openName = name
                openInner = []
                // Content trailing the `{` on the header line, and a `}` on the
                // same line (single-line block), are both handled here.
                var tail = String(line[line.index(after: open)...])
                if let close = tail.firstIndex(of: "}") {
                    tail = String(tail[..<close])
                    let inner = tail.trimmingCharacters(in: .whitespaces)
                    if !inner.isEmpty { openInner.append(inner) }
                    finishBlock()
                } else {
                    let inner = tail.trimmingCharacters(in: .whitespaces)
                    if !inner.isEmpty { openInner.append(inner) }
                }
                continue
            }

            if let relation = parseRelation(line) {
                relations.append(relation)
            }
        }
        // A dangling unterminated block still contributes what it has.
        if openKeyword != nil { finishBlock() }

        guard !requirements.isEmpty || !elements.isEmpty else { return nil }
        return RequirementDiagram(requirements: requirements, elements: elements, relations: relations)
    }
}
