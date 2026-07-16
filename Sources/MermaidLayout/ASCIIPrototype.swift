import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Monospace text measurer
//
// A POC ASCII/Unicode-box renderer for flowcharts. The elegant part: because
// the SAME monospace measurer drives `DiagramScene.lower`, all the geometry the
// layout engine produces already lands on character-cell multiples (a box that
// is "8 columns wide" is measured as 8*cw points wide, and the layout adds
// cell-multiple padding around it). Quantization then degrades to a rounding
// step, and the orthogonal edge polylines snap cleanly onto grid runs.

/// A character cell is `cw` points wide and `ch` points tall. Terminal cells are
/// about twice as tall as wide, so `ch ≈ 2*cw` keeps the aspect honest: a box
/// the layout thinks is square comes out roughly square on screen.
public enum ASCIIMetrics {
    public static let cw: CGFloat = 7.0
    public static let ch: CGFloat = 14.0
}

/// Display width of a string in monospace columns. POC simplification: one
/// column per grapheme (Character). This is wrong for East-Asian wide glyphs
/// and zero-width joiners, but correct for the ASCII flowcharts we target.
func displayColumns(_ text: String) -> Int {
    text.components(separatedBy: "\n").map { $0.count }.max() ?? 0
}

func lineCount(_ text: String) -> Int {
    max(1, text.components(separatedBy: "\n").count)
}

extension ASCIIMetrics {
    /// The measurer that makes the whole trick work. Layout asks "how big is
    /// this label at font size N" and gets an answer in whole-cell units.
    public static var measurer: DiagramTextMeasurer {
        { text, _ in
            CGSize(width: CGFloat(max(displayColumns(text), 1)) * ASCIIMetrics.cw,
                   height: CGFloat(lineCount(text)) * ASCIIMetrics.ch)
        }
    }
}

// MARK: - Bit-plane canvas

/// A character grid painted with the bit-mask technique. Edges never place a
/// glyph directly; they OR direction bits (Up/Down/Left/Right) into cells, and
/// at finalize each cell's 4-bit mask resolves to the one box-drawing glyph that
/// has exactly those arms. Crossings and T-junctions then fall out for free.
final class Canvas {
    struct Dir {
        static let up: UInt8 = 1
        static let down: UInt8 = 2
        static let left: UInt8 = 4
        static let right: UInt8 = 8
    }

    let cols: Int
    let rows: Int
    /// Per-cell direction mask (the bit plane the edges/borders write into).
    private var mask: [UInt8]
    /// Per-cell hard glyph override (labels, arrowheads) — wins over the mask.
    private var glyph: [Character?]
    /// Per-cell "occupied by a solid box" plane. Edge bits dropped on reserved
    /// cells, so a wire can never draw through a node interior or border.
    private var reserved: [Bool]

    init(cols: Int, rows: Int) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        let n = self.cols * self.rows
        mask = Array(repeating: 0, count: n)
        glyph = Array(repeating: nil, count: n)
        reserved = Array(repeating: false, count: n)
    }

    private func inBounds(_ r: Int, _ c: Int) -> Bool {
        r >= 0 && r < rows && c >= 0 && c < cols
    }
    private func idx(_ r: Int, _ c: Int) -> Int { r * cols + c }

    func reserve(_ r: Int, _ c: Int) {
        guard inBounds(r, c) else { return }
        reserved[idx(r, c)] = true
    }
    func isReserved(_ r: Int, _ c: Int) -> Bool {
        inBounds(r, c) ? reserved[idx(r, c)] : true
    }

    /// OR direction bits into a cell's mask (dropped if the cell is reserved,
    /// unless `force` — node borders are drawn with force so the box outline
    /// survives its own reservation).
    func addBits(_ r: Int, _ c: Int, _ bits: UInt8, force: Bool = false) {
        guard inBounds(r, c) else { return }
        if reserved[idx(r, c)] && !force { return }
        mask[idx(r, c)] |= bits
    }

    func setGlyph(_ r: Int, _ c: Int, _ ch: Character) {
        guard inBounds(r, c) else { return }
        glyph[idx(r, c)] = ch
    }

    /// Map a 4-bit direction mask to its box-drawing glyph.
    private func glyphForMask(_ m: UInt8) -> Character {
        switch m {
        case Dir.down | Dir.right:                       return "┌"
        case Dir.down | Dir.left:                        return "┐"
        case Dir.up | Dir.right:                         return "└"
        case Dir.up | Dir.left:                          return "┘"
        case Dir.up | Dir.down:                          return "│"
        case Dir.left | Dir.right:                       return "─"
        case Dir.up | Dir.down | Dir.right:              return "├"
        case Dir.up | Dir.down | Dir.left:               return "┤"
        case Dir.down | Dir.left | Dir.right:            return "┬"
        case Dir.up | Dir.left | Dir.right:              return "┴"
        case Dir.up | Dir.down | Dir.left | Dir.right:   return "┼"
        // Dangling single arms (an edge stub that got dropped at a reserved
        // neighbour) — draw them as a straight run so nothing floats.
        case Dir.up, Dir.down:                           return "│"
        case Dir.left, Dir.right:                        return "─"
        default:                                         return " "
        }
    }

    func render() -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows)
        for r in 0..<rows {
            var line = ""
            for c in 0..<cols {
                if let g = glyph[idx(r, c)] {
                    line.append(g)
                } else {
                    let m = mask[idx(r, c)]
                    line.append(m == 0 ? " " : glyphForMask(m))
                }
            }
            // Trim trailing spaces.
            while line.hasSuffix(" ") { line.removeLast() }
            lines.append(line)
        }
        // Trim trailing all-blank rows.
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Scene → ASCII

public enum ASCIIRenderer {

    private static func col(_ x: CGFloat) -> Int { Int((x / ASCIIMetrics.cw).rounded()) }
    private static func row(_ y: CGFloat) -> Int { Int((y / ASCIIMetrics.ch).rounded()) }

    /// Parse → lower with the monospace measurer → quantize → draw. Returns nil
    /// for non-flowchart sources (POC scope).
    public static func asciiRenderFlowchart(_ source: String) -> String? {
        guard let diagram = MermaidParser.parse(source) else { return nil }
        guard case .flowchart(let chart) = diagram else { return nil }
        let scene = DiagramScene.lower(diagram, measure: ASCIIMetrics.measurer)
        // The scene keeps each node's *identifier* (A, B) as its id, having
        // dropped the display label during lowering. Recover the id→label map
        // from the same layout so boxes read "Start", not "A". Geometry still
        // comes wholly from the scene.
        let layout = DiagramLayoutEngine.layout(chart, measure: ASCIIMetrics.measurer)
        var labelForID: [String: String] = [:]
        for n in layout.nodes where !n.label.isEmpty { labelForID[n.id] = n.label }
        return draw(scene, labelForID: labelForID)
    }

    /// Draw an already-lowered flowchart scene. `labelForID` supplies human
    /// display text for node boxes keyed by the scene node's id (optional).
    static func draw(_ scene: DiagramScene, labelForID: [String: String] = [:]) -> String {
        let cols = min(400, col(scene.size.width) + 1)
        let rows = min(400, row(scene.size.height) + 1)
        let canvas = Canvas(cols: cols, rows: rows)

        // 1. Reserve + outline solid node boxes first, so edges drawn later are
        //    dropped over box interiors/borders. Containers only get an outline
        //    (their interior legitimately holds child nodes and their wires).
        for node in scene.nodes {
            drawBox(node, label: labelForID[node.id] ?? node.id,
                    on: canvas, reserveInterior: !node.isContainer)
        }

        // 2. Rasterize edges into the bit plane, then cap them with arrowheads.
        for edge in scene.edges {
            drawEdge(edge, on: canvas)
        }

        // 3. Free-standing labels (edge captions, subgraph headers). Written as
        //    hard glyphs so they read over any wire that passed under them.
        for label in scene.labels {
            place(text: label.text,
                  centerX: label.frame.midX, centerY: label.frame.midY,
                  on: canvas, reserving: false)
        }

        return canvas.render()
    }

    // MARK: box

    private static func drawBox(_ node: DiagramScene.Node, label: String, on canvas: Canvas, reserveInterior: Bool) {
        let c0 = col(node.frame.minX), c1 = col(node.frame.maxX)
        let r0 = row(node.frame.minY), r1 = row(node.frame.maxY)
        guard c1 > c0, r1 > r0 else { return }

        // Reserve the whole footprint (interior + border) for solid nodes so no
        // wire can cross them.
        if reserveInterior {
            for r in r0...r1 { for c in c0...c1 { canvas.reserve(r, c) } }
        }

        // Border via the bit mask so corners/junctions join cleanly. `force`
        // because the border cells are themselves reserved.
        for c in (c0 + 1)..<c1 {
            canvas.addBits(r0, c, Canvas.Dir.left | Canvas.Dir.right, force: true)
            canvas.addBits(r1, c, Canvas.Dir.left | Canvas.Dir.right, force: true)
        }
        for r in (r0 + 1)..<r1 {
            canvas.addBits(r, c0, Canvas.Dir.up | Canvas.Dir.down, force: true)
            canvas.addBits(r, c1, Canvas.Dir.up | Canvas.Dir.down, force: true)
        }
        canvas.addBits(r0, c0, Canvas.Dir.down | Canvas.Dir.right, force: true)
        canvas.addBits(r0, c1, Canvas.Dir.down | Canvas.Dir.left, force: true)
        canvas.addBits(r1, c0, Canvas.Dir.up | Canvas.Dir.right, force: true)
        canvas.addBits(r1, c1, Canvas.Dir.up | Canvas.Dir.left, force: true)

        // Interior label. For a solid node the id IS its centred label; for a
        // container it's the subgraph header (lowered separately as a Label too,
        // but drawing it here anchors it inside the box). Skip empty/synthetic.
        let interiorCols = c1 - c0 - 1
        if reserveInterior, interiorCols > 0 {
            let midR = (r0 + r1) / 2
            place(text: label, centerCol: (c0 + c1) / 2, centerRow: midR,
                  maxCols: interiorCols, on: canvas, reserving: false, force: true)
        }
    }

    // MARK: edge

    private static func drawEdge(_ edge: DiagramScene.Edge, on canvas: Canvas) {
        // Snap polyline vertices to cells, then expand into a contiguous cell
        // path (orthogonal L-moves between consecutive vertices).
        let pts = edge.polyline.map { (r: row($0.y), c: col($0.x)) }
        guard pts.count >= 2 else { return }

        var path: [(r: Int, c: Int)] = [pts[0]]
        for k in 1..<pts.count {
            let from = path.last!, to = pts[k]
            // Horizontal leg then vertical leg (flowchart routes are already
            // axis-aligned, so usually only one of these actually moves).
            var cur = from
            while cur.c != to.c {
                cur.c += cur.c < to.c ? 1 : -1
                path.append(cur)
            }
            while cur.r != to.r {
                cur.r += cur.r < to.r ? 1 : -1
                path.append(cur)
            }
        }
        // Drop consecutive duplicates.
        var dedup: [(r: Int, c: Int)] = []
        for p in path where dedup.last.map({ $0 != p }) ?? true { dedup.append(p) }
        guard dedup.count >= 2 else { return }

        // OR reciprocal direction bits for each adjacent pair (dropped on
        // reserved cells, so the run stops at a box border).
        for i in 0..<(dedup.count - 1) {
            let a = dedup[i], b = dedup[i + 1]
            if b.c > a.c { canvas.addBits(a.r, a.c, Canvas.Dir.right); canvas.addBits(b.r, b.c, Canvas.Dir.left) }
            else if b.c < a.c { canvas.addBits(a.r, a.c, Canvas.Dir.left); canvas.addBits(b.r, b.c, Canvas.Dir.right) }
            else if b.r > a.r { canvas.addBits(a.r, a.c, Canvas.Dir.down); canvas.addBits(b.r, b.c, Canvas.Dir.up) }
            else if b.r < a.r { canvas.addBits(a.r, a.c, Canvas.Dir.up); canvas.addBits(b.r, b.c, Canvas.Dir.down) }
        }

        // Arrowhead at the target end: the last non-reserved cell, pointing in
        // the direction of travel into the (reserved) target box.
        var headIdx = dedup.count - 1
        while headIdx > 0 && canvas.isReserved(dedup[headIdx].r, dedup[headIdx].c) {
            headIdx -= 1
        }
        guard headIdx >= 1 else { return }
        let head = dedup[headIdx], prev = dedup[headIdx - 1]
        let arrow: Character
        if head.c > prev.c { arrow = "▶" }
        else if head.c < prev.c { arrow = "◀" }
        else if head.r > prev.r { arrow = "▼" }
        else { arrow = "▲" }
        canvas.setGlyph(head.r, head.c, arrow)
    }

    // MARK: text placement

    private static func place(text: String, centerX: CGFloat, centerY: CGFloat,
                              on canvas: Canvas, reserving: Bool) {
        place(text: text, centerCol: col(centerX), centerRow: row(centerY),
              maxCols: displayColumns(text), on: canvas, reserving: reserving, force: false)
    }

    private static func place(text: String, centerCol: Int, centerRow: Int,
                              maxCols: Int, on canvas: Canvas, reserving: Bool, force: Bool) {
        let firstLine = text.components(separatedBy: "\n").first ?? text
        guard !firstLine.isEmpty, maxCols > 0 else { return }
        var chars = Array(firstLine)
        if chars.count > maxCols {
            // Truncate with an ellipsis when it doesn't fit.
            if maxCols >= 2 { chars = Array(chars.prefix(maxCols - 1)) + ["…"] }
            else { chars = Array(chars.prefix(maxCols)) }
        }
        let startCol = centerCol - chars.count / 2
        for (i, ch) in chars.enumerated() {
            let c = startCol + i
            canvas.setGlyph(centerRow, c, ch)
            if reserving { canvas.reserve(centerRow, c) }
            _ = force
        }
    }
}
