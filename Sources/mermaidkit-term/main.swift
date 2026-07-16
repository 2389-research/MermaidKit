import Foundation
import MermaidLayout
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
    var mode: String = "auto"          // kitty | box | plain | auto
    var color: ColorPreference = .auto // auto | always | never
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
  mermaidkit-term [FILE] [--mode kitty|box|plain|auto] [--color auto|always|never]
  cat diagram.mmd | mermaidkit-term --mode box --color always

MODES (capability ladder):
  auto    detect: kitty-graphics if Kitty/Ghostty, else colored box if truecolor, else plain
  kitty   real PNG render, inline via the Kitty graphics protocol (Kitty/Ghostty)
  box     structured Unicode box-drawing (colored per --color)
  plain   box-drawing, never colored

COLOR (--color): auto = on when stdout is a TTY and $COLORTERM is truecolor/24bit.

PALETTE MAPPING (mermaid palette → element):
  seafoam  #39D6C5  node borders + labels
  lavender #C9B6FF  decision nodes (borders + label)
  deep teal #123C4A edges + subgraph boxes (muted)
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

    // Resolve the mode.
    let mode: TerminalRenderMode
    switch opts.mode {
    case "auto":  mode = TerminalCapabilities.autoMode(env)
    case "kitty": mode = .kitty
    case "box":   mode = TerminalCapabilities.useColor(opts.color, env) ? .coloredBox : .plainBox
    case "plain": mode = .plainBox
    default:
        FileHandle.standardError.write(Data("unknown --mode \(opts.mode)\n".utf8))
        return 2
    }

    switch mode {
    case .kitty:
        return renderKitty(source)
    case .coloredBox, .plainBox:
        let colorOn = (mode == .coloredBox)
        guard let out = ASCIIRenderer.asciiRenderFlowchart(source, color: colorOn ? .truecolor : .plain) else {
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
func renderKitty(_ source: String) -> Int32 {
    #if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
    if let png = MermaidRenderer.pngData(source: source, theme: DiagramTheme(prefersDark: false)) {
        FileHandle.standardOutput.write(Data(KittyGraphics.encode(pngData: png).utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
        return 0
    }
    FileHandle.standardError.write(Data("could not rasterize; falling back to box render\n".utf8))
    #else
    FileHandle.standardError.write(Data("kitty mode needs the raster backend; falling back to box render\n".utf8))
    #endif
    if let out = ASCIIRenderer.asciiRenderFlowchart(source, color: .truecolor) {
        print(out)
        return 0
    }
    return 1
}

exit(run())
