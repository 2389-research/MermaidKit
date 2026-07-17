import Foundation

// A Swift front-end for SQL DDL (`CREATE TABLE …`) that targets the `ERDiagram`
// IR, so a schema dump flows through the same layered layout → renderer as a
// Mermaid `erDiagram`. It parses the structural core — tables, typed columns,
// PRIMARY/FOREIGN/UNIQUE keys (inline and table-level), and REFERENCES — mapping
// each foreign key to a one-to-many crow's-foot relationship. Unknown syntax
// (CHECK, INDEX, DEFAULT, engine options, dialect quoting) is ignored, never
// fatal. Like the other front-ends it degrades gracefully: malformed, huge, or
// hostile input returns `nil`, and the shared `maxTextSize`/`maxEdges` caps hold.
public enum SQLDDLParser {

    /// Parses one or more `CREATE TABLE` statements into an `ERDiagram`; `nil`
    /// when the source has no parseable table.
    public static func parse(_ source: String) -> ERDiagram? {
        guard source.count <= MermaidParser.maxTextSize else { return nil }
        let tokens = SQLLexer.tokenize(source)
        guard !tokens.isEmpty else { return nil }
        return SQLDDLImpl(tokens: tokens).run()
    }
}

// MARK: - Tokens & lexer

private struct SQLTok {
    let text: String
    let word: Bool   // false for the punctuation tokens ( ) , and skipped literals
}

private enum SQLLexer {
    static func tokenize(_ s: String) -> [SQLTok] {
        var toks: [SQLTok] = []
        let a = Array(s); let n = a.count; var i = 0
        func peek(_ k: Int = 1) -> Character? { i + k < n ? a[i + k] : nil }

        while i < n {
            let c = a[i]
            if c == " " || c == "\t" || c == "\r" || c == "\n" { i += 1; continue }
            // Comments: `-- line`, `/* block */`.
            if c == "-" && peek() == "-" { while i < n && a[i] != "\n" { i += 1 }; continue }
            if c == "/" && peek() == "*" {
                i += 2
                while i < n && !(a[i] == "*" && i + 1 < n && a[i + 1] == "/") { i += 1 }
                if i < n { i += 2 }
                continue
            }
            // Structural punctuation.
            if c == "(" || c == ")" || c == "," { toks.append(SQLTok(text: String(c), word: false)); i += 1; continue }
            if c == ";" { toks.append(SQLTok(text: ";", word: false)); i += 1; continue }
            // Quoted identifiers: "x", `x`, [x].
            if c == "\"" || c == "`" {
                let close = c; var j = i + 1; var out = ""
                while j < n && a[j] != close { out.append(a[j]); j += 1 }
                toks.append(SQLTok(text: out, word: true)); i = j < n ? j + 1 : j; continue
            }
            if c == "[" {
                var j = i + 1; var out = ""
                while j < n && a[j] != "]" { out.append(a[j]); j += 1 }
                toks.append(SQLTok(text: out, word: true)); i = j < n ? j + 1 : j; continue
            }
            // String literal (default values, etc.) — kept as a non-word token so
            // it never masquerades as a column name.
            if c == "'" {
                var j = i + 1; var out = ""
                while j < n {
                    if a[j] == "'" { if j + 1 < n && a[j + 1] == "'" { out.append("'"); j += 2; continue } else { break } }
                    out.append(a[j]); j += 1
                }
                toks.append(SQLTok(text: out, word: false)); i = j < n ? j + 1 : j; continue
            }
            // Identifier / keyword.
            if c.isLetter || c == "_" {
                var j = i + 1
                while j < n && (a[j].isLetter || a[j].isNumber || a[j] == "_") { j += 1 }
                toks.append(SQLTok(text: String(a[i..<j]), word: true)); i = j; continue
            }
            // Numeral.
            if c.isNumber {
                var j = i + 1
                while j < n && (a[j].isNumber || a[j] == ".") { j += 1 }
                toks.append(SQLTok(text: String(a[i..<j]), word: true)); i = j; continue
            }
            i += 1   // any other char (=, operators, dots) — skip
        }
        return toks
    }
}

// MARK: - Parser

private final class SQLDDLImpl {
    private let t: [SQLTok]
    private var i = 0

    private var order: [String] = []
    private var entities: [String: ERDiagram.Entity] = [:]
    private var relations: [ERDiagram.Relation] = []
    private var relSeen = Set<String>()

    init(tokens: [SQLTok]) { self.t = tokens }

    // token helpers
    private func kw(_ word: String, at k: Int) -> Bool {
        k < t.count && t[k].word && t[k].text.lowercased() == word
    }
    private func isPunct(_ text: String, at k: Int) -> Bool {
        k < t.count && !t[k].word && t[k].text == text
    }

    func run() -> ERDiagram? {
        while i < t.count {
            let before = i
            if kw("create", at: i) {
                i += 1
                skip(["global", "local", "temp", "temporary", "unlogged"])
                if kw("table", at: i) { i += 1; parseCreateTable() }
            } else {
                i += 1
            }
            if i == before { i += 1 }   // forward-progress guard
        }

        guard !entities.isEmpty else { return nil }
        let known = Set(order)
        let rels = relations.filter { known.contains($0.from) && known.contains($0.to) }
        guard rels.count <= MermaidParser.maxEdges else { return nil }
        return ERDiagram(entities: order.compactMap { entities[$0] }, relations: rels)
    }

    private func skip(_ words: [String]) {
        while i < t.count, t[i].word, words.contains(t[i].text.lowercased()) { i += 1 }
    }

    private func parseCreateTable() {
        skip(["if", "not", "exists"])
        guard i < t.count, t[i].word else { return }
        let table = t[i].text; i += 1
        guard isPunct("(", at: i) else { skipStatement(); return }   // e.g. CREATE TABLE x AS SELECT …
        i += 1

        // Split the parenthesized body into top-level (depth-1) items.
        var items: [[SQLTok]] = [[]]
        var depth = 1
        while i < t.count && depth > 0 {
            let tk = t[i]
            if !tk.word && tk.text == "(" { depth += 1; items[items.count - 1].append(tk); i += 1; continue }
            if !tk.word && tk.text == ")" { depth -= 1; if depth == 0 { i += 1; break }; items[items.count - 1].append(tk); i += 1; continue }
            if !tk.word && tk.text == "," && depth == 1 { items.append([]); i += 1; continue }
            items[items.count - 1].append(tk); i += 1
        }
        skipStatement()

        var attributes: [ERDiagram.Attribute] = []
        var indexOf: [String: Int] = [:]
        var fkTargets: [(col: String, refTable: String)] = []

        for item in items where !item.isEmpty {
            if isConstraintHead(item) {
                parseTableConstraint(item, into: &attributes, indexOf: indexOf, fks: &fkTargets)
            } else {
                parseColumn(item, into: &attributes, indexOf: &indexOf, fks: &fkTargets)
            }
        }

        if entities[table] == nil { order.append(table) }
        entities[table] = ERDiagram.Entity(name: table, attributes: attributes)

        for fk in fkTargets { addRelation(from: fk.refTable, to: table) }
    }

    // A body item is a table constraint when it opens with one of these words.
    private func isConstraintHead(_ item: [SQLTok]) -> Bool {
        guard let head = item.first, head.word else { return false }
        switch head.text.lowercased() {
        case "primary", "foreign", "unique", "constraint", "key", "check", "index", "exclude": return true
        default: return false
        }
    }

    private func parseColumn(_ item: [SQLTok], into attrs: inout [ERDiagram.Attribute],
                             indexOf: inout [String: Int], fks: inout [(col: String, refTable: String)]) {
        var p = 0
        guard p < item.count, item[p].word else { return }
        let name = item[p].text; p += 1

        // Type: the next word plus any immediately-following (…) size clause.
        var type = ""
        if p < item.count, item[p].word {
            type = item[p].text; p += 1
            if p < item.count, !item[p].word, item[p].text == "(" {
                var d = 0
                while p < item.count {
                    let tk = item[p]
                    if !tk.word, tk.text == "(" { d += 1; type += "("; p += 1; continue }
                    if !tk.word, tk.text == ")" { d -= 1; type += ")"; p += 1; if d == 0 { break }; continue }
                    type += tk.text; p += 1
                }
            }
        }

        var keys: [ERDiagram.Attribute.Key] = []
        while p < item.count {
            if item[p].word {
                switch item[p].text.lowercased() {
                case "primary":
                    keys.append(.primary); p += 1
                    if p < item.count, item[p].word, item[p].text.lowercased() == "key" { p += 1 }   // "PRIMARY KEY"
                    continue
                case "unique":
                    keys.append(.unique); p += 1; continue
                case "references":
                    p += 1
                    if p < item.count, item[p].word {
                        let refTable = item[p].text; p += 1
                        skipParens(item, &p)
                        keys.append(.foreign); fks.append((name, refTable))
                    }
                    continue
                default: break
                }
            }
            p += 1
        }

        upsert(name: name, type: type, keys: keys, into: &attrs, indexOf: &indexOf)
    }

    private func parseTableConstraint(_ item: [SQLTok], into attrs: inout [ERDiagram.Attribute],
                                      indexOf: [String: Int], fks: inout [(col: String, refTable: String)]) {
        var p = 0
        if p < item.count, item[p].word, item[p].text.lowercased() == "constraint" {
            p += 1
            if p < item.count, item[p].word { p += 1 }   // skip the constraint name
        }
        guard p < item.count, item[p].word else { return }
        switch item[p].text.lowercased() {
        case "primary":
            p += 1
            if p < item.count, item[p].word, item[p].text.lowercased() == "key" { p += 1 }
            for col in parenCols(item, &p) { addKey(.primary, to: col, in: &attrs, indexOf: indexOf) }
        case "unique":
            p += 1
            for col in parenCols(item, &p) { addKey(.unique, to: col, in: &attrs, indexOf: indexOf) }
        case "foreign":
            p += 1
            if p < item.count, item[p].word, item[p].text.lowercased() == "key" { p += 1 }
            let cols = parenCols(item, &p)
            if p < item.count, item[p].word, item[p].text.lowercased() == "references", p + 1 < item.count, item[p + 1].word {
                p += 1
                let refTable = item[p].text; p += 1
                skipParens(item, &p)
                for col in cols { addKey(.foreign, to: col, in: &attrs, indexOf: indexOf); fks.append((col, refTable)) }
            }
        default:
            break   // KEY / INDEX / CHECK / EXCLUDE — ignored
        }
    }

    // MARK: attribute mutation

    private func upsert(name: String, type: String, keys: [ERDiagram.Attribute.Key],
                        into attrs: inout [ERDiagram.Attribute], indexOf: inout [String: Int]) {
        if let idx = indexOf[name] {
            attrs[idx] = ERDiagram.Attribute(type: attrs[idx].type.isEmpty ? type : attrs[idx].type,
                                             name: name, keys: mergeKeys(attrs[idx].keys, keys))
        } else {
            indexOf[name] = attrs.count
            attrs.append(ERDiagram.Attribute(type: type, name: name, keys: keys))
        }
    }

    private func addKey(_ key: ERDiagram.Attribute.Key, to col: String,
                        in attrs: inout [ERDiagram.Attribute], indexOf: [String: Int]) {
        guard let idx = indexOf[col] else { return }
        attrs[idx] = ERDiagram.Attribute(type: attrs[idx].type, name: attrs[idx].name,
                                         keys: mergeKeys(attrs[idx].keys, [key]))
    }

    private func mergeKeys(_ a: [ERDiagram.Attribute.Key], _ b: [ERDiagram.Attribute.Key]) -> [ERDiagram.Attribute.Key] {
        var out = a
        for k in b where !out.contains(k) { out.append(k) }
        return out
    }

    // MARK: relations

    private func addRelation(from parent: String, to child: String) {
        let key = "\(parent)->\(child)"
        guard !relSeen.contains(key), parent != child else { return }
        relSeen.insert(key)
        // A foreign key is one parent to zero-or-more children.
        relations.append(ERDiagram.Relation(from: parent, to: child,
                                            fromCard: .one, toCard: .zeroOrMore,
                                            label: "", identifying: false))
    }

    // MARK: token scanning within an item

    /// Reads a `( a, b, c )` column list, advancing `p` past the close paren.
    private func parenCols(_ item: [SQLTok], _ p: inout Int) -> [String] {
        guard p < item.count, !item[p].word, item[p].text == "(" else { return [] }
        p += 1
        var cols: [String] = []
        while p < item.count {
            let tk = item[p]
            if !tk.word, tk.text == ")" { p += 1; break }
            if !tk.word, tk.text == "," { p += 1; continue }
            if tk.word { cols.append(tk.text) }
            p += 1
        }
        return cols
    }

    /// Skips a balanced `( … )` group when present.
    private func skipParens(_ item: [SQLTok], _ p: inout Int) {
        guard p < item.count, !item[p].word, item[p].text == "(" else { return }
        var d = 0
        while p < item.count {
            let tk = item[p]
            if !tk.word, tk.text == "(" { d += 1 }
            if !tk.word, tk.text == ")" { d -= 1; p += 1; if d == 0 { return }; continue }
            p += 1
        }
    }

    private func skipStatement() {
        while i < t.count, !(!t[i].word && t[i].text == ";") { i += 1 }
        if i < t.count { i += 1 }
    }
}
