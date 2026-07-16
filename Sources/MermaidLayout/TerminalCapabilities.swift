import Foundation

// Terminal capability detection + the Kitty graphics transport. Pure bytes and
// environment reads — no graphics dependency — so the tier ladder can be
// exercised headless (and the CLI in `Sources/mermaidkit-term` just drives it).

// MARK: - Rendering tiers

/// The output tier chosen from the capability ladder (best fidelity → most
/// portable). See `docs/notes/terminal-rendering-capabilities.md`.
public enum TerminalRenderMode: String, Sendable {
    /// Tier 1: a real raster image inline via the Kitty graphics protocol.
    case kitty
    /// Tier 4: structured Unicode box-drawing, colored from the mermaid palette.
    case coloredBox
    /// Tier 4, monochrome: box-drawing with no ANSI color.
    case plainBox
}

/// Whether ANSI color should be emitted. `auto` resolves against the terminal.
public enum ColorPreference: String, Sendable {
    case auto, always, never
}

/// The subset of environment/TTY facts the detectors need. Injectable so the
/// ladder is unit-testable without a real terminal.
public struct TerminalEnvironment: Sendable {
    public var term: String?
    public var colorterm: String?
    public var termProgram: String?
    public var kittyWindowID: String?
    public var hasGhosttyMarker: Bool
    public var stdoutIsTTY: Bool

    public init(term: String? = nil, colorterm: String? = nil, termProgram: String? = nil,
                kittyWindowID: String? = nil, hasGhosttyMarker: Bool = false,
                stdoutIsTTY: Bool = false) {
        self.term = term
        self.colorterm = colorterm
        self.termProgram = termProgram
        self.kittyWindowID = kittyWindowID
        self.hasGhosttyMarker = hasGhosttyMarker
        self.stdoutIsTTY = stdoutIsTTY
    }

    /// Snapshot the live process environment and stdout TTY state.
    public static func current() -> TerminalEnvironment {
        let env = ProcessInfo.processInfo.environment
        let ghostty = env.keys.contains { $0.hasPrefix("GHOSTTY_") }
        return TerminalEnvironment(
            term: env["TERM"],
            colorterm: env["COLORTERM"],
            termProgram: env["TERM_PROGRAM"],
            kittyWindowID: env["KITTY_WINDOW_ID"],
            hasGhosttyMarker: ghostty,
            stdoutIsTTY: isatty(fileno(stdout)) != 0)
    }
}

public enum TerminalCapabilities {

    /// True when the terminal advertises 24-bit color (`$COLORTERM` contains
    /// `truecolor`/`24bit`). Used both for `--color=auto` and to pick the
    /// colored-box tier over plain.
    public static func supportsTruecolor(_ env: TerminalEnvironment) -> Bool {
        guard let ct = env.colorterm?.lowercased() else { return false }
        return ct.contains("truecolor") || ct.contains("24bit")
    }

    /// Resolve a `--color` preference to a concrete on/off. `auto` = on when
    /// stdout is a TTY and the terminal reports truecolor.
    public static func useColor(_ pref: ColorPreference, _ env: TerminalEnvironment) -> Bool {
        switch pref {
        case .always: return true
        case .never:  return false
        case .auto:   return env.stdoutIsTTY && supportsTruecolor(env)
        }
    }

    /// True when the terminal looks like Kitty or Ghostty — the two engines that
    /// implement the Kitty graphics protocol.
    public static func supportsKittyGraphics(_ env: TerminalEnvironment) -> Bool {
        if let term = env.term, term == "xterm-kitty" || term == "xterm-ghostty" { return true }
        if env.kittyWindowID?.isEmpty == false { return true }
        if env.hasGhosttyMarker { return true }
        if env.termProgram?.lowercased() == "ghostty" { return true }
        return false
    }

    /// The auto ladder: Kitty graphics if available, else colored box when
    /// truecolor is present, else plain box.
    public static func autoMode(_ env: TerminalEnvironment) -> TerminalRenderMode {
        if supportsKittyGraphics(env) { return .kitty }
        if supportsTruecolor(env) { return .coloredBox }
        return .plainBox
    }
}

// MARK: - Kitty graphics protocol (Tier 1 transport)

/// Encodes PNG bytes as a Kitty-graphics escape stream: base64 chunked at 4096
/// bytes, `a=T` (transmit + display), `f=100` (PNG). Every chunk but the last
/// carries `m=1`; the final chunk `m=0`. The control keys `f`/`a` ride only on
/// the first chunk, per the protocol. Emit the result to a Kitty/Ghostty
/// terminal (or `cat` a file containing it) and the image appears inline.
public enum KittyGraphics {

    /// The escape stream for `pngData`. `chunkSize` is the base64 payload cap
    /// per chunk (protocol max is 4096).
    public static func encode(pngData: Data, chunkSize: Int = 4096) -> String {
        let b64 = Array(Data(pngData).base64EncodedString().utf8)
        guard !b64.isEmpty else {
            // Zero-length transmit: a single empty terminator chunk.
            return "\u{1B}_Gf=100,a=T,m=0;\u{1B}\\"
        }
        var out = ""
        var offset = 0
        var first = true
        while offset < b64.count {
            let end = min(offset + chunkSize, b64.count)
            let isLast = end >= b64.count
            let payload = String(decoding: b64[offset..<end], as: UTF8.self)
            let control = first ? "f=100,a=T,m=\(isLast ? 0 : 1)" : "m=\(isLast ? 0 : 1)"
            out += "\u{1B}_G\(control);\(payload)\u{1B}\\"
            first = false
            offset = end
        }
        return out
    }
}
