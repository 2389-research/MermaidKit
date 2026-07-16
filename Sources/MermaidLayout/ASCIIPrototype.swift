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

// MARK: - Truecolor (Tier 4 palette)

/// A 24-bit sRGB color emitted as an ANSI `SGR 38;2;r;g;b` foreground sequence.
public struct ANSIColor: Equatable, Sendable {
    public let r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    /// From a `0xRRGGBB` literal.
    public init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }
    var setForeground: String { "\u{1B}[38;2;\(r);\(g);\(b)m" }
    static let reset = "\u{1B}[0m"
}

/// The mermaid palette, and how each diagram element maps onto it. The user
/// runs the colored output (this process can't see it), so the mapping is
/// documented here and mirrored in the demo CLI's `--help`.
public enum MermaidPalette {
    public static let deepTeal = ANSIColor(hex: 0x123C4A)   // muted structure (light bg)
    /// Structure color lifted toward the seafoam/aqua for dark terminals: the
    /// deep teal (#123C4A) is nearly invisible on black, so edges + subgraph
    /// boxes use this brighter teal when the background is dark.
    public static let brightTeal = ANSIColor(hex: 0x2FA39B)
    public static let seafoam  = ANSIColor(hex: 0x39D6C5)   // node borders/labels
    public static let coral    = ANSIColor(hex: 0xFF8FA3)   // arrowheads/highlights
    public static let lavender = ANSIColor(hex: 0xC9B6FF)   // decision nodes

    /// Border + label color for a node of the given shape.
    static func nodeColor(_ shape: Flowchart.NodeShape) -> ANSIColor {
        shape == .diamond ? lavender : seafoam
    }
    /// Structure color (edges + subgraph boxes), brightened on dark backgrounds
    /// and kept as the deep teal on light ones.
    static func structureColor(background: TerminalBackground) -> ANSIColor {
        background == .dark ? brightTeal : deepTeal
    }
    static let arrowColor = coral          // arrowheads: highlight
    static let labelColor = coral          // edge captions / free labels
}

/// How the renderer colors its output. `plain` emits no escapes at all.
public enum ASCIIColorMode: Sendable { case plain, truecolor }

// MARK: - Bit-plane canvas

/// A character grid painted with the bit-mask technique. Edges never place a
/// glyph directly; they OR direction bits (Up/Down/Left/Right) into cells, and
/// at finalize each cell's 4-bit mask resolves to the one box-drawing glyph that
/// has exactly those arms. Crossings and T-junctions then fall out for free.
///
/// A parallel per-cell foreground-color plane rides alongside so the same grid
/// can emit either plain Unicode or Tier-4 truecolor.
final class Canvas {
    struct Dir {
        static let up: UInt8 = 1
        static let down: UInt8 = 2
        static let left: UInt8 = 4
        static let right: UInt8 = 8
    }

    let cols: Int
    let rows: Int
    let colorMode: ASCIIColorMode
    /// Per-cell direction mask (the bit plane the edges/borders write into).
    private var mask: [UInt8]
    /// Per-cell hard glyph override (labels, arrowheads) — wins over the mask.
    private var glyph: [Character?]
    /// Per-cell "occupied by a solid box" plane. Edge bits dropped on reserved
    /// cells, so a wire can never draw through a node interior or border.
    private var reserved: [Bool]
    /// Per-cell foreground color (truecolor plane). nil = terminal default.
    private var fg: [ANSIColor?]

    init(cols: Int, rows: Int, colorMode: ASCIIColorMode = .plain) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        self.colorMode = colorMode
        let n = self.cols * self.rows
        mask = Array(repeating: 0, count: n)
        glyph = Array(repeating: nil, count: n)
        reserved = Array(repeating: false, count: n)
        fg = Array(repeating: nil, count: n)
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

    private func paint(_ r: Int, _ c: Int, _ color: ANSIColor?) {
        guard let color, inBounds(r, c) else { return }
        fg[idx(r, c)] = color
    }

    /// OR direction bits into a cell's mask (dropped if the cell is reserved,
    /// unless `force` — node borders are drawn with force so the box outline
    /// survives its own reservation).
    func addBits(_ r: Int, _ c: Int, _ bits: UInt8, force: Bool = false, color: ANSIColor? = nil) {
        guard inBounds(r, c) else { return }
        if reserved[idx(r, c)] && !force { return }
        mask[idx(r, c)] |= bits
        paint(r, c, color)
    }

    func setGlyph(_ r: Int, _ c: Int, _ ch: Character, color: ANSIColor? = nil) {
        guard inBounds(r, c) else { return }
        glyph[idx(r, c)] = ch
        paint(r, c, color)
    }

    /// Erase a cell's routing mask + color (only if no hard glyph occupies it),
    /// so the cell resolves to a blank. Used to punch a clean gap beside an edge
    /// caption so a corner/line glyph never abuts the text (`no┘` → `no ┘`).
    func clearMask(_ r: Int, _ c: Int) {
        guard inBounds(r, c), glyph[idx(r, c)] == nil else { return }
        mask[idx(r, c)] = 0
        fg[idx(r, c)] = nil
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

    /// The resolved glyph at a cell (hard override, else mask glyph, else space).
    private func resolved(_ r: Int, _ c: Int) -> Character {
        if let g = glyph[idx(r, c)] { return g }
        let m = mask[idx(r, c)]
        return m == 0 ? " " : glyphForMask(m)
    }

    func render() -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows)
        for r in 0..<rows {
            // Find the last non-blank column so trailing padding (and its color
            // runs) are dropped without leaving a dangling escape.
            var lastCol = -1
            for c in 0..<cols where resolved(r, c) != " " { lastCol = c }
            guard lastCol >= 0 else { lines.append(""); continue }

            var line = ""
            var active: ANSIColor? = nil
            for c in 0...lastCol {
                let ch = resolved(r, c)
                if colorMode == .truecolor {
                    // Spaces carry no color; close any open run over a gap.
                    let want: ANSIColor? = (ch == " ") ? nil : fg[idx(r, c)]
                    if want != active {
                        if want == nil { line += ANSIColor.reset }
                        else { line += want!.setForeground }
                        active = want
                    }
                }
                line.append(ch)
            }
            if colorMode == .truecolor && active != nil { line += ANSIColor.reset }
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
    /// for non-flowchart sources (POC scope). `color` selects plain Unicode or
    /// Tier-4 truecolor.
    public static func asciiRenderFlowchart(_ source: String,
                                            color: ASCIIColorMode = .plain,
                                            background: TerminalBackground = .dark) -> String? {
        guard let diagram = MermaidParser.parse(source) else { return nil }
        guard case .flowchart(let chart) = diagram else { return nil }
        return asciiRenderFlowchart(chart, color: color, background: background)
    }

    /// Render an already-parsed `Flowchart` (e.g. from `DOTParser`) through the
    /// same lower → quantize → draw path as the source-string entry.
    public static func asciiRenderFlowchart(_ chart: Flowchart,
                                            color: ASCIIColorMode = .plain,
                                            background: TerminalBackground = .dark) -> String? {
        // Lay out ONCE, then lower that same layout to the scene. For a
        // flowchart, `DiagramScene.lower(_:measure:)` does exactly this —
        // layout, then `from(_:)` — and injects no title label (a flowchart
        // carries none), so lowering the layout we already hold is
        // behaviour-identical while avoiding a redundant second layout pass.
        let layout = DiagramLayoutEngine.layout(chart, measure: ASCIIMetrics.measurer)
        let scene = DiagramScene.from(layout, measure: ASCIIMetrics.measurer)
        // The scene keeps each node's *identifier* (A, B) as its id, having
        // dropped the display label AND shape during lowering. Recover both from
        // the same layout so boxes read "Start" (not "A") and a decision node
        // draws as a diamond (not a rectangle). Geometry still comes wholly from
        // the scene.
        var labelForID: [String: String] = [:]
        var shapeForID: [String: Flowchart.NodeShape] = [:]
        for n in layout.nodes {
            if !n.label.isEmpty { labelForID[n.id] = n.label }
            shapeForID[n.id] = n.shape
        }
        return draw(scene, labelForID: labelForID, shapeForID: shapeForID,
                    color: color, background: background)
    }

    /// Draw an already-lowered flowchart scene. `labelForID`/`shapeForID` supply
    /// human display text and node outline keyed by the scene node's id.
    /// `background` picks the structure color (brightened on dark terminals).
    static func draw(_ scene: DiagramScene,
                     labelForID: [String: String] = [:],
                     shapeForID: [String: Flowchart.NodeShape] = [:],
                     color: ASCIIColorMode = .plain,
                     background: TerminalBackground = .dark) -> String {
        let cols = min(400, col(scene.size.width) + 1)
        let rows = min(400, row(scene.size.height) + 1)
        let canvas = Canvas(cols: cols, rows: rows, colorMode: color)
        let structure = MermaidPalette.structureColor(background: background)

        // 1. Reserve + outline solid node boxes first, so edges drawn later are
        //    dropped over box interiors/borders. Containers only get an outline
        //    (their interior legitimately holds child nodes and their wires).
        for node in scene.nodes {
            let shape = node.isContainer ? nil : shapeForID[node.id]
            drawBox(node, label: labelForID[node.id] ?? node.id, shape: shape,
                    on: canvas, reserveInterior: !node.isContainer, structure: structure)
        }

        // 2. Rasterize edges into the bit plane, then cap them with arrowheads.
        for edge in scene.edges {
            drawEdge(edge, on: canvas, edgeColor: structure)
        }

        // 3. Free-standing labels (edge captions, subgraph headers). Written as
        //    hard glyphs so they read over any wire that passed under them.
        for label in scene.labels {
            let span = place(text: label.text,
                             centerX: label.frame.midX, centerY: label.frame.midY,
                             on: canvas, reserving: false, color: MermaidPalette.labelColor)
            // Edge captions (anchored on their route) often land right next to a
            // routing corner — `no┘`. Punch a one-cell gap on each side of the
            // caption so a corner/line glyph never abuts the text. Only for edge
            // captions: a subgraph header sits ON its container's top border, and
            // clearing its neighbours would leave a hole in that border run.
            if label.anchorEdge != nil, let span {
                canvas.clearMask(span.row, span.startCol - 1)
                canvas.clearMask(span.row, span.endCol + 1)
            }
        }

        return canvas.render()
    }

    // MARK: box

    /// Draw a node box. `shape == nil` (containers) always draws a plain
    /// rectangle; otherwise the outline is styled per shape. Approximations are
    /// deliberate — the goal is that a decision node is unmistakably *not* a
    /// rectangle in a monospace grid.
    private static func drawBox(_ node: DiagramScene.Node, label: String,
                                shape: Flowchart.NodeShape?, on canvas: Canvas,
                                reserveInterior: Bool, structure: ANSIColor) {
        let c0 = col(node.frame.minX), c1 = col(node.frame.maxX)
        let r0 = row(node.frame.minY), r1 = row(node.frame.maxY)
        guard c1 > c0, r1 > r0 else { return }

        let effectiveShape = shape ?? .rectangle
        let stroke = node.isContainer ? structure
                                      : MermaidPalette.nodeColor(effectiveShape)

        // Reserve the whole footprint (interior + border) for solid nodes so no
        // wire can cross them.
        if reserveInterior {
            for r in r0...r1 { for c in c0...c1 { canvas.reserve(r, c) } }
        }

        // Horizontal + vertical edges via the bit mask so corners/junctions join
        // cleanly. `force` because the border cells are themselves reserved.
        for c in (c0 + 1)..<c1 {
            canvas.addBits(r0, c, Canvas.Dir.left | Canvas.Dir.right, force: true, color: stroke)
            canvas.addBits(r1, c, Canvas.Dir.left | Canvas.Dir.right, force: true, color: stroke)
        }
        for r in (r0 + 1)..<r1 {
            canvas.addBits(r, c0, Canvas.Dir.up | Canvas.Dir.down, force: true, color: stroke)
            canvas.addBits(r, c1, Canvas.Dir.up | Canvas.Dir.down, force: true, color: stroke)
        }
        canvas.addBits(r0, c0, Canvas.Dir.down | Canvas.Dir.right, force: true, color: stroke)
        canvas.addBits(r0, c1, Canvas.Dir.down | Canvas.Dir.left, force: true, color: stroke)
        canvas.addBits(r1, c0, Canvas.Dir.up | Canvas.Dir.right, force: true, color: stroke)
        canvas.addBits(r1, c1, Canvas.Dir.up | Canvas.Dir.left, force: true, color: stroke)

        // Shape-specific glyph overrides on corners and side caps.
        styleOutline(effectiveShape, c0: c0, c1: c1, r0: r0, r1: r1, on: canvas, color: stroke)

        // Interior label, centered. For a solid node the id (or recovered label)
        // is its centred text; for a container it's the subgraph header (also
        // lowered as a Label). A `\n` in the label (e.g. a Dippin agent's model
        // subtitle) stacks over the extra interior rows the taller box reserves;
        // lines beyond the interior height are clamped away, never over a border.
        let interiorCols = c1 - c0 - 1
        if reserveInterior, interiorCols > 0 {
            let midR = (r0 + r1) / 2
            let lines = label.components(separatedBy: "\n")
            let interiorRows = max(1, r1 - r0 - 1)
            let shown = min(lines.count, interiorRows)
            let startR = midR - (shown - 1) / 2
            let cx = (c0 + c1) / 2
            for k in 0..<shown {
                place(text: lines[k], centerCol: cx, centerRow: startR + k,
                      maxCols: interiorCols, on: canvas, reserving: false,
                      color: stroke)
            }
        }
    }

    /// Overlay shape-distinguishing glyphs on an already-outlined box.
    private static func styleOutline(_ shape: Flowchart.NodeShape,
                                     c0: Int, c1: Int, r0: Int, r1: Int,
                                     on canvas: Canvas, color: ANSIColor?) {
        let midR = (r0 + r1) / 2
        func corners(_ tl: Character, _ tr: Character, _ bl: Character, _ br: Character) {
            canvas.setGlyph(r0, c0, tl, color: color)
            canvas.setGlyph(r0, c1, tr, color: color)
            canvas.setGlyph(r1, c0, bl, color: color)
            canvas.setGlyph(r1, c1, br, color: color)
        }
        // Replace the vertical border run on each side with an end-cap glyph.
        func sideCaps(_ left: Character, _ right: Character) {
            for r in (r0 + 1)..<r1 {
                canvas.setGlyph(r, c0, left, color: color)
                canvas.setGlyph(r, c1, right, color: color)
            }
            _ = midR
        }
        // Replace the top and bottom border runs with a cap glyph.
        func topBottomCaps(_ ch: Character) {
            for c in (c0 + 1)..<c1 {
                canvas.setGlyph(r0, c, ch, color: color)
                canvas.setGlyph(r1, c, ch, color: color)
            }
        }
        switch shape {
        case .rectangle, .stateStart, .stateEnd:
            break // sharp ┌┐└┘ from the mask is correct
        case .cylinder:
            // Database drum: doubled top/bottom rails (the tool node's outline).
            corners("╒", "╕", "╘", "╛")
            topBottomCaps("═")
        case .rounded:
            corners("╭", "╮", "╰", "╯")
        case .stadium:
            // Pill: rounded corners + parenthesis end-caps.
            corners("╭", "╮", "╰", "╯")
            sideCaps("(", ")")
        case .circle:
            // Rounder: quarter-arc corners + parenthesis sides.
            corners("◜", "◝", "◟", "◞")
            sideCaps("(", ")")
        case .diamond:
            // Decision: a clean hexagon. Sloped top (╱────╲) and bottom
            // (╲────╱) corners with straight │ sides between — unmistakably not
            // a rectangle, and tidy (no repeated chevrons on every row).
            corners("╱", "╲", "╲", "╱")
        case .hexagon:
            // Fork/join cell: the inverse slope of a decision (╲────╱ top,
            // ╱────╲ bottom) so a parallel fan reads apart from a diamond.
            corners("╲", "╱", "╱", "╲")
        case .subroutine:
            // Call to a predefined sub-process: heavy double side rails (the
            // monospace echo of the flowchart `[[ … ]]` box).
            sideCaps("║", "║")
        }
    }

    // MARK: edge

    private static func drawEdge(_ edge: DiagramScene.Edge, on canvas: Canvas,
                                 edgeColor: ANSIColor) {
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
            if b.c > a.c { canvas.addBits(a.r, a.c, Canvas.Dir.right, color: edgeColor); canvas.addBits(b.r, b.c, Canvas.Dir.left, color: edgeColor) }
            else if b.c < a.c { canvas.addBits(a.r, a.c, Canvas.Dir.left, color: edgeColor); canvas.addBits(b.r, b.c, Canvas.Dir.right, color: edgeColor) }
            else if b.r > a.r { canvas.addBits(a.r, a.c, Canvas.Dir.down, color: edgeColor); canvas.addBits(b.r, b.c, Canvas.Dir.up, color: edgeColor) }
            else if b.r < a.r { canvas.addBits(a.r, a.c, Canvas.Dir.up, color: edgeColor); canvas.addBits(b.r, b.c, Canvas.Dir.down, color: edgeColor) }
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
        canvas.setGlyph(head.r, head.c, arrow, color: MermaidPalette.arrowColor)
    }

    // MARK: text placement

    /// The character span a placed label occupies, for callers that need to
    /// tidy the cells around it (see the edge-caption margin clearing).
    struct PlacedSpan { let row: Int; let startCol: Int; let endCol: Int }

    @discardableResult
    private static func place(text: String, centerX: CGFloat, centerY: CGFloat,
                              on canvas: Canvas, reserving: Bool,
                              color: ANSIColor? = nil) -> PlacedSpan? {
        place(text: text, centerCol: col(centerX), centerRow: row(centerY),
              maxCols: displayColumns(text), on: canvas, reserving: reserving,
              color: color)
    }

    @discardableResult
    private static func place(text: String, centerCol: Int, centerRow: Int,
                              maxCols: Int, on canvas: Canvas, reserving: Bool,
                              color: ANSIColor? = nil) -> PlacedSpan? {
        let firstLine = text.components(separatedBy: "\n").first ?? text
        guard !firstLine.isEmpty, maxCols > 0 else { return nil }
        var chars = Array(firstLine)
        if chars.count > maxCols {
            // Truncate with an ellipsis when it doesn't fit.
            if maxCols >= 2 { chars = Array(chars.prefix(maxCols - 1)) + ["…"] }
            else { chars = Array(chars.prefix(maxCols)) }
        }
        let startCol = centerCol - chars.count / 2
        for (i, ch) in chars.enumerated() {
            let c = startCol + i
            canvas.setGlyph(centerRow, c, ch, color: color)
            if reserving { canvas.reserve(centerRow, c) }
        }
        return PlacedSpan(row: centerRow, startCol: startCol,
                          endCol: startCol + chars.count - 1)
    }
}
