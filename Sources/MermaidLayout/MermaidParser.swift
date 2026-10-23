import Foundation

/// A parsed diagram: one case per supported Mermaid type (30 in all), each
/// carrying its typed model. Sources in any other dialect don't parse
/// (`MermaidParser.parse` returns nil) and the renderer keeps the
/// styled-source fallback.
public enum MermaidDiagram: Hashable, Sendable {
    case flowchart(Flowchart)
    case sequence(SequenceDiagram)
    case pie(PieChart)
    case classDiagram(ClassDiagram)
    case er(ERDiagram)
    case state(StateDiagram)
    case gantt(GanttChart)
    case timeline(Timeline)
    case mindmap(Mindmap)
    case journey(UserJourney)
    case quadrant(QuadrantChart)
    case packet(PacketDiagram)
    case xychart(XYChart)
    case kanban(KanbanBoard)
    case radar(RadarChart)
    case treemap(Treemap)
    case treeView(TreeViewDiagram)
    case venn(VennDiagram)
    case cynefin(CynefinDiagram)
    case wardley(WardleyMap)
    case ishikawa(IshikawaDiagram)
    case eventModeling(EventModelingDiagram)
    case swimlane(SwimlaneDiagram)
    case gitGraph(GitGraph)
    case sankey(SankeyDiagram)
    case requirement(RequirementDiagram)
    case zenuml(ZenUML)
    case c4(C4Diagram)
    case architecture(ArchitectureDiagram)
    case block(BlockDiagram)

    /// A human-readable name for the diagram's type ("flowchart",
    /// "sequence", …) — for accessibility labels, telemetry, and captions.
    public var typeName: String {
        switch self {
        case .flowchart: return "flowchart"
        case .sequence: return "sequence"
        case .pie: return "pie chart"
        case .classDiagram: return "class"
        case .er: return "entity relationship"
        case .state: return "state"
        case .gantt: return "gantt"
        case .timeline: return "timeline"
        case .mindmap: return "mind map"
        case .journey: return "user journey"
        case .quadrant: return "quadrant chart"
        case .packet: return "packet"
        case .xychart: return "xy chart"
        case .kanban: return "kanban"
        case .radar: return "radar chart"
        case .treemap: return "treemap"
        case .treeView: return "treeView"
        case .venn: return "venn"
        case .cynefin: return "cynefin"
        case .wardley: return "wardley"
        case .ishikawa: return "ishikawa"
        case .eventModeling: return "eventmodeling"
        case .swimlane: return "swimlane"
        case .gitGraph: return "git graph"
        case .sankey: return "sankey"
        case .requirement: return "requirement"
        case .zenuml: return "zenuml sequence"
        case .c4: return "C4"
        case .architecture: return "architecture"
        case .block: return "block"
        }
    }

    /// The diagram's title, when its dialect has one — used by the scene
    /// lowering so titles are visible to the geometry linter.
    public var titleText: String? {
        switch self {
        case .pie(let d): return d.title
        case .gantt(let d): return d.title
        case .timeline(let d): return d.title
        case .journey(let d): return d.title
        case .quadrant(let d): return d.title
        case .packet(let d): return d.title
        case .xychart(let d): return d.title
        case .radar(let d): return d.title
        case .wardley(let d): return d.title
        case .cynefin(let d): return d.title
        case .zenuml(let d): return d.title
        case .c4(let d): return d.title
        default: return nil
        }
    }
}

// MARK: - Parser

public enum MermaidParser {

    /// Parses a number that is safe to lay out. `Double.init` happily accepts
    /// "NaN"/"inf", and astronomically large finite values (1e308) overflow to
    /// infinity in span arithmetic — either poisons layout geometry and traps
    /// in Int conversions. Rejects non-finite input and clamps magnitude.
    static func finiteDouble(_ text: some StringProtocol) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return min(max(value, -1e12), 1e12)
    }

    /// Input bounds, mirroring mermaid.js's own defaults (`maxTextSize`,
    /// `maxEdges`). Oversized sources return nil FAST instead of feeding a
    /// quadratic layout for tens of seconds; hosts fall back to showing the
    /// fenced source.
    public static let maxTextSize = 50_000
    public static let maxEdges = 500

    /// Parses any of the 30 supported diagram types; nil for an unknown
    /// dialect, unparseable input, or a source past `maxTextSize`/`maxEdges`
    /// (the caller falls back to styled source).
    public static func parse(_ source: String) -> MermaidDiagram? {
        parseWithMetadata(source)?.diagram
    }

    /// Parses a diagram AND returns the front-matter/accessibility metadata the
    /// same pass extracted — so a caller that needs both (the render pipeline
    /// caption path) pays a single `stripMetadata` scan instead of parsing and
    /// then re-scanning the whole source with `metadata(in:)`. `parse` is this
    /// with the metadata discarded.
    public static func parseWithMetadata(
        _ source: String
    ) -> (diagram: MermaidDiagram, metadata: DiagramMetadata)? {
        guard source.count <= maxTextSize else { return nil }
        // YAML front-matter (`---\ntitle: ...\n---`) precedes the header in
        // doc examples; without stripping it, `---` became the header and
        // every config-bearing example fell back to styled source. The same
        // pass removes `accTitle:`/`accDescr:` statements so no dialect ever
        // sees them as content (they read back via the returned metadata).
        let (body, metadata) = stripMetadata(from: source)
        guard let diagram = parseBody(body) else { return nil }
        return (diagram, metadata)
    }

    /// Dispatches an already-metadata-stripped body to the per-dialect parsers.
    private static func parseBody(_ source: String) -> MermaidDiagram? {
        let lines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
        guard let header = lines.first else { return nil }

        if header.hasPrefix("graph") || header.hasPrefix("flowchart") {
            let statements = lines.flatMap(flowchartStatements)
            guard let first = statements.first else { return nil }
            return parseFlowchart(header: first, body: Array(statements.dropFirst()))
                .flatMap { $0.edges.count <= maxEdges ? .flowchart($0) : nil }
        }
        if header.hasPrefix("sequenceDiagram") {
            return parseSequence(body: Array(lines.dropFirst())).map { .sequence($0) }
        }
        if header.hasPrefix("pie") {
            return parsePie(header: header, body: Array(lines.dropFirst())).map { .pie($0) }
        }
        if header.hasPrefix("stateDiagram") {
            return parseState(body: Array(lines.dropFirst())).map { .state($0) }
        }
        if header.hasPrefix("classDiagram") {
            return parseClass(body: Array(lines.dropFirst())).map { .classDiagram($0) }
        }
        if header.hasPrefix("erDiagram") {
            return parseER(body: Array(lines.dropFirst())).map { .er($0) }
        }
        if header.hasPrefix("gantt") {
            return parseGantt(body: Array(lines.dropFirst())).map { .gantt($0) }
        }
        if header.hasPrefix("timeline") {
            return parseTimeline(body: Array(lines.dropFirst())).map { .timeline($0) }
        }
        if header.hasPrefix("mindmap") {
            // Indentation is significant, so re-read the raw (untrimmed) source.
            return parseMindmap(source: source).map { .mindmap($0) }
        }
        if header.hasPrefix("journey") {
            return parseJourney(body: Array(lines.dropFirst())).map { .journey($0) }
        }
        if header.hasPrefix("quadrantChart") {
            return parseQuadrant(body: Array(lines.dropFirst())).map { .quadrant($0) }
        }
        if header.hasPrefix("packet") {
            return parsePacket(body: Array(lines.dropFirst())).map { .packet($0) }
        }
        if header.hasPrefix("xychart") {
            return parseXYChart(body: Array(lines.dropFirst())).map { .xychart($0) }
        }
        if header.hasPrefix("kanban") {
            // Indentation is significant, so re-read the raw (untrimmed) source.
            return parseKanban(source: source).map { .kanban($0) }
        }
        if header.hasPrefix("radar") {
            return parseRadar(body: Array(lines.dropFirst())).map { .radar($0) }
        }
        if header.hasPrefix("treeView") {
            // Indentation is significant, so re-read the raw source.
            return parseTreeView(source: source).map { .treeView($0) }
        }
        if header.hasPrefix("venn") {
            return parseVenn(body: Array(lines.dropFirst())).map { .venn($0) }
        }
        if header.hasPrefix("cynefin") {
            return parseCynefin(body: Array(lines.dropFirst())).map { .cynefin($0) }
        }
        if header.hasPrefix("ishikawa") {
            // Indentation is significant, so re-read the raw source.
            return parseIshikawa(source: source).map { .ishikawa($0) }
        }
        if header.hasPrefix("eventmodeling") {
            return parseEventModeling(body: Array(lines.dropFirst())).map { .eventModeling($0) }
        }
        if header.hasPrefix("swimlane") {
            return parseSwimlane(header: header, body: Array(lines.dropFirst())).map { .swimlane($0) }
        }
        if header.hasPrefix("wardley") {
            return parseWardley(body: Array(lines.dropFirst())).map { .wardley($0) }
        }
        if header.hasPrefix("treemap") {
            // Indentation is significant, so re-read the raw (untrimmed) source.
            return parseTreemap(source: source).map { .treemap($0) }
        }
        if header.hasPrefix("gitGraph") {
            return parseGitGraph(body: Array(lines.dropFirst())).map { .gitGraph($0) }
        }
        if header.hasPrefix("sankey") {
            return parseSankey(body: Array(lines.dropFirst())).map { .sankey($0) }
        }
        if header.hasPrefix("requirementDiagram") {
            return parseRequirement(body: Array(lines.dropFirst())).map { .requirement($0) }
        }
        if header.hasPrefix("zenuml") {
            return parseZenUML(body: Array(lines.dropFirst())).map { .zenuml($0) }
        }
        if header.hasPrefix("C4") {
            return parseC4(body: Array(lines.dropFirst())).map { .c4($0) }
        }
        if header.hasPrefix("architecture") {
            return parseArchitecture(body: Array(lines.dropFirst())).map { .architecture($0) }
        }
        if header.hasPrefix("block-beta") {
            return parseBlock(body: Array(lines.dropFirst())).map { .block($0) }
        }
        return nil
    }

    // MARK: Flowchart

    /// A flowchart's statements: its lines, each split at every `;` that ends
    /// a statement (`graph LR; A --> B; B --> C`), as mermaid allows.
    ///
    /// A `;` ends a statement exactly where mermaid's lexer reads it as one:
    /// not inside a string (`"…"`), a node's text (`[…]`, `(…)`, `{…}`,
    /// `>…]`), a pipe label (`|…|`) or a link's inline text (`-- … -->`,
    /// `== … ==>`, `-. … .->`), and not ending an entity (`#quot;`, `#35;`).
    /// In `style`, `classDef` and `linkStyle` statements a `;` always ends
    /// one, so `fill:#f96;` is a color, not an entity. A `%%` comment at a
    /// statement's start runs to the end of the line, as it does on a line
    /// of its own.
    static func flowchartStatements(_ line: String) -> [String] {
        lexFlowchart(line, splitting: true).map(\.text)
    }

    /// `statement` with each label's contents (strings, node text, pipe
    /// labels, inline link text) replaced by `masked`, character for
    /// character but for spaces and tabs: what's left is the statement's
    /// syntax, so a search for a
    /// link or an `&` can't find one inside a label. The same lexer as
    /// `flowchartStatements`, so the two can't disagree on where a label is.
    static func flowchartSyntax(_ statement: String) -> [Character] {
        Array(lexFlowchart(statement, splitting: false).first?.masked ?? "")
    }

    /// What a label's character reads as in `flowchartSyntax`: no syntax.
    static let masked: Character = "\u{1}"

    private static func lexFlowchart(_ line: String, splitting: Bool) -> [(text: String, masked: String)] {
        /// A node's text, as mermaid's lexer reads it: it ends at the first of
        /// its shape's closers (`]]` for `[[`, `)]` for `[(`, `/]` or `\]`
        /// for `[/`…, from `shapeDelimiters`), with no nesting — `(`, `)` or
        /// another `[` inside `[…]` is text.
        struct Shape { let closers: [[Character]] }
        enum Mode {
            case statement
            case string(returnTo: Shape?)       // the node text to resume, if any
            case shape(Shape)                   // inside […], (…), {…}, >…]
            case pipe                           // inside |…|
            case linkText(closer: Character)    // after `--`, `==` or `-.`
        }
        let chars = Array(line)
        var statements: [(text: String, masked: String)] = []
        var current = ""
        // `current` with each label character masked.
        var syntax = ""
        var mode = Mode.statement
        /// Appends written syntax (`visible`) or label text to both.
        func take(_ text: some StringProtocol, visible: Bool) {
            current += text
            syntax += visible ? String(text) : String(text.map { $0 == " " || $0 == "\t" ? $0 : masked })
        }
        var blank = true    // `current` is only whitespace so far
        // Whether `current` is a style/classDef/linkStyle statement, once
        // asked: by then it holds a `#word`, so its first word is settled.
        var styled: Bool?
        var i = 0
        /// The shape whose opener starts at `at` (the longest that matches),
        /// and the opener's length.
        func shape(at: Int) -> (Shape, Int)? {
            func starts(_ s: [Character], _ at: Int) -> Bool {
                at + s.count <= chars.count && Array(chars[at..<at + s.count]) == s
            }
            let opens = shapeDelimiters.map { Array($0.open) }.filter { $0 != [">"] && starts($0, at) }
            guard let open = opens.max(by: { $0.count < $1.count }) else { return nil }
            let closers = shapeDelimiters.filter { Array($0.open) == open }.map { Array($0.close) }
            return (Shape(closers: closers), open.count)
        }
        func closes(_ shape: Shape, at: Int) -> Int? {
            shape.closers.first { at + $0.count <= chars.count && Array(chars[at..<at + $0.count]) == $0 }?.count
        }

        /// Whether `chars[at...]` is a whole link made of `c` — mermaid's
        /// `--+[-xo>]` / `==+[=xo>]`: three or more (`---`, `====`), or two or
        /// more then a head (`-->`, `--x`, `==o`).
        func link(at: Int, _ c: Character) -> Bool {
            var j = at
            while j < chars.count, chars[j] == c { j += 1 }
            let heads: Set<Character> = [">", "x", "o"]
            return j - at >= 3 || (j - at >= 2 && j < chars.count && heads.contains(chars[j]))
        }
        func styling(_ text: String) -> Bool {
            let t = text.drop(while: { $0 == " " || $0 == "\t" })
            return ["style", "classDef", "linkStyle"].contains { startsWithKeyword(t, $0) }
        }

        while i < chars.count {
            let c = chars[i]
            // Whether `c` is read inside a label (decided before it can
            // change the mode, so an opening `|` or `"` is syntax).
            let inLabel: Bool
            if case .statement = mode { inLabel = false } else { inLabel = true }
            switch mode {
            case .string(let shape):
                if c == "\"" {
                    // A top-level string's closing quote is syntax again.
                    mode = shape.map { .shape($0) } ?? .statement
                    take(String(c), visible: shape == nil)
                    i += 1
                    continue
                }
            case .shape(let shape):
                if c == "\"" {
                    mode = .string(returnTo: shape)
                } else if let length = closes(shape, at: i) {
                    take(String(chars[i..<i + length]), visible: true)
                    i += length
                    mode = .statement
                    continue
                }
            case .pipe:
                if c == "|" {
                    mode = .statement
                    take("|", visible: true)
                    i += 1
                    continue
                }
            case .linkText(let closer):
                // Ends at the link that closes it: `-->`/`---`/`--x`/`--o`,
                // `==>`/`===`…, or `.->`/`.-`. The whole link is taken, so
                // its tail can't reopen text.
                var end = i
                if closer == c, c == "-" || c == "=", link(at: i, c) {
                    while end < chars.count, chars[end] == c { end += 1 }
                } else if closer == ".", c == "." {
                    var j = i
                    while j < chars.count, chars[j] == "." { j += 1 }
                    if j < chars.count, chars[j] == "-" {
                        end = j + 1
                    } else {
                        // The run can't close the text; take it whole so no
                        // later dot in it rescans it (linear, not quadratic).
                        take(String(chars[i..<j]), visible: false)
                        i = j
                        continue
                    }
                }
                if end > i {
                    take(String(chars[i..<end]), visible: true)
                    i = end
                    mode = .statement
                    continue
                }
            case .statement:
                if blank, c == "%", i + 1 < chars.count, chars[i + 1] == "%" {
                    i = chars.count     // a comment: the rest of the line
                    current = ""
                    syntax = ""
                    continue
                }
                switch c {
                case ";":
                    // Mermaid encodes every `#word;` as an entity before it lexes.
                    let word = current.reversed().prefix(while: isWordCharacter).count
                    let entity = word > 0 && current.dropLast(word).last == "#" && !{
                        if styled == nil { styled = styling(current) }
                        return styled!
                    }()
                    if splitting, !entity {
                        statements.append((current, syntax))
                        current = ""
                        syntax = ""
                        blank = true
                        styled = nil
                        i += 1
                        continue
                    }
                case "\"": mode = .string(returnTo: nil)
                case "[", "(", "{":
                    if let (shape, length) = shape(at: i) {
                        take(String(chars[i..<i + length]), visible: true)
                        blank = false
                        i += length
                        mode = .shape(shape)
                        continue
                    }
                case ">":
                    // `A>flag]` (asymmetric) — not a link's arrowhead.
                    if let prev = current.last, isIDCharacter(prev) {
                        mode = .shape(Shape(closers: [["]"]]))
                    }
                case "|": mode = .pipe
                case "-", "=":
                    let next = i + 1 < chars.count ? chars[i + 1] : " "
                    if next == c {
                        // `--` or `==` opens inline text unless it's already a
                        // whole link (`-->`, `---`, `--x`, `==>`…), as in
                        // mermaid's lexer.
                        if !link(at: i, c) {
                            take(String(chars[i...i + 1]), visible: true)
                            blank = false
                            i += 2
                            mode = .linkText(closer: c)
                            continue
                        }
                        // Skip the whole link so its tail can't reopen text.
                        while i < chars.count, chars[i] == c { take(String(chars[i]), visible: true); i += 1 }
                        blank = false
                        continue
                    }
                    if c == "-", next == "." {
                        let after = i + 2 < chars.count ? chars[i + 2] : " "
                        if after != "." && after != "-" {
                            take("-.", visible: true)
                            blank = false
                            i += 2
                            mode = .linkText(closer: ".")
                            continue
                        }
                    }
                default: break
                }
            }
            take(String(c), visible: !inLabel)
            if c != " " && c != "\t" { blank = false }
            i += 1
        }
        statements.append((current, syntax))
        // Trimmed alike: the syntax keeps the text's whitespace at each end.
        return statements.compactMap { statement in
            let text = Array(statement.text), syntax = Array(statement.masked)
            let blank: (Character) -> Bool = { $0.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains) }
            let lead = text.prefix(while: blank).count
            let trail = text.dropFirst(lead).reversed().prefix(while: blank).count
            guard lead < text.count else { return nil }
            return (String(text[lead..<(text.count - trail)]), String(syntax[lead..<(syntax.count - trail)]))
        }
    }

    /// A character a node id is made of (Unicode letters included).
    static func isIDCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    /// A character of mermaid's `\w`: an ASCII letter or digit, or `_`.
    private static func isWordCharacter(_ c: Character) -> Bool {
        c == "_" || (c.isASCII && (c.isLetter || c.isNumber))
    }

    /// Whether `line` opens with `keyword` as a whole word (`style A …`, not
    /// `styleguide --> B`): mermaid reads a keyword only before whitespace.
    static func startsWithKeyword(_ line: some StringProtocol, _ keyword: String) -> Bool {
        guard line.hasPrefix(keyword) else { return false }
        let next = line.dropFirst(keyword.count).first
        return next == nil || next == " " || next == "\t"
    }

    /// Label text as mermaid shows it, read in one scan of the text as
    /// written: character references decoded as a browser reads them
    /// (`#quot;`, `#35;`, `&amp;`, `&copy`, `&#x2665;`; see `reference`), and
    /// inline formatting tags (`<b>`, `<i>`, `<code>`, `<span …>`, …) dropped
    /// for their text, which the renderers can't style. `<br>` line breaks
    /// stay; other angle brackets (`p<0.05`, `List<String>`) are text. Each
    /// tag and reference is read where it's written, so dropping a tag never
    /// joins a reference either (`&am<b></b>p;` shows as written).
    ///
    /// Reading never spells a line break the text doesn't have as written
    /// (layout reads `<br…>` and `\n` as breaks; a reference to a line
    /// separator, `&#8232;`, is one as written). Each
    /// character a break is made of is written: a `<br…>` tag's `<`, `b` and
    /// `r`, side by side, and its closing `>`; both halves of `\n`, side by
    /// side. Otherwise the reference that supplied one, or the tag dropped
    /// between two, stays as written: `&lt;br&gt;`, `<b&#114;>`, `#92;n` and
    /// `\<i>n` show as written instead of breaking the label. Linear: each
    /// tag and reference is read once, and a `<br` costs the same however long
    /// the label.
    static func labelText(_ raw: String) -> String {
        guard raw.contains("#") || raw.contains("&") || raw.contains("<") else { return raw }
        let s = Array(raw.unicodeScalars)
        // Each tag and reference, and what it reads as (a tag, nothing).
        var spans: [(range: Range<Int>, text: [Unicode.Scalar])] = []
        var i = 0
        while i < s.count {
            if s[i] == "<", let end = formattingTag(at: i, in: s) {
                spans.append((i..<end, []))
                i = end
            } else if let (end, text) = reference(at: i, in: s) {
                spans.append((i..<end, text))
                i = end
            } else {
                i += 1
            }
        }
        guard !spans.isEmpty else { return raw }
        // The text as read; which span supplied each character (-1: the text
        // as written); and the spans that read as nothing just before each.
        var plain: [Unicode.Scalar] = []
        var from: [Int] = []
        var dropped: [Int: [Int]] = [:]
        plain.reserveCapacity(s.count)
        from.reserveCapacity(s.count)
        var cursor = 0
        for (k, span) in spans.enumerated() {
            plain += s[cursor..<span.range.lowerBound]
            from += repeatElement(-1, count: span.range.lowerBound - cursor)
            if span.text.isEmpty { dropped[plain.count, default: []].append(k) }
            plain += span.text
            from += repeatElement(k, count: span.text.count)
            cursor = span.range.upperBound
        }
        plain += s[cursor...]
        from += repeatElement(-1, count: s.count - cursor)
        // Spans to keep as written. A reference's written form has no `<`,
        // `>` or `\`, and a tag's can't open a `<br` or end in `\`, so keeping
        // one never makes a break either.
        var kept = Set<Int>()
        func written(_ i: Int) -> Bool { from[i] < 0 }
        /// Written, and written right after the character before it.
        func writtenBeside(_ i: Int) -> Bool { written(i) && dropped[i] == nil }
        /// Keeps the span that supplied `i`, and those dropped just before it.
        func keep(_ i: Int, andBefore: Bool = true) {
            if from[i] >= 0 { kept.insert(from[i]) }
            if andBefore { kept.formUnion(dropped[i] ?? []) }
        }
        let lastClose = plain.lastIndex(of: ">") ?? -1
        var openWritten = -1, closeWritten = -1
        for i in plain.indices {
            switch plain[i] {
            case "<" where opensBreakTag(plain, at: i):
                if written(i), writtenBeside(i + 1), writtenBeside(i + 2) {
                    openWritten = i
                } else if lastClose > i {
                    keep(i, andBefore: false); keep(i + 1); keep(i + 2)
                }
            case ">":
                // A decoded `>` would close a written `<br…` early, or at all.
                if written(i) { closeWritten = i } else if openWritten > closeWritten { keep(i) }
            case "\\" where i + 1 < plain.count && plain[i + 1] == "n" && !(written(i) && writtenBeside(i + 1)):
                keep(i, andBefore: false); keep(i + 1)
            default:
                break
            }
        }
        var out = String.UnicodeScalarView()
        cursor = 0
        for (k, span) in spans.enumerated() {
            out.append(contentsOf: s[cursor..<span.range.lowerBound])
            out.append(contentsOf: kept.contains(k) ? Array(s[span.range]) : span.text)
            cursor = span.range.upperBound
        }
        out.append(contentsOf: s[cursor...])
        return String(out)
    }

    /// Inline formatting tags the renderers can't style, dropped for their
    /// text.
    private static let formattingTags: Set<String> = [
        "b", "i", "u", "s", "em", "strong", "code", "kbd", "mark", "small", "big", "sub", "sup", "strike",
        "del", "ins", "span", "font", "a", "p", "div", "tt", "q", "cite",
    ]

    /// Where a formatting tag (`<b>`, `</i>`, `<span …>`, `<b/>`) opening at
    /// `i` ends, or nil: `</?name(\s[^<>]*)?/?>`, any case.
    /// Linear: attributes are read no further than the next `<`.
    private static func formattingTag(at i: Int, in s: [Unicode.Scalar]) -> Int? {
        var j = i + 1
        if j < s.count, s[j] == "/" { j += 1 }
        let name = j
        while j < s.count, ("a"..."z").contains(s[j]) || ("A"..."Z").contains(s[j]) { j += 1 }
        guard j < s.count, formattingTags.contains(String(String.UnicodeScalarView(s[name..<j])).lowercased()) else {
            return nil
        }
        if s[j].properties.isWhitespace {
            while j < s.count, s[j] != "<", s[j] != ">" { j += 1 }
        } else if s[j] == "/" {
            j += 1
        }
        return j < s.count && s[j] == ">" ? j + 1 : nil
    }

    /// The character reference at `i`, as mermaid's text reaches its reader:
    /// where it ends, and what it reads as. Mermaid first makes its own
    /// `#name;` and `#123;` (any `#word;`) `&name;` and `&#123;`; then the
    /// browser reads every reference by HTML's algorithm over the full table
    /// (`htmlEntities`): the longest name that matches wins (`&notit;` is
    /// "¬it;"), a legacy name needs no `;` (`&amp`, `&copy`), and neither
    /// does a numeric reference. `&#123;` is one reference, as its author
    /// meant (mermaid's rewrite strands the `&`). A reference to something
    /// that isn't a printable character reads as written, whole; an unknown `&name;` isn't a reference (nil); an unknown `#name;`
    /// reads `&name;`, as mermaid shows it. Linear: a name is at most `htmlEntityMaxLength`
    /// long, and a run of digits or of `#word` is read once.
    private static func reference(at i: Int, in s: [Unicode.Scalar]) -> (end: Int, text: [Unicode.Scalar])? {
        func isAlphanumeric(_ c: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c)
        }
        /// The longest name in the table starting at `k`, read no further
        /// than `limit`: its text and where it ends.
        func named(at k: Int, limit: Int) -> (String, Int)? {
            var run = k
            while run < min(limit, s.count), run - k < htmlEntityMaxLength, isAlphanumeric(s[run]) { run += 1 }
            func name(_ end: Int) -> String { String(String.UnicodeScalarView(s[k..<end])) }
            if run < min(limit, s.count), s[run] == ";", let text = htmlEntities[name(run) + ";"] {
                return (text, run + 1)
            }
            for end in stride(from: run, to: k, by: -1) {
                if let text = htmlEntities[name(end)] { return (text, end) }
            }
            return nil
        }
        /// A numeric reference's digits from `k` (after `&#`), hex after an
        /// `x`; the `;` is optional. Nil without digits.
        func numeric(at k: Int) -> (UInt32, Int)? {
            var j = k
            let hex = j < s.count && (s[j] == "x" || s[j] == "X")
            if hex { j += 1 }
            let digits = j
            var value: UInt32 = 0
            while j < s.count, let d = hex ? hexValue(s[j]) : decimalValue(s[j]) {
                value = min(value * (hex ? 16 : 10) + d, 0x110000)
                j += 1
            }
            guard j > digits else { return nil }
            if j < s.count, s[j] == ";" { j += 1 }
            return (value, j)
        }
        // Where the reference ends, and what it reads as (nil: as written).
        var end: Int?
        var text: String?
        if s[i] == "&", i + 1 < s.count {
            if s[i + 1] == "#", let (value, after) = numeric(at: i + 2) {
                (text, end) = (referenced(value), after)
            } else if isAlphanumeric(s[i + 1]), let (name, after) = named(at: i + 1, limit: s.count) {
                (text, end) = (name, after)
            }
        } else if s[i] == "#" {
            var j = i + 1
            while j < s.count, isAlphanumeric(s[j]) || s[j] == "_" { j += 1 }
            guard j > i + 1, j < s.count, s[j] == ";" else { return nil }
            if s[(i + 1)..<j].allSatisfy({ ("0"..."9").contains($0) }) {
                (text, end) = (numeric(at: i + 1).flatMap { referenced($0.0) }, j + 1)
            } else if let (name, after) = named(at: i + 1, limit: j + 1) {
                (text, end) = (name, after)
            } else {
                (text, end) = ("&" + String(String.UnicodeScalarView(s[(i + 1)...j])), j + 1)
            }
        }
        guard let end else { return nil }
        // A control character stays as written: it can't be drawn. (A line
        // or paragraph separator, `&#8232;`, is the author's line break.)
        if let text, !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return (end, Array(text.unicodeScalars))
        }
        return (end, Array(s[i..<end]))
    }

    /// Whether `text` opens a `<br…>` tag at `i`, as layout reads one (`<br`
    /// at a word boundary): the same `<br\b[^>]*>` as
    /// `DiagramLayoutEngine.brLines`, asked of the four characters that decide
    /// it, so it costs the same however long the text. (The closing `>` is
    /// `labelText`'s to check.)
    private static func opensBreakTag(_ text: [Unicode.Scalar], at i: Int) -> Bool {
        guard i + 3 < text.count, text[i + 1] == "b" || text[i + 1] == "B", text[i + 2] == "r" || text[i + 2] == "R",
              let breakTag else { return false }
        let probe = "<br" + String(Character(text[i + 3])) + ">"
        return breakTag.firstMatch(in: probe, range: NSRange(location: 0, length: (probe as NSString).length)) != nil
    }

    private static func decimalValue(_ c: Unicode.Scalar) -> UInt32? {
        ("0"..."9").contains(c) ? c.value - 48 : nil
    }

    private static func hexValue(_ c: Unicode.Scalar) -> UInt32? {
        if let d = decimalValue(c) { return d }
        if ("a"..."f").contains(c) { return c.value - 87 }
        if ("A"..."F").contains(c) { return c.value - 55 }
        return nil
    }

    private static let breakTag = try? NSRegularExpression(pattern: #"<br\b[^>]*>"#, options: .caseInsensitive)

    /// The character a numeric reference names, as a browser reads it:
    /// 0x80–0x9F as Windows-1252 (`#133;` is "…"), and nothing for a control
    /// character, a noncharacter (U+FFFE, U+FDD0…) or a value that isn't a
    /// Unicode scalar — none of those can be drawn, and SVG can't hold them.
    private static func referenced(_ value: UInt32) -> String? {
        if (0x80...0x9F).contains(value) { return windows1252[Int(value - 0x80)] }
        guard value >= 0x20, value != 0x7F, value & 0xFFFE != 0xFFFE, !(0xFDD0...0xFDEF).contains(value),
              let scalar = Unicode.Scalar(value) else { return nil }
        return String(scalar)
    }

    /// Windows-1252's 0x80–0x9F, which HTML reads numeric references in that
    /// range as; its five gaps are C1 controls and stay unread.
    private static let windows1252: [String?] = [
        "€", nil, "‚", "ƒ", "„", "…", "†", "‡", "ˆ", "‰", "Š", "‹", "Œ", nil, "Ž", nil,
        nil, "‘", "’", "“", "”", "•", "–", "—", "˜", "™", "š", "›", "œ", nil, "ž", "Ÿ",
    ]

    /// Parses a flowchart's header and body statements. `setAside` hears about
    /// each statement it couldn't use — by body index, or -1 for the header —
    /// and why; styling it ignores on purpose (`classDef`, `style`, `click`…)
    /// isn't reported.
    static func parseFlowchart(header: String, body: [String],
                               setAside report: (_ index: Int, _ reason: String) -> Void = { _, _ in }) -> Flowchart? {
        // Statements left out of the chart; a note that loses nothing (a
        // top-level `direction`) doesn't count.
        var setAsideCount = 0
        func setAside(_ index: Int, _ reason: String, losing: Bool = true) {
            if losing { setAsideCount += 1 }
            report(index, reason)
        }
        let parts = header.split(whereSeparator: \.isWhitespace)
        // The header mermaid reads: a keyword, then at most a direction.
        if let keyword = parts.first, !["graph", "flowchart", "flowchart-elk"].contains(String(keyword)) {
            setAside(-1, "unknown header '\(keyword)'; read as a flowchart")
        }
        if parts.count > 2 {
            setAside(-1, "'\(parts.dropFirst(2).joined(separator: " "))' after the direction; ignored")
        }
        var direction = Flowchart.Direction.topDown
        if parts.count > 1 {
            let token = normalizedDirectionToken(parts[1])
            if let parsed = Flowchart.Direction(rawValue: token) {
                direction = parsed
            } else {
                setAside(-1, "unknown direction '\(parts[1])'; laid out top-down")
            }
        }

        var nodes: [String: Flowchart.Node] = [:]
        var order: [String] = []
        var edges: [Flowchart.Edge] = []

        // Subgraph nesting: a stack of open subgraph ids, plus the accumulated
        // definitions. Membership is recorded when a node is FIRST noted while
        // a subgraph is open, so a node belongs to the innermost block it
        // appears in — matching mermaid.
        var subgraphs: [String: Flowchart.Subgraph] = [:]
        var subgraphOrder: [String] = []
        var stack: [String] = []
        var membership: [String: String] = [:]
        var anonCount = 0
        // Subgraphs a later block reopened: their first direction stands.
        var reopened: Set<String> = []
        // Every id a header names, so a synthesized one never takes it.
        let namedSubgraphs = Set(body.compactMap { startsWithKeyword($0, "subgraph") ? subgraphHeader($0).id : nil })
        /// Whether `id` contains `other`, at any depth.
        func isAncestor(_ id: String, of other: String) -> Bool {
            var seen: Set<String> = [], frontier = subgraphs[id]?.childIDs ?? []
            while let next = frontier.popLast() {
                if next == other { return true }
                if seen.insert(next).inserted { frontier += subgraphs[next]?.childIDs ?? [] }
            }
            return false
        }

        func note(_ node: Flowchart.Node) {
            if let existing = nodes[node.id] {
                // A later declaration with an explicit label wins over a bare id.
                if node.label != node.id || existing.label == existing.id {
                    if node.label != node.id { nodes[node.id] = node }
                }
            } else {
                nodes[node.id] = node
                order.append(node.id)
            }
            // Membership: the first subgraph block a node textually appears in
            // claims it (an inside reference wins over an earlier outside one;
            // an inner block wins over its outer). Nodes only ever seen at the
            // top level stay unclaimed.
            if let top = stack.last, subgraphs[top] != nil, membership[node.id] == nil {
                membership[node.id] = top
                subgraphs[top]!.nodeIDs.append(node.id)
            }
        }

        for (index, line) in body.enumerated() {
            if startsWithKeyword(line, "subgraph") {
                let known = subgraphOrder.count
                let id = openSubgraph(line, into: &subgraphs, order: &subgraphOrder,
                                      stack: stack, reserved: namedSubgraphs, anonCount: &anonCount)
                let reopening = subgraphOrder.count == known
                if reopening { reopened.insert(id) }
                // A subgraph has one parent, its first: a reopened block never
                // re-parents it (that could nest it inside its own descendant,
                // a cycle layout would recurse on forever).
                if let parent = stack.last, subgraphs[parent] != nil,
                   !reopening || !subgraphs.values.contains(where: { $0.childIDs.contains(id) }) && !isAncestor(id, of: parent) {
                    subgraphs[parent]!.childIDs.append(id)
                }
                stack.append(id)
                continue
            }
            if line == "end" {
                if stack.isEmpty { setAside(index, "'end' with no subgraph open") } else { stack.removeLast() }
                continue
            }
            // `direction` and one word, as mermaid lexes it; `direction --> B`
            // is an edge from a node named `direction`.
            if startsWithKeyword(line, "direction"),
               line.dropFirst("direction".count).trimmingCharacters(in: .whitespaces).allSatisfy(\.isLetter),
               line.count > "direction ".count {
                // Scoped to the innermost open subgraph. A top-level direction
                // line is dropped, as mermaid drops it (the header sets the
                // chart's flow); either way it never leaks in as a phantom node.
                let token = line.dropFirst("direction".count)
                let parsed = Flowchart.Direction(rawValue: normalizedDirectionToken(token))
                let written = token.trimmingCharacters(in: .whitespaces)
                if parsed == nil {
                    setAside(index, "unknown direction '\(written)'")
                }
                if let top = stack.last, subgraphs[top] != nil {
                    if !reopened.contains(top) || subgraphs[top]!.direction == nil { subgraphs[top]!.direction = parsed }
                } else if parsed != nil {
                    setAside(index, "'direction \(written)' outside a subgraph has no effect; the header sets the flow",
                             losing: false)
                }
                continue
            }
            // Styling, ignored on purpose: the theme draws every node alike.
            // A `linkStyle` index must name a link read before it (mermaid
            // rejects the chart otherwise).
            if startsWithKeyword(line, "linkStyle") {
                let target = line.dropFirst("linkStyle".count).split(whereSeparator: \.isWhitespace).first ?? ""
                /// A link read before this statement, by its index.
                func names(_ index: Substring) -> Bool {
                    !index.isEmpty && index.allSatisfy { ("0"..."9").contains($0) } && (Int(index).map { $0 < edges.count } ?? false)
                }
                if target != "default",
                   let missing = target.split(separator: ",", omittingEmptySubsequences: false).first(where: { !names($0) }) {
                    setAside(index, "linkStyle '\(missing)' names no link (\(edges.count) read before it); ignored")
                }
                continue
            }
            // `style X …` names a node, as in mermaid, which draws it even if
            // nothing else does (but not as a member of an open subgraph).
            if startsWithKeyword(line, "style") {
                let target = line.dropFirst("style".count).split(whereSeparator: \.isWhitespace).first ?? ""
                if let node = parseNodeToken(target), node.label == node.id, nodes[node.id] == nil {
                    nodes[node.id] = node
                    order.append(node.id)
                }
                continue
            }
            if ["classDef", "class", "click"].contains(where: { startsWithKeyword(line, $0) }) {
                continue
            }

            // Split on links (`-->`, `---`, `-.->`, `==>`, `~~~`, `--o`, …),
            // keeping what each draws and its optional |label|.
            var unread: [Substring] = []
            if let parsed = parseEdgeLine(line, unread: &unread), !parsed.isEmpty {
                for token in unread {
                    let text = token.trimmingCharacters(in: .whitespaces)
                    setAside(index, text.isEmpty ? "an empty '&' endpoint; left out of the diagram"
                        : "couldn't read '\(text.count > 60 ? text.prefix(57) + "…" : text)' in an '&' fan; left out of the diagram")
                }
                for edge in parsed {
                    note(edge.fromNode)
                    note(edge.toNode)
                    edges.append(edge.edge)
                }
                continue
            }

            // Standalone node declaration.
            if let node = parseNodeToken(Substring(line)) {
                note(node)
            } else {
                setAside(index, "couldn't read '\(line.count > 60 ? line.prefix(57) + "…" : line)'; left out of the diagram")
            }
        }

        // An edge endpoint naming a subgraph id minted a phantom node above;
        // drop those — the layout resolves the id to the group's box. Also
        // scrub them from any membership list they slipped into.
        let subgraphIDs = Set(subgraphOrder)
        for id in subgraphIDs {
            nodes.removeValue(forKey: id)
            order.removeAll { $0 == id }
        }
        for key in subgraphs.keys {
            subgraphs[key]!.nodeIDs.removeAll { subgraphIDs.contains($0) }
        }

        // A chart with nothing to draw is an empty chart, as in mermaid; one
        // that drew nothing because it couldn't read a statement isn't. A
        // subgraph's box is something drawn, as a node is.
        guard !nodes.isEmpty || !subgraphOrder.isEmpty || setAsideCount == 0 else { return nil }
        return Flowchart(
            direction: direction,
            nodes: order.compactMap { nodes[$0] },
            edges: edges,
            subgraphs: subgraphOrder.compactMap { subgraphs[$0] }
        )
    }

    /// Normalizes a `direction` token (`TB` is mermaid's alias for `TD`).
    private static func normalizedDirectionToken(_ raw: Substring) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return t == "TB" ? "TD" : t
    }

    /// A `subgraph …` header's id and title: `subgraph id[Title]`,
    /// `subgraph id`, `subgraph "Title"` (brackets inside the quotes are part
    /// of the title) or a bare `subgraph`. Without
    /// brackets the title is the id too, unless it has whitespace (as in
    /// mermaid), so two `subgraph My Group` blocks are two boxes. A nil id is
    /// one to synthesize.
    private static func subgraphHeader(_ line: String) -> (id: String?, label: String) {
        func titleID(_ title: String) -> String? {
            title.isEmpty || title.contains(where: \.isWhitespace) ? nil : title
        }
        let rest = String(line.dropFirst("subgraph".count)).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return (nil, "") }
        // One quoted string is a title, brackets and all.
        if rest.count > 1, rest.hasPrefix("\""), rest.hasSuffix("\""), !rest.dropFirst().dropLast().contains("\"") {
            let label = String(rest.dropFirst().dropLast())
            return (titleID(label), label)
        }
        if let open = rest.firstIndex(of: "["), let close = rest.lastIndex(of: "]"), open < close {
            let id = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
            let label = String(rest[rest.index(after: open)..<close])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            return (id.isEmpty ? nil : id, label)
        }
        if rest.hasPrefix("\"") {
            let label = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (titleID(label), label)
        }
        return (titleID(rest), rest)
    }

    /// Opens the subgraph a `subgraph …` header names (see `subgraphHeader`):
    /// a new definition, registered, or a closed one reopened.
    private static func openSubgraph(
        _ line: String,
        into subgraphs: inout [String: Flowchart.Subgraph],
        order: inout [String],
        stack: [String],
        reserved: Set<String>,
        anonCount: inout Int
    ) -> String {
        /// A synthesized id (`§sub0`, `§sub1`, …) no subgraph has, and no
        /// header in the chart names (`reserved`), whatever the order.
        func fresh() -> String {
            while subgraphs["\u{a7}sub\(anonCount)"] != nil || reserved.contains("\u{a7}sub\(anonCount)") { anonCount += 1 }
            defer { anonCount += 1 }
            return "\u{a7}sub\(anonCount)"
        }
        let header = subgraphHeader(line)
        var id = header.id ?? fresh()
        let label = header.label
        // A closed subgraph's id, used again, reopens it, as in mermaid: its
        // first title and direction stand and the block adds members. Only a
        // named id can (a synthesized one is always new); one still open (a
        // subgraph inside itself) gets a fresh id instead.
        if subgraphs[id] != nil {
            if !stack.contains(id) { return id }
            id = fresh()
        }
        subgraphs[id] = Flowchart.Subgraph(id: id, label: labelText(label))
        order.append(id)
        return id
    }

    private struct ParsedEdge {
        let fromNode: Flowchart.Node
        let toNode: Flowchart.Node
        let edge: Flowchart.Edge
    }

    /// Moves inline link text onto the `|text|` form so one scanner reads
    /// every link (`-- text -->` becomes `-->|text|`, `<-. text .-o` becomes
    /// `<-.-o|text|`), and drops edge IDs (`e1@-->`), which are animation
    /// targets.
    private static func normalizeEdgeSyntax(_ line: Written) -> Written {
        var line = line
        for (pattern, template) in edgeRewrites {
            guard let pattern else { continue }
            var text: [Character] = [], syntax: [Character] = []
            var cursor = 0
            for groups in Searchable(line.syntax).matches(of: pattern) {
                guard let whole = groups[0] else { continue }
                text += line.text[cursor..<whole.lowerBound]
                syntax += line.syntax[cursor..<whole.lowerBound]
                for piece in template {
                    switch piece {
                    case .literal(let c): text.append(c); syntax.append(c)
                    case .group(let n):
                        if let range = groups[n] { text += line.text[range]; syntax += line.syntax[range] }
                    }
                }
                cursor = whole.upperBound
            }
            text += line.text[cursor...]
            syntax += line.syntax[cursor...]
            line = Written(text: text, syntax: syntax)
        }
        return line
    }

    private enum TemplatePiece { case literal(Character), group(Int) }

    /// `normalizeEdgeSyntax`'s rewrites, matched against a statement's
    /// syntax, so inline text can hold anything but a link (`-- a-b -->`).
    private static let edgeRewrites: [(NSRegularExpression?, [TemplatePiece])] = {
        // A start head: `<`, or an `o`/`x` that isn't the end of an id. The
        // opener can't begin inside a longer link, or `A --- B --- C` would
        // read from the first `---`'s second dash as `-- B ---`.
        let start = #"((?<![^\s])[ox]|<)?(?<![-=.~])"#
        // An `o`/`x` end head is followed by a space, `|` or the line's end.
        let head = #"[ox](?=[\s|]|$)"#
        let moved: [TemplatePiece] = [.group(1), .group(3), .literal("|"), .group(2), .literal("|")]
        return [
            // An edge id only right before a link, so `ops@xmail` in a label stays.
            (#"\s\w+@(?=[ox<]?(?:--|==|-\.|~~~))"#, [.literal(" ")]),                          // edge IDs
            (start + #"--\s+([^-|>][^-]*?)\s+(-{2,}>|-{2,}\#(head)|-{3,})"#, moved),              // -- text -->
            (start + #"-\.\s+([^.|]+?)\s+(\.+->|\.+-\#(head)|\.+-)"#,
             [.group(1), .literal("-"), .group(3), .literal("|"), .group(2), .literal("|")]),     // -. text .->
            (start + #"==\s+([^=|>][^=]*?)\s+(={2,}>|={2,}\#(head)|={3,})"#, moved),              // == text ==>
        ].map { (try? NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    /// A statement as written, and its syntax (`flowchartSyntax`), character
    /// for character: searches read the syntax, and what they find is cut
    /// from the text.
    private struct Written {
        var text: [Character]
        var syntax: [Character]

        init(text: [Character], syntax: [Character]) {
            self.text = text
            self.syntax = syntax
        }

        init(_ statement: String) {
            text = Array(statement.trimmingCharacters(in: .whitespaces))
            let syntax = MermaidParser.flowchartSyntax(String(text))
            // An unreadable statement has no syntax to trust; search it whole.
            self.syntax = syntax.count == text.count ? syntax : text
        }

        var count: Int { text.count }
        subscript(range: Range<Int>) -> Written { Written(text: Array(text[range]), syntax: Array(syntax[range])) }

        /// Without the whitespace at either end.
        func trimmed() -> Written {
            let blank: (Character) -> Bool = { $0.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains) }
            let lead = text.prefix(while: blank).count
            let trail = text.dropFirst(lead).reversed().prefix(while: blank).count
            return self[lead..<(count - trail)]
        }
    }

    /// A statement's syntax, indexed once for regex searches that report
    /// characters (the regex engine counts UTF-16).
    private struct Searchable {
        let string: String
        /// The character each UTF-16 offset starts (-1 inside one), and the end.
        private let characterAt: [Int]
        /// Each character's UTF-16 offset, and the end's.
        private let offsetOf: [Int]

        init(_ syntax: [Character]) {
            string = String(syntax)
            var characterAt = [Int](repeating: -1, count: string.utf16.count + 1)
            var offsetOf: [Int] = []
            offsetOf.reserveCapacity(syntax.count + 1)
            var offset = 0
            for (k, c) in syntax.enumerated() {
                characterAt[offset] = k
                offsetOf.append(offset)
                offset += c.utf16.count
            }
            characterAt[offset] = syntax.count
            offsetOf.append(offset)
            self.characterAt = characterAt
            self.offsetOf = offsetOf
        }

        /// A match's groups, in characters (nil for one that didn't take part).
        func groups(_ match: NSTextCheckingResult) -> [Range<Int>?] {
            (0..<match.numberOfRanges).map { g in
                let range = match.range(at: g)
                guard range.location != NSNotFound else { return nil }
                return characterAt[range.location]..<characterAt[range.location + range.length]
            }
        }

        func matches(of pattern: NSRegularExpression) -> [[Range<Int>?]] {
            pattern.matches(in: string, range: NSRange(location: 0, length: offsetOf.last!)).map(groups)
        }

        /// The first match at or after character `start`, reading nothing
        /// before it (as if the text began there).
        func firstMatch(of pattern: NSRegularExpression, from start: Int) -> [Range<Int>?]? {
            pattern.firstMatch(in: string, range: NSRange(location: offsetOf[start], length: offsetOf.last! - offsetOf[start]))
                .map(groups)
        }
    }

    /// One link token between two endpoint lists.
    private struct Link {
        var dashed = false
        var thick = false
        var invisible = false
        var hasArrow = false
        var backArrow = false
        var head = Flowchart.Edge.Head.arrow
        var length = 1
        var label: String?
    }

    /// The longest link `length` honored: each extra rank is a layer of
    /// routing channels, so a runaway `------…->` can't blow up the layout.
    static let maxLinkLength = 10

    /// Mermaid's link tokens: solid (`-->`, `---`, `--o`, `--x`), thick
    /// (`==>`, `===`), dotted (`-.->`, `-.-`), invisible (`~~~`), each
    /// longer for a longer link, with an optional matching start head
    /// (`<-->`, `o--o`, `x--x`). Group 1 is the start head, 2 the body.
    private static let linkPattern: NSRegularExpression? = {
        let head = #"[ox](?=[\s|]|$)"#
        let body = [
            #"-{2,}>"#, #"-{2,}\#(head)"#, #"-{3,}"#,
            #"={2,}>"#, #"={2,}\#(head)"#, #"={3,}"#,
            #"-\.+->"#, #"-\.+-\#(head)"#, #"-\.+-"#,
            #"~{3,}"#,
        ].joined(separator: "|")
        return try? NSRegularExpression(pattern: #"((?<![^\s])[ox]|<)?("# + body + ")")
    }()

    /// The first link token in a statement's `syntax` at or after `start`:
    /// its range, in characters (with a start head only when it's the
    /// link's: `<-->`, or one written after the endpoint before it), and
    /// what it draws.
    private static func firstLink(in syntax: [Character], from start: Int,
                                  searching search: Searchable) -> (range: Range<Int>, link: Link)? {
        guard let pattern = linkPattern, let groups = search.firstMatch(of: pattern, from: start),
              let bodyRange = groups[2] else { return nil }
        var body = syntax[bodyRange]
        var link = Link()
        switch body.last {
        case ">": link.hasArrow = true; link.head = .arrow
        case "o": link.hasArrow = true; link.head = .circle
        case "x": link.hasArrow = true; link.head = .cross
        default: break
        }
        if link.hasArrow { body = body.dropLast() }
        var lower = bodyRange.lowerBound
        // A start head that doesn't match the end isn't one: mermaid reads it
        // as the link's first character (`<---` is `----`).
        var unmatchedStart = false
        let from = start
        if let startRange = groups[1] {
            let start = syntax[startRange.lowerBound]
            let matches = link.hasArrow &&
                ((start == "<" && link.head == .arrow) || (start == "o" && link.head == .circle) ||
                 (start == "x" && link.head == .cross))
            if matches {
                link.backArrow = true
                lower = startRange.lowerBound
            } else if start == "<" || syntax[from..<startRange.lowerBound].contains(where: { $0 != " " && $0 != "\t" }) {
                // An `o`/`x` with nothing before it is the endpoint itself
                // (`x-->o`); after an endpoint it's the link's.
                lower = startRange.lowerBound
                unmatchedStart = true
            }
        }
        // Lengths as mermaid counts them: dots for a dotted link, otherwise
        // the body less its first character (less one more for an open link,
        // whose body has no head to stand in for it). An unmatched start
        // counts, and makes the link solid: mermaid's stroke is the line's
        // first character.
        if body.first == "~" {
            link.invisible = true
            link.length = body.count - 2
        } else if body.contains(".") {
            link.dashed = true
            link.length = body.filter { $0 == "." }.count
        } else {
            link.thick = body.first == "=" && !unmatchedStart
            link.length = body.count - (link.hasArrow ? 1 : 2) + (unmatchedStart ? 1 : 0)
        }
        link.length = min(max(link.length, 1), maxLinkLength)
        return (lower..<bodyRange.upperBound, link)
    }

    /// Splits an endpoint list on each `&` in its syntax, so `A[Tom & Jerry]`
    /// and `A>Tom & Jerry]` stay whole; an `&` written between two id
    /// characters is part of the id (`B&C`), as in mermaid.
    private static func splitEndpoints(_ list: Written) -> [Written] {
        var parts: [Written] = []
        var start = 0
        for i in 0..<list.count where list.syntax[i] == "&" {
            let joinsAnID = i > 0 && i + 1 < list.count && isIDCharacter(list.text[i - 1]) && isIDCharacter(list.text[i + 1])
            guard !joinsAnID else { continue }
            parts.append(list[start..<i])
            start = i + 1
        }
        parts.append(list[start..<list.count])
        return parts
    }

    /// Parses one line's worth of edges — chained (`A --> B --> C`) and
    /// fanned (`A & B --> C`) forms yield several. The old single-edge parser
    /// silently erased any line it couldn't fully tokenize, which killed the
    /// most common idioms in real flowcharts. Links, `|labels|` and `&` are
    /// found in the line's syntax, never inside a label.
    /// `unread` collects the endpoints of an `&` fan that aren't nodes.
    private static func parseEdgeLine(_ raw: String, unread: inout [Substring]) -> [ParsedEdge]? {
        let line = normalizeEdgeSyntax(Written(raw))
        // Indexed once, so each link is found from where the last one ended
        // (linear in the line, however long the chain).
        let search = Searchable(line.syntax)
        var nextBar = [Int](repeating: line.count, count: line.count + 1)
        for i in stride(from: line.count - 1, through: 0, by: -1) {
            nextBar[i] = line.syntax[i] == "|" ? i : nextBar[i + 1]
        }
        var segments: [Written] = []
        var joins: [Link] = []
        var cursor = 0
        while true {
            guard let found = firstLink(in: line.syntax, from: cursor, searching: search) else {
                segments.append(line[cursor..<line.count])
                break
            }
            segments.append(line[cursor..<found.range.lowerBound].trimmed())
            var link = found.link
            var after = found.range.upperBound
            while after < line.count, line.syntax[after] == " " { after += 1 }
            if after < line.count, line.syntax[after] == "|", nextBar[after + 1] < line.count {
                let close = nextBar[after + 1]
                link.label = labelText(String(line.text[(after + 1)..<close]))
                after = close + 1
            }
            joins.append(link)
            cursor = after
        }
        guard !joins.isEmpty, segments.count == joins.count + 1 else { return nil }

        var ends: [[Flowchart.Node]] = []
        for segment in segments {
            var nodes: [Flowchart.Node] = []
            for part in splitEndpoints(segment) {
                let token = Substring(String(part.text))
                if let node = parseNodeToken(token) { nodes.append(node) } else { unread.append(token) }
            }
            guard !nodes.isEmpty else { unread = []; return nil }
            ends.append(nodes)
        }

        var out: [ParsedEdge] = []
        for (i, join) in joins.enumerated() {
            for l in ends[i] {
                for r in ends[i + 1] {
                    out.append(ParsedEdge(
                        fromNode: l, toNode: r,
                        edge: Flowchart.Edge(from: l.id, to: r.id, label: join.label,
                                             dashed: join.dashed, hasArrow: join.hasArrow,
                                             backArrow: join.backArrow, head: join.head,
                                             thick: join.thick, invisible: join.invisible,
                                             length: join.length)))
                }
            }
        }
        return out
    }

    /// Parses `id`, `id[Label]`, `id(Label)`, `id([Label])`, `id{Label}`,
    /// `id((Label))`, `id(((Label)))`, `id[(Label)]`, `id[[Label]]`,
    /// `id{{Label}}`, the slanted `id[/Label/]`, `id[\Label\]`, `id[/Label\]`
    /// and `id[\Label/]`, the asymmetric `id>Label]`, and the
    /// `id@{ shape: …, label: … }` shape-data form. Ids may contain `-`, `.`
    /// and `&` between word characters (`api-gateway`, `auth.service`,
    /// `B&C`), as in mermaid. A shape must close where the token ends: its
    /// text is read as `flowchartStatements` reads it (the first closer
    /// outside a string), so `x>a] --> B[c]` isn't one node labeled
    /// `a] --> B[c`.
    static func parseNodeToken(_ token: Substring) -> Flowchart.Node? {
        var trimmed = token.trimmingCharacters(in: .whitespaces)
        // `:::className` binds a style class — styling we ignore; without
        // this strip the tokenizer rejected the node and the line vanished.
        if let styleClass = trimmed.range(of: ":::") {
            trimmed = String(trimmed[..<styleClass.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        guard !trimmed.isEmpty else { return nil }

        /// A character an id is made of; `-` and `.` only join two of these.
        let isWord = isIDCharacter
        var id = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let c = trimmed[index]
            let next = trimmed.index(after: index)
            if isWord(c) {
                id.append(c)
            } else if (c == "-" || c == "." || c == "&"), !id.isEmpty, next < trimmed.endIndex, isWord(trimmed[next]) {
                // `api-gateway`, `auth.service`, `B&C`: a separator between
                // word characters. Edge connectors and `&` fans are split off
                // before this runs.
                id.append(c)
            } else {
                break
            }
            index = next
        }
        guard !id.isEmpty else { return nil }
        let rest = String(trimmed[index...])
        // The rest's syntax: a shape's text is all label (masked or blank).
        let syntax = flowchartSyntax(trimmed)
        let restSyntax = syntax.count == trimmed.count ? syntax.dropFirst(id.count) : []
        /// Whether `open` and `close` wrap nothing but the shape's text.
        func wraps(_ open: String, _ close: String) -> Bool {
            rest.hasPrefix(open) && rest.hasSuffix(close) && rest.count >= open.count + close.count
                && restSyntax.dropFirst(open.count).dropLast(close.count).allSatisfy { $0 == masked || $0 == " " || $0 == "\t" }
        }

        /// The label between `open` and `close` when they wrap the rest of the
        /// token, quotes and padding trimmed; nil for another shape.
        func stripped(_ open: String, _ close: String) -> String? {
            guard wraps(open, close) else { return nil }
            return labelText(String(rest.dropFirst(open.count).dropLast(close.count))
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }

        if rest.isEmpty {
            return Flowchart.Node(id: id, label: id, shape: .rectangle)
        }
        if wraps("@{", "}") {
            return shapeDataNode(id: id, body: rest.dropFirst(2).dropLast())
        }
        for (open, close, shape) in shapeDelimiters {
            if let label = stripped(open, close) {
                return Flowchart.Node(id: id, label: label, shape: shape)
            }
        }
        return nil
    }

    /// Each classic shape's delimiters, longest first so `{{` isn't read as
    /// `{` with a brace in the label. `parseNodeToken` reads a shape by
    /// them, and `flowchartStatements` ends a node's text at them.
    static let shapeDelimiters: [(open: String, close: String, shape: Flowchart.NodeShape)] = [
        ("(((", ")))", .doubleCircle), ("((", "))", .circle), ("([", "])", .stadium),
        ("[(", ")]", .cylinder), ("[[", "]]", .subroutine), ("{{", "}}", .hexagon),
        ("[/", "/]", .parallelogram), ("[\\", "\\]", .parallelogramAlt),
        ("[/", "\\]", .trapezoid), ("[\\", "/]", .trapezoidAlt),
        ("[", "]", .rectangle), ("(", ")", .rounded), ("{", "}", .diamond),
        (">", "]", .asymmetric),
    ]

    /// `id@{ shape: diam, label: "Decide" }` — mermaid's newer shape syntax.
    /// Named shapes map onto the model's; ones it has no case for (and an
    /// unknown name) are rectangles. Without a `label`, the id is the label.
    private static func shapeDataNode(id: String, body: Substring) -> Flowchart.Node {
        var fields: [String] = []
        var current = ""
        var quoted = false
        for c in body {
            if c == "\"" { quoted.toggle() }
            if c == ",", !quoted {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        fields.append(current)
        var label = id
        var shape = Flowchart.NodeShape.rectangle
        for field in fields {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon].trimmingCharacters(in: .whitespaces)
            let value = field[field.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "label" where !value.isEmpty: label = labelText(value)
            case "shape": shape = shapeNames[value.lowercased()] ?? .rectangle
            default: break
            }
        }
        return Flowchart.Node(id: id, label: label, shape: shape)
    }

    /// Mermaid's shape names (and aliases) that have a model case.
    private static let shapeNames: [String: Flowchart.NodeShape] = [
        "rect": .rectangle, "rectangle": .rectangle, "proc": .rectangle, "process": .rectangle,
        "rounded": .rounded, "event": .rounded,
        "stadium": .stadium, "pill": .stadium, "terminal": .stadium,
        "diam": .diamond, "diamond": .diamond, "decision": .diamond, "question": .diamond,
        "circle": .circle, "circ": .circle,
        "dbl-circ": .doubleCircle, "double-circle": .doubleCircle,
        "lean-r": .parallelogram, "lean-right": .parallelogram, "in-out": .parallelogram,
        "lean-l": .parallelogramAlt, "lean-left": .parallelogramAlt, "out-in": .parallelogramAlt,
        "trap-b": .trapezoid, "trapezoid-bottom": .trapezoid, "priority": .trapezoid,
        "trap-t": .trapezoidAlt, "trapezoid-top": .trapezoidAlt, "manual": .trapezoidAlt,
        "odd": .asymmetric,
        "cyl": .cylinder, "cylinder": .cylinder, "database": .cylinder, "db": .cylinder,
        "hex": .hexagon, "hexagon": .hexagon, "prepare": .hexagon,
        "subproc": .subroutine, "subprocess": .subroutine, "subroutine": .subroutine,
        "fr-rect": .subroutine, "framed-rectangle": .subroutine,
    ]


    // MARK: State

    /// stateDiagram / stateDiagram-v2 → a nested StateDiagram. `state X { … }`
    /// blocks recurse into composites (each with its own `[*]` entry/exit);
    /// `<<choice>>` / `<<fork>>` / `<<join>>` annotations mark special shapes;
    /// transitions are arrows with an optional `: label`.
    static func parseState(body: [String]) -> StateDiagram? {
        // Composite parsing (and the layout that mirrors it) recurses once per
        // `state X {` nesting level. A linear pre-scan bounds that depth so
        // adversarial input can't overflow the stack — past the cap the block
        // degrades to the tidy styled-source card.
        var depth = 0, maxDepth = 0
        for line in body {
            if line.hasPrefix("state "), line.hasSuffix("{") { depth += 1; maxDepth = max(maxDepth, depth) }
            if line == "}" { depth = max(0, depth - 1) }
        }
        guard maxDepth <= 32 else { return nil }

        var index = 0
        var scopeCounter = 0
        let direction = detectStateDirection(body)

        // Recursively parses one brace scope, consuming lines until its
        // closing `}` (or end of input for the root). `scopeID` disambiguates
        // this scope's synthetic `[*]` terminals from every other scope's.
        func parseScope(scopeID: String) -> StateDiagram {
            var nodes: [String: StateDiagram.Node] = [:]
            var order: [String] = []
            var edges: [StateDiagram.Edge] = []
            var annotations: [String: StateDiagram.Kind] = [:]  // id → choice/fork/join

            func note(id: String, label: String, kind: StateDiagram.Kind) {
                if let existing = nodes[id] {
                    // Upgrade a bare reference to a labelled / composite node.
                    if existing.label == existing.id && (label != id || !isSimple(kind)) {
                        nodes[id] = StateDiagram.Node(id: id, label: label, kind: kind)
                    } else if isComposite(kind) {
                        nodes[id] = StateDiagram.Node(id: id, label: label, kind: kind)
                    }
                } else {
                    nodes[id] = StateDiagram.Node(id: id, label: label, kind: kind)
                    order.append(id)
                }
            }

            // Resolves a transition endpoint token to a node id, minting a
            // scope-local terminal for `[*]`.
            func endpoint(_ token: String, isSource: Bool) -> String? {
                let trimmed = token.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                if trimmed == "[*]" {
                    let id = isSource ? "\(scopeID)__start" : "\(scopeID)__end"
                    note(id: id, label: "", kind: isSource ? .start : .end)
                    return id
                }
                guard trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
                note(id: trimmed, label: trimmed, kind: .simple)
                return trimmed
            }

            while index < body.count {
                let line = body[index]
                index += 1

                if line == "}" { break }                       // close this scope
                if line.hasPrefix("direction") { continue }    // handled globally
                if line.hasPrefix("note") || line.hasPrefix("Note") { continue }

                // `state X { ` opens a composite — recurse.
                if line.hasPrefix("state "), line.hasSuffix("{") {
                    let inner = String(line.dropFirst("state ".count).dropLast())
                        .trimmingCharacters(in: .whitespaces)
                    let (id, label) = stateNameAndLabel(inner)
                    scopeCounter += 1
                    let child = parseScope(scopeID: "s\(scopeCounter)_")
                    nodes[id] = StateDiagram.Node(id: id, label: label, kind: .composite(child))
                    if !order.contains(id) { order.append(id) }
                    continue
                }

                // `state X <<choice>>` / `<<fork>>` / `<<join>>` annotations.
                if line.hasPrefix("state "), let annotationRange = line.range(of: "<<") {
                    let id = String(line[line.index(line.startIndex, offsetBy: "state ".count)..<annotationRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    let annotation = line[annotationRange.lowerBound...]
                    let kind: StateDiagram.Kind? = annotation.contains("choice") ? .choice
                        : annotation.contains("fork") ? .fork
                        : annotation.contains("join") ? .join : nil
                    if let kind, !id.isEmpty {
                        annotations[id] = kind
                        note(id: id, label: id, kind: kind)
                    }
                    continue
                }

                // `state "Long description" as s2`
                if line.hasPrefix("state ") {
                    let declaration = String(line.dropFirst("state ".count))
                    if let asRange = declaration.range(of: " as ") {
                        let label = String(declaration[..<asRange.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        let id = String(declaration[asRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if !id.isEmpty { note(id: id, label: label, kind: .simple) }
                    } else {
                        let (id, label) = stateNameAndLabel(declaration.trimmingCharacters(in: .whitespaces))
                        if !id.isEmpty { note(id: id, label: label, kind: .simple) }
                    }
                    continue
                }

                if let arrowRange = line.range(of: "-->") {
                    let left = String(line[..<arrowRange.lowerBound])
                    var right = String(line[arrowRange.upperBound...])
                    var label: String?
                    if let colon = right.firstIndex(of: ":") {
                        label = String(right[right.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        right = String(right[..<colon])
                    }
                    guard let from = endpoint(left, isSource: true),
                          let to = endpoint(right, isSource: false) else { continue }
                    edges.append(StateDiagram.Edge(from: from, to: to, label: label))
                    continue
                }

                // Bare state id on its own line.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    note(id: trimmed, label: trimmed, kind: .simple)
                }
            }

            // Apply any annotations that arrived after a node was first seen.
            for (id, kind) in annotations where nodes[id] != nil {
                nodes[id] = StateDiagram.Node(id: id, label: nodes[id]!.label == id ? id : nodes[id]!.label, kind: kind)
            }

            return StateDiagram(
                direction: direction,
                nodes: order.compactMap { nodes[$0] },
                edges: edges
            )
        }

        let root = parseScope(scopeID: "root_")
        guard !root.nodes.isEmpty else { return nil }
        return root
    }

    private static func detectStateDirection(_ body: [String]) -> Flowchart.Direction {
        for line in body where line.hasPrefix("direction") {
            let value = line.dropFirst("direction".count).trimmingCharacters(in: .whitespaces)
            return Flowchart.Direction(rawValue: value.uppercased()) ?? .topDown
        }
        return .topDown
    }

    /// `Foo` → (Foo, Foo); `Foo : Nice Label` → (Foo, "Nice Label").
    private static func stateNameAndLabel(_ text: String) -> (String, String) {
        if let colon = text.firstIndex(of: ":") {
            let id = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let label = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return (id, label.isEmpty ? id : label)
        }
        let id = text.trimmingCharacters(in: .whitespaces)
        return (id, id)
    }

    private static func isSimple(_ kind: StateDiagram.Kind) -> Bool {
        if case .simple = kind { return true }
        return false
    }
    private static func isComposite(_ kind: StateDiagram.Kind) -> Bool {
        if case .composite = kind { return true }
        return false
    }

    // MARK: Class

    static func parseClass(body: [String]) -> ClassDiagram? {
        var classes: [String: ClassDiagram.Class] = [:]
        var order: [String] = []
        var relations: [ClassDiagram.Relation] = []
        var openClass: String? // inside `class X { … }`

        // Mints (or finds) the class a written name refers to and returns its
        // id: `Box~T~` and `Box` are the same class.
        @discardableResult
        func note(_ written: String) -> String {
            let (name, generic) = splitGeneric(written)
            guard !name.isEmpty else { return name }
            if classes[name] == nil {
                classes[name] = ClassDiagram.Class(name: name, generic: generic, attributes: [], methods: [])
                order.append(name)
            } else if classes[name]?.generic == nil {
                // mermaid keeps only the first mention's generic, so
                // `Box --> Item` then `class Box~T~` loses the `T`; keep it.
                classes[name]?.generic = generic
            }
            return name
        }

        func addMember(_ raw: String, to written: String) {
            let member = raw.trimmingCharacters(in: .whitespaces)
            guard !member.isEmpty else { return }
            let name = note(written)
            if member.contains("(") {
                classes[name]?.methods.append(genericMember(member))
            } else {
                classes[name]?.attributes.append(genericMember(member))
            }
        }

        // Mermaid multiplicity labels sit as a quoted token next to the
        // connector: `ClassA "1" *-- "many" ClassB`. Strip them so the
        // endpoint names still match the declared classes.
        func stripMultiplicity(_ text: String, trailing: Bool) -> String {
            let pattern = trailing ? #"\s*"[^"]*"$"# : #"^"[^"]*"\s*"#
            guard let range = text.range(of: pattern, options: .regularExpression) else { return text }
            let stripped = trailing ? text[..<range.lowerBound] : text[range.upperBound...]
            return stripped.trimmingCharacters(in: .whitespaces)
        }

        // Relation connectors, longest first. Reversed forms flip from/to
        // so the marker is always at the `to` end.
        let connectors: [(token: String, kind: ClassDiagram.RelationKind, reversed: Bool)] = [
            ("<|--", .inheritance, true), ("--|>", .inheritance, false),
            ("<|..", .realization, true), ("..|>", .realization, false),
            ("*--", .composition, true), ("--*", .composition, false),
            ("o--", .aggregation, true), ("--o", .aggregation, false),
            ("<--", .association, true), ("-->", .association, false),
            ("<..", .dependency, true), ("..>", .dependency, false),
            ("--", .link, false), ("..", .link, false),
        ]

        for line in body {
            if let current = openClass {
                if line == "}" { openClass = nil; continue }
                addMember(line, to: current)
                continue
            }
            if line.hasPrefix("class ") {
                var declaration = String(line.dropFirst("class ".count)).trimmingCharacters(in: .whitespaces)
                if declaration.hasSuffix("{") {
                    declaration = String(declaration.dropLast()).trimmingCharacters(in: .whitespaces)
                    openClass = declaration
                }
                note(declaration)
                continue
            }
            if line.hasPrefix("<<") || line.hasPrefix("note") { continue }

            // Member via colon shorthand: `Animal : +int age` — but only
            // when no relation connector is present on the line.
            if !connectors.contains(where: { line.contains($0.token) }),
               let colon = line.firstIndex(of: ":") {
                let written = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let name = splitGeneric(written).name
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    addMember(String(line[line.index(after: colon)...]), to: written)
                }
                continue
            }

            for connector in connectors {
                guard let range = line.range(of: connector.token) else { continue }
                let left = stripMultiplicity(
                    String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    trailing: true
                )
                var right = String(line[range.upperBound...])
                var label: String?
                if let colon = right.firstIndex(of: ":") {
                    label = String(right[right.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    right = String(right[..<colon])
                }
                let rightName = stripMultiplicity(right.trimmingCharacters(in: .whitespaces), trailing: false)
                guard !left.isEmpty, !rightName.isEmpty else { break }
                let leftID = note(left), rightID = note(rightName)
                let from = connector.reversed ? rightID : leftID
                let to = connector.reversed ? leftID : rightID
                relations.append(ClassDiagram.Relation(from: from, to: to, kind: connector.kind, label: label))
                break
            }
        }

        guard !classes.isEmpty else { return nil }
        return ClassDiagram(classes: order.compactMap { classes[$0] }, relations: relations)
    }

    /// `Box~T~` → (`Box`, `T`): mermaid splits a class name at its first
    /// tilde. A name whose generic never closes (`Box~T`) stays whole, as
    /// written; an empty one (`Box~~`) is just `Box`.
    static func splitGeneric(_ written: String) -> (name: String, generic: String?) {
        guard let open = written.firstIndex(of: "~"), open > written.startIndex,
              written.hasSuffix("~"), written.index(before: written.endIndex) > open else {
            return (written, nil)
        }
        let name = String(written[..<open]).trimmingCharacters(in: .whitespaces)
        let generic = String(written[written.index(after: open)..<written.index(before: written.endIndex)])
        return (name, generic.trimmingCharacters(in: .whitespaces).isEmpty ? nil : generic)
    }

    /// A class member as mermaid shows it: generics read `<T>` in a method's
    /// name, parameters and return type, each on its own (so
    /// `+map~U~(f) Box~U~` pairs within each part, never across them).
    /// The leading visibility (`~` is package) is never a generic.
    static func genericMember(_ member: String) -> String {
        guard member.contains("~") else { return member }
        var rest = Substring(member)
        var visibility = ""
        if let first = rest.first, "+-#~".contains(first) {
            visibility = String(first)
            rest = rest.dropFirst()
        }
        // mermaid's method split: the name runs to the last `(` before the
        // last `)`.
        guard let close = rest.lastIndex(of: ")"),
              let open = rest[..<close].lastIndex(of: "("), open > rest.startIndex else {
            return visibility + genericTypes(String(rest))
        }
        return visibility + genericTypes(String(rest[..<open]))
            + "(" + genericTypes(String(rest[rest.index(after: open)..<close])) + ")"
            + genericTypes(String(rest[rest.index(after: close)...]))
    }

    /// mermaid's `parseGenericTypes`: split at commas, glue `Map~K` and
    /// ` V~` back together (one tilde on each side), then pair each piece's
    /// tildes outside-in, so `List~List~int~~` reads `List<List<int>>`.
    /// A lone tilde stays. One deliberate difference: mermaid can glue a
    /// piece twice and lose text (`a~b,c~d,e~f` shows `c<d,e>f`); here a
    /// piece glues once, and nothing written is dropped.
    static func genericTypes(_ text: String) -> String {
        guard text.contains("~") else { return text }
        // Pieces and the "," between them, like JS `split(/(,)/)`.
        let sets = Array(text.split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { [String($0), ","] }
            .dropLast())
        func tildes(_ s: String) -> Int { s.reduce(0) { $1 == "~" ? $0 + 1 : $0 } }
        var output: [String] = []
        var glued = -1 // the last piece already glued onto the one before it
        var i = 0
        while i < sets.count {
            var set = sets[i]
            if set == ",", i > 0, i + 1 < sets.count, i - 1 != glued,
               tildes(sets[i - 1]) == 1, tildes(sets[i + 1]) == 1 {
                set = sets[i - 1] + "," + sets[i + 1]
                output.removeLast()
                i += 1
                glued = i
            }
            output.append(pairTildes(set))
            i += 1
        }
        return output.joined()
    }

    /// mermaid's `processSet`: the first tilde pairs with the last, the
    /// second with the second-to-last, and so on; with an odd count a
    /// leading tilde sits out (else the middle one stays).
    private static func pairTildes(_ text: String) -> String {
        var chars = Array(text)
        var positions = chars.indices.filter { chars[$0] == "~" }
        guard positions.count > 1 else { return text }
        if positions.count % 2 != 0, positions.first == 0 { positions.removeFirst() }
        for k in 0..<positions.count / 2 {
            chars[positions[k]] = "<"
            chars[positions[positions.count - 1 - k]] = ">"
        }
        return String(chars)
    }

    // MARK: ER

    static func parseER(body: [String]) -> ERDiagram? {
        var entities: [String: ERDiagram.Entity] = [:]
        var order: [String] = []
        var relations: [ERDiagram.Relation] = []
        var openEntity: String?

        func note(_ name: String) {
            guard !name.isEmpty, entities[name] == nil else { return }
            entities[name] = ERDiagram.Entity(name: name, attributes: [])
            order.append(name)
        }

        func cardinality(_ token: String) -> ERDiagram.Cardinality? {
            // Left-side tokens read outward (||, |o, }o, }|); right-side
            // tokens are mirrored (||, o|, o{, |{). Normalize both.
            switch token {
            case "||": return .one
            case "|o", "o|": return .zeroOrOne
            case "}|", "|{": return .oneOrMore
            case "}o", "o{": return .zeroOrMore
            default: return nil
            }
        }

        for line in body {
            if let current = openEntity {
                if line == "}" { openEntity = nil; continue }
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    entities[current]?.attributes.append(
                        ERDiagram.Attribute(type: String(parts[0]), name: String(parts[1]))
                    )
                }
                continue
            }
            if line.hasSuffix("{"), !line.contains("--"), !line.contains("..") {
                let name = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    note(name)
                    openEntity = name
                }
                continue
            }

            // A ||--o{ B : label   (also `..` for non-identifying)
            for separator in ["--", ".."] {
                guard let range = line.range(of: separator) else { continue }
                let left = String(line[..<range.lowerBound])
                var right = String(line[range.upperBound...])
                guard left.count >= 2, right.count >= 2 else { continue }
                let leftCardToken = String(left.suffix(2))
                let rightCardToken = String(right.prefix(2))
                guard let fromCard = cardinality(leftCardToken),
                      let toCard = cardinality(rightCardToken)
                else { continue }
                let from = String(left.dropLast(2)).trimmingCharacters(in: .whitespaces)
                right = String(right.dropFirst(2))
                var label = ""
                if let colon = right.firstIndex(of: ":") {
                    label = String(right[right.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    right = String(right[..<colon])
                }
                let to = right.trimmingCharacters(in: .whitespaces)
                guard !from.isEmpty, !to.isEmpty else { continue }
                note(from)
                note(to)
                relations.append(ERDiagram.Relation(
                    from: from, to: to,
                    fromCard: fromCard, toCard: toCard,
                    label: label, identifying: separator == "--"
                ))
                break
            }
        }

        guard !entities.isEmpty else { return nil }
        return ERDiagram(entities: order.compactMap { entities[$0] }, relations: relations)
    }

    // MARK: Sequence

    static func parseSequence(body: [String]) -> SequenceDiagram? {
        var participants: [String: SequenceDiagram.Participant] = [:]
        var order: [String] = []
        var messages: [SequenceDiagram.Message] = []

        var notes: [SequenceDiagram.Note] = []
        var declaredKind: [String: SequenceDiagram.Participant.Kind] = [:]
        var fragments: [SequenceDiagram.Fragment] = []
        var boxes: [SequenceDiagram.Box] = []
        var openBox: (label: String?, members: [String])?
        var events: [SequenceDiagram.Event] = []
        var openFragments: [Int] = []   // stack of fragment indices
        func note(_ id: String, label: String? = nil, isActor: Bool = false) {
            if participants[id] == nil {
                participants[id] = SequenceDiagram.Participant(id: id, label: label ?? id, isActor: isActor)
                order.append(id)
            } else if let label {
                participants[id] = SequenceDiagram.Participant(
                    id: id, label: label, isActor: participants[id]?.isActor == true || isActor)
            }
        }

        var autonumber = 0   // 0 = off; >0 = next number to stamp
        var autonumberStep = 1
        for line in body {
            if line == "autonumber" || line.hasPrefix("autonumber ") {
                // `autonumber` / `autonumber 10` / `autonumber 10 5` /
                // `autonumber off`.
                let parts = line.split(separator: " ").dropFirst().map(String.init)
                if parts.first == "off" { autonumber = 0 }
                else {
                    autonumber = parts.first.flatMap(Int.init) ?? 1
                    autonumberStep = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
                }
                continue
            }
            if line.hasPrefix("participant") || line.hasPrefix("actor") {
                // Strip only the leading keyword — a global replace once
                // corrupted labels containing the word "actor ".
                var declaration = line
                var isActor = false
                if declaration.hasPrefix("participant ") { declaration = String(declaration.dropFirst(12)) }
                else if declaration.hasPrefix("actor ") { declaration = String(declaration.dropFirst(6)); isActor = true }
                // Typed heads: `participant B@{ "type": "database" }`.
                var kind: SequenceDiagram.Participant.Kind? = isActor ? .actor : nil
                if let at = declaration.range(of: "@{") {
                    let spec = String(declaration[at.upperBound...])
                    if let typeRange = spec.range(of: "type") {
                        let value = spec[typeRange.upperBound...]
                            .trimmingCharacters(in: CharacterSet(charactersIn: " :\"'}"))
                        if let parsed = SequenceDiagram.Participant.Kind(
                            rawValue: value.lowercased()) { kind = parsed }
                    }
                    declaration = String(declaration[..<at.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                let id: String
                if let asRange = declaration.range(of: " as ") {
                    id = String(declaration[..<asRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let label = String(declaration[asRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    note(id, label: label, isActor: kind == .actor)
                } else {
                    id = declaration.trimmingCharacters(in: .whitespaces)
                    note(id, isActor: kind == .actor)
                }
                if let kind { declaredKind[id] = kind }
                openBox?.members.append(id)
                continue
            }
            // `Note right of A: text` / `Note left of A: text` /
            // `Note over A,B: text` — author content that used to vanish.
            if line.lowercased().hasPrefix("note ") {
                let rest = String(line.dropFirst(5))
                let lower = rest.lowercased()
                var position: SequenceDiagram.Note.Position?
                var idText = ""
                if lower.hasPrefix("right of ") { position = .rightOf; idText = String(rest.dropFirst(9)) }
                else if lower.hasPrefix("left of ") { position = .leftOf; idText = String(rest.dropFirst(8)) }
                else if lower.hasPrefix("over ") { position = .over; idText = String(rest.dropFirst(5)) }
                if let position, let colon = idText.firstIndex(of: ":") {
                    let ids = idText[..<colon].split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let text = String(idText[idText.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    if !ids.isEmpty, !text.isEmpty {
                        ids.forEach { note($0) }
                        notes.append(.init(position: position, ids: ids, text: text,
                                           afterMessage: messages.count))
                        events.append(.note(notes.count - 1))
                        continue
                    }
                }
                continue // malformed note: skip, never a phantom message
            }
            // Combined fragments: a tolerant stack machine. Unclosed frames
            // close at end-of-diagram; a stray `end` is ignored.
            let keyword = line.split(separator: " ").first.map(String.init) ?? line
            if let kind = SequenceDiagram.Fragment.Kind(rawValue: keyword) {
                let label = line.count > keyword.count
                    ? String(line.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                    : nil
                fragments.append(.init(kind: kind, label: label?.isEmpty == true ? nil : label))
                openFragments.append(fragments.count - 1)
                events.append(.open(fragments.count - 1))
                continue
            }
            if keyword == "else" || keyword == "and" || keyword == "option" {
                if let top = openFragments.last {
                    let label = line.count > keyword.count
                        ? String(line.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                        : nil
                    events.append(.divider(fragment: top, label: label?.isEmpty == true ? nil : label))
                }
                continue
            }
            if line == "end" {
                if openBox != nil {
                    // `end` closes the innermost construct: an open box wins
                    // (boxes can't contain messages, so no ambiguity).
                    boxes.append(.init(label: openBox!.label, memberIDs: openBox!.members))
                    openBox = nil
                } else if let top = openFragments.popLast() {
                    events.append(.close(top))
                }
                continue
            }
            if line.hasPrefix("create participant ") || line.hasPrefix("create actor ") {
                let isActor = line.hasPrefix("create actor ")
                let declaration = String(line.dropFirst(isActor ? 13 : 19))
                let id: String
                if let asRange = declaration.range(of: " as ") {
                    id = String(declaration[..<asRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    note(id, label: String(declaration[asRange.upperBound...]).trimmingCharacters(in: .whitespaces),
                         isActor: isActor)
                } else {
                    id = declaration.trimmingCharacters(in: .whitespaces)
                    note(id, isActor: isActor)
                }
                if !id.isEmpty { events.append(.create(id)) }
                continue
            }
            if line.hasPrefix("destroy ") {
                let id = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { note(id); events.append(.destroy(id)) }
                continue
            }
            if line.hasPrefix("activate ") {
                let id = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { note(id); events.append(.activate(id)) }
                continue
            }
            if line.hasPrefix("deactivate ") {
                let id = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { events.append(.deactivate(id)) }
                continue
            }
            if line.hasPrefix("box ") || line == "box" {
                // `box [color] Label` — the first token may be a CSS color or
                // rgb(...)/transparent; everything else is the label.
                var label: String? = line == "box" ? nil : String(line.dropFirst(4))
                if let text = label {
                    let tokens = text.split(separator: " ").map(String.init)
                    let colorish = tokens.first.map { token in
                        token.lowercased() == "transparent" || token.hasPrefix("rgb(")
                            || token.hasPrefix("#")
                            || ["aqua", "aliceblue", "lightblue", "lightgrey", "lightgreen",
                                "lightyellow", "mistyrose", "lavender", "beige"].contains(token.lowercased())
                    } ?? false
                    label = colorish ? tokens.dropFirst().joined(separator: " ") : text
                    if label?.isEmpty == true { label = nil }
                }
                openBox = (label, [])
                continue
            }

            // Messages. Longest token first so `-->>` never part-matches as
            // `-->`. Every mermaid arrow token maps to its true head style.
            typealias Head = SequenceDiagram.Message.ArrowHead
            let arrowTokens: [(token: String, dashed: Bool, head: Head)] = [
                ("<<-->>", true, .both), ("<<->>", false, .both),
                ("--)", true, .open), ("-->>", true, .filled), ("->>", false, .filled),
                ("-->", true, .none), ("--x", true, .cross), ("-)", false, .open),
                ("-x", false, .cross), ("->", false, .none),
            ]
            for (token, dashed, head) in arrowTokens {
                guard let range = line.range(of: token) else { continue }
                var from = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let remainder = String(line[range.upperBound...])
                let pieces = remainder.split(separator: ":", maxSplits: 1)
                var to = pieces.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                let text = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
                // Activation shorthand: `A->>+B:` / `B->>-A:` — the +/- binds
                // activation, it is NOT part of the participant name. The old
                // parser minted phantom "+B"/"-B" lifelines from the docs'
                // very first example.
                var activates = false
                var deactivates = false
                if to.hasPrefix("+") { activates = true }
                if to.hasPrefix("-") { deactivates = true }   // `->>-A:` deactivates the RECEIVER-side sender form below
                if to.hasPrefix("+") || to.hasPrefix("-") { to = String(to.dropFirst()).trimmingCharacters(in: .whitespaces) }
                if from.hasSuffix("+") || from.hasSuffix("-") { from = String(from.dropLast()).trimmingCharacters(in: .whitespaces) }
                guard !from.isEmpty, !to.isEmpty else { break }
                var number: Int?
                if autonumber > 0 {
                    number = autonumber
                    autonumber += autonumberStep
                }
                note(from)
                note(to)
                messages.append(SequenceDiagram.Message(
                    from: from, to: to, text: text, dashed: dashed,
                    head: head, number: number,
                    activatesTarget: activates, deactivatesSender: deactivates))
                events.append(.message(messages.count - 1))
                break
            }
        }

        guard !participants.isEmpty else { return nil }
        // Close any unclosed frames (author forgot `end`): tolerant, not fatal.
        while let top = openFragments.popLast() { events.append(.close(top)) }
        if let box = openBox { boxes.append(.init(label: box.label, memberIDs: box.members)) }
        return SequenceDiagram(
            participants: order.compactMap { id -> SequenceDiagram.Participant? in
                guard var participant = participants[id] else { return nil }
                if let kind = declaredKind[id] { participant.kind = kind }
                return participant
            },
            boxes: boxes,
            notes: notes,
            fragments: fragments,
            events: events,
            messages: messages
        )
    }

}
