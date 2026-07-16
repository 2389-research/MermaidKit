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
                  [--color auto|always|never] [--theme auto|dark|light]
  cat diagram.mmd | mermaidkit-term --mode halfblock --width 100

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
        return renderKitty(source, background: background)
    case .halfBlock:
        return renderHalfBlock(source, background: background, requestedWidth: opts.width)
    case .coloredBox, .plainBox:
        let colorOn = (mode == .coloredBox)
        guard let out = ASCIIRenderer.asciiRenderFlowchart(
            source, color: colorOn ? .truecolor : .plain, background: background) else {
            FileHandle.standardError.write(Data("not a flowchart (this demo is flowchart-scoped)\n".utf8))
            return 1
        }
        print(out)
        return 0
    }
}

/// Tier 1: rasterize the diagram to PNG and stream it via the Kitty graphics
/// protocol. Falls back to a colored box render if the rasterizer is
/// unavailable or the source doesn't render.
func renderKitty(_ source: String, background: TerminalBackground) -> Int32 {
    #if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
    if let png = MermaidRenderer.pngData(source: source,
                                         theme: DiagramTheme(prefersDark: background == .dark)) {
        FileHandle.standardOutput.write(Data(KittyGraphics.encode(pngData: png).utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
        return 0
    }
    FileHandle.standardError.write(Data("could not rasterize; falling back to box render\n".utf8))
    #else
    FileHandle.standardError.write(Data("kitty mode needs the raster backend; falling back to box render\n".utf8))
    #endif
    if let out = ASCIIRenderer.asciiRenderFlowchart(source, color: .truecolor, background: background) {
        print(out)
        return 0
    }
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
func renderHalfBlock(_ source: String, background: TerminalBackground,
                     requestedWidth: Int?) -> Int32 {
    let cols = max(10, min(requestedWidth ?? terminalColumns() ?? 100, 400))
    let prefersDark = (background == .dark)
    // The theme canvas colors from DiagramTheme(prefersDark:) — margins blend.
    let bg: (r: UInt8, g: UInt8, b: UInt8) =
        prefersDark ? (0x1B, 0x1B, 0x1D) : (0xFF, 0xFF, 0xFF)

    #if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
    if let raster = MermaidRenderer.rgbaRaster(
        source: source, theme: DiagramTheme(prefersDark: prefersDark),
        targetWidth: cols, background: bg) {
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
    if let out = ASCIIRenderer.asciiRenderFlowchart(source, color: .truecolor, background: background) {
        print(out)
        return 0
    }
    return 1
}

exit(run())
