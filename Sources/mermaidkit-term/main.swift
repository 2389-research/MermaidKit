import Foundation
import MermaidLayout
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import MermaidRender
#endif

// mermaidkit-term — a demo CLI that renders a Mermaid flowchart into the
// terminal using the capability ladder from
// docs/notes/terminal-rendering-capabilities.md:
//
//   kitty-graphics (real image) → colored box-drawing → plain box-drawing
//
// Read a source from a file argument or stdin. Flowchart-scoped for this
// iteration (matches the ASCII POC).

// MARK: - Argument parsing

struct Options {
    var mode: String = "auto"          // kitty | halfblock | box | plain | auto
    var format: String = "auto"        // mermaid | dot | auto
    var color: ColorPreference = .auto // auto | always | never
    var theme: ThemePreference = .auto // auto | dark | light
    var width: Int?                    // halfblock target columns (nil → detect)
    var path: String?                  // nil → read stdin
    var help = false
}

func parseArgs(_ argv: [String]) -> Options? {
    var o = Options()
    var i = 0
    let args = Array(argv.dropFirst())
    while i < args.count {
        let a = args[i]
        func value(after flag: String) -> String? {
            if let eq = a.firstIndex(of: "=") { return String(a[a.index(after: eq)...]) }
            i += 1
            return i < args.count ? args[i] : nil
        }
        switch true {
        case a == "-h" || a == "--help":
            o.help = true
        case a == "--mode" || a.hasPrefix("--mode="):
            guard let v = value(after: "--mode") else { return nil }
            o.mode = v
        case a == "--format" || a.hasPrefix("--format="):
            guard let v = value(after: "--format"),
                  ["mermaid", "dot", "auto"].contains(v) else { return nil }
            o.format = v
        case a == "--color" || a.hasPrefix("--color="):
            guard let v = value(after: "--color"), let c = ColorPreference(rawValue: v) else { return nil }
            o.color = c
        case a == "--theme" || a.hasPrefix("--theme="):
            guard let v = value(after: "--theme"), let t = ThemePreference(rawValue: v) else { return nil }
            o.theme = t
        case a == "--width" || a.hasPrefix("--width="):
            guard let v = value(after: "--width"), let n = Int(v), n > 0 else { return nil }
            o.width = n
        case a.hasPrefix("-"):
            FileHandle.standardError.write(Data("unknown flag: \(a)\n".utf8))
            return nil
        default:
            o.path = a
        }
        i += 1
    }
    return o
}

let usage = """
mermaidkit-term — render a Mermaid flowchart to the terminal

USAGE:
  mermaidkit-term [FILE] [--mode kitty|halfblock|box|plain|auto] [--width COLS]
                  [--format mermaid|dot|auto]
                  [--color auto|always|never] [--theme auto|dark|light]
  cat diagram.mmd | mermaidkit-term --mode halfblock --width 100
  cat pipeline.dot | mermaidkit-term --format dot --mode plain

FORMAT (--format): auto detects Graphviz DOT by a .dot/.gv file extension or a
  leading strict/graph/digraph … { content sniff, else parses Mermaid. DOT is
  parsed to the same Flowchart IR, so every mode renders it.

MODES (capability ladder):
  auto      detect: kitty-graphics if Kitty/Ghostty, else half-block if truecolor, else plain
  kitty     real PNG render, inline via the Kitty graphics protocol (Kitty/Ghostty)
  halfblock truecolor half-block raster: "▀" cells, fg = top pixel, bg = bottom
            pixel — a near-photographic image in any 24-bit terminal, no protocol
  box       structured Unicode box-drawing (colored per --color)
  plain     box-drawing, never colored

WIDTH (--width): half-block target columns. Default detects the terminal width
  (TIOCGWINSZ, then $COLUMNS), falling back to 100.

COLOR (--color): auto = on when stdout is a TTY and $COLORTERM is truecolor/24bit.

THEME (--theme): auto detects the terminal background (OSC 11 query on /dev/tty,
  then $COLORFGBG, then a dark default). Dark backgrounds get a brightened
  structure palette and the dark PNG theme; light backgrounds keep the deep teal.

PALETTE MAPPING (mermaid palette → element):
  seafoam  #39D6C5  node borders + labels
  lavender #C9B6FF  decision nodes (borders + label)
  structure         edges + subgraph boxes — deep teal #123C4A on light,
                    brightened to #2FA39B on dark
  coral    #FF8FA3  arrowheads + edge captions
"""

// MARK: - Main

func run() -> Int32 {
    guard let opts = parseArgs(CommandLine.arguments) else {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        return 2
    }
    if opts.help {
        print(usage)
        return 0
    }

    // Read source.
    let source: String
    if let path = opts.path {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
            return 1
        }
        source = text
    } else {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        source = String(data: data, encoding: .utf8) ?? ""
    }
    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        FileHandle.standardError.write(Data("no input (pass a FILE or pipe via stdin)\n".utf8))
        return 1
    }

    // Resolve the input format. DOT is parsed up-front to the shared Flowchart
    // IR so every render mode below drives the same pipeline as Mermaid.
    let isDOT: Bool
    switch opts.format {
    case "dot":     isDOT = true
    case "mermaid": isDOT = false
    default:        isDOT = looksLikeDOT(source, path: opts.path)  // auto
    }
    var dotDiagram: MermaidDiagram?
    if isDOT {
        guard let chart = DOTParser.parse(source) else {
            FileHandle.standardError.write(Data("could not parse DOT source\n".utf8))
            return 1
        }
        dotDiagram = .flowchart(chart)
    }

    let env = TerminalEnvironment.current()
    let background = TerminalCapabilities.detectBackground(theme: opts.theme, env: env)

    // Resolve the mode.
    let mode: TerminalRenderMode
    switch opts.mode {
    case "auto":      mode = TerminalCapabilities.autoMode(env)
    case "kitty":     mode = .kitty
    case "halfblock": mode = .halfBlock
    case "box":       mode = TerminalCapabilities.useColor(opts.color, env) ? .coloredBox : .plainBox
    case "plain":     mode = .plainBox
    default:
        FileHandle.standardError.write(Data("unknown --mode \(opts.mode)\n".utf8))
        return 2
    }

    switch mode {
    case .kitty:
        return renderKitty(source, diagram: dotDiagram, background: background)
    case .halfBlock:
        return renderHalfBlock(source, diagram: dotDiagram, background: background,
                               requestedWidth: opts.width)
    case .coloredBox, .plainBox:
        let colorOn = (mode == .coloredBox)
        let color: ASCIIColorMode = colorOn ? .truecolor : .plain
        let out: String?
        if case .flowchart(let chart)? = dotDiagram {
            out = ASCIIRenderer.asciiRenderFlowchart(chart, color: color, background: background)
        } else {
            out = ASCIIRenderer.asciiRenderFlowchart(source, color: color, background: background)
        }
        guard let rendered = out else {
            FileHandle.standardError.write(Data("not a flowchart (this demo is flowchart-scoped)\n".utf8))
            return 1
        }
        print(rendered)
        return 0
    }
}

/// Sniffs whether a source is Graphviz DOT: a `.dot`/`.gv` extension, or a
/// leading (`strict`) `graph`/`digraph` … `{` once comments/whitespace are
/// skipped. Mermaid's own `graph`/`flowchart` headers are NOT followed by `{`,
/// so they never trip this.
func looksLikeDOT(_ source: String, path: String?) -> Bool {
    if let path = path {
        let lower = path.lowercased()
        if lower.hasSuffix(".dot") || lower.hasSuffix(".gv") { return true }
        if lower.hasSuffix(".mmd") || lower.hasSuffix(".mermaid") { return false }
    }
    // Content sniff. Drop block comments, then read the first meaningful line's
    // leading keyword. `digraph` is DOT-exclusive. For `graph` (which Mermaid
    // also uses) a Mermaid direction token settles it; otherwise a `{` on the
    // header line marks DOT. This avoids reading a fused Mermaid node label like
    // `A{decision}` (which sits on a body line) as a DOT brace.
    var s = source
    while let open = s.range(of: "/*"), let close = s.range(of: "*/", range: open.upperBound..<s.endIndex) {
        s.replaceSubrange(open.lowerBound..<close.upperBound, with: " ")
    }
    let lines = s.split(separator: "\n").map { line -> String in
        if let c = line.range(of: "//") { return String(line[line.startIndex..<c.lowerBound]) }
        return String(line)
    }
    guard let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    else { return false }
    let lower = firstLine.trimmingCharacters(in: .whitespaces).lowercased()
    var words = lower.split(whereSeparator: { " \t;,".contains($0) }).map(String.init)
    if words.first == "strict" { words.removeFirst() }
    guard let first = words.first else { return false }
    if first == "digraph" { return true }           // DOT-only keyword
    guard first == "graph" else { return false }     // else Mermaid (flowchart, …)
    let directions: Set<String> = ["td", "tb", "lr", "rl", "bt"]
    if let second = words.dropFirst().first, directions.contains(second) { return false }
    return firstLine.contains("{")                   // `graph { … }` header → DOT
}

/// Tier 1: rasterize the diagram to PNG and stream it via the Kitty graphics
/// protocol. Falls back to a colored box render if the rasterizer is
/// unavailable or the source doesn't render.
func renderKitty(_ source: String, diagram: MermaidDiagram?,
                 background: TerminalBackground) -> Int32 {
    #if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
    let theme = DiagramTheme(prefersDark: background == .dark)
    let png = diagram.flatMap { MermaidRenderer.pngData(diagram: $0, theme: theme) }
        ?? MermaidRenderer.pngData(source: source, theme: theme)
    if let png {
        FileHandle.standardOutput.write(Data(KittyGraphics.encode(pngData: png).utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
        return 0
    }
    FileHandle.standardError.write(Data("could not rasterize; falling back to box render\n".utf8))
    #else
    FileHandle.standardError.write(Data("kitty mode needs the raster backend; falling back to box render\n".utf8))
    #endif
    return fallbackBox(source, diagram: diagram, background: background)
}

/// Shared box-render fallback for the raster tiers, honoring a pre-parsed DOT
/// diagram when present.
func fallbackBox(_ source: String, diagram: MermaidDiagram?,
                 background: TerminalBackground) -> Int32 {
    let out: String?
    if case .flowchart(let chart)? = diagram {
        out = ASCIIRenderer.asciiRenderFlowchart(chart, color: .truecolor, background: background)
    } else {
        out = ASCIIRenderer.asciiRenderFlowchart(source, color: .truecolor, background: background)
    }
    if let out { print(out); return 0 }
    return 1
}

/// Best-effort terminal column count: the live window size (TIOCGWINSZ), then
/// `$COLUMNS`, else nil (the caller defaults).
func terminalColumns() -> Int? {
    var ws = winsize()
    if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0 {
        return Int(ws.ws_col)
    }
    if let cols = ProcessInfo.processInfo.environment["COLUMNS"], let n = Int(cols), n > 0 {
        return n
    }
    return nil
}

/// Tier 3: rasterize the diagram and paint it as truecolor half-blocks. The
/// resolved grid size is reported on stderr (so stdout stays a clean ANSI
/// stream that can be redirected to a file). Falls back to the colored box
/// render when the raster backend is unavailable or the source doesn't render.
func renderHalfBlock(_ source: String, diagram: MermaidDiagram?,
                     background: TerminalBackground, requestedWidth: Int?) -> Int32 {
    let cols = max(10, min(requestedWidth ?? terminalColumns() ?? 100, 400))
    let prefersDark = (background == .dark)
    // The theme canvas colors from DiagramTheme(prefersDark:) — margins blend.
    let bg: (r: UInt8, g: UInt8, b: UInt8) =
        prefersDark ? (0x1B, 0x1B, 0x1D) : (0xFF, 0xFF, 0xFF)

    #if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
    let theme = DiagramTheme(prefersDark: prefersDark)
    let maybeRaster = diagram.flatMap {
        MermaidRenderer.rgbaRaster(diagram: $0, theme: theme, targetWidth: cols, background: bg)
    } ?? MermaidRenderer.rgbaRaster(source: source, theme: theme, targetWidth: cols, background: bg)
    if let raster = maybeRaster {
        var pixels = [RGBA]()
        pixels.reserveCapacity(raster.width * raster.height)
        let b = raster.pixels
        var i = 0
        while i + 3 < b.count {
            pixels.append(RGBA(b[i], b[i + 1], b[i + 2], b[i + 3]))
            i += 4
        }
        let ansi = HalfBlockRenderer.render(
            pixels: pixels, width: raster.width, height: raster.height,
            background: RGBA(bg.r, bg.g, bg.b))
        let sizeNote = "half-block grid: \(raster.width) cols × \(raster.height / 2) rows "
            + "(\(raster.width)×\(raster.height) pixels), background \(background)\n"
        FileHandle.standardError.write(Data(sizeNote.utf8))
        print(ansi)
        return 0
    }
    FileHandle.standardError.write(Data("could not rasterize; falling back to box render\n".utf8))
    #else
    FileHandle.standardError.write(Data("halfblock mode needs the raster backend; falling back to box render\n".utf8))
    #endif
    return fallbackBox(source, diagram: diagram, background: background)
}

exit(run())
