import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

/// The perceived lightness of the terminal background. Drives the auto theme
/// (dark vs. light `DiagramTheme`) and palette brightening for the box tier.
public enum TerminalBackground: String, Sendable {
    case dark, light
}

/// Requested terminal theme. `auto` runs the background detector (OSC 11, then
/// `$COLORFGBG`, then a dark default).
public enum ThemePreference: String, Sendable {
    case auto, dark, light
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
    /// `$COLORFGBG` (e.g. `15;0`) — the fallback background hint when OSC 11
    /// gets no reply.
    public var colorFGBG: String?

    public init(term: String? = nil, colorterm: String? = nil, termProgram: String? = nil,
                kittyWindowID: String? = nil, hasGhosttyMarker: Bool = false,
                stdoutIsTTY: Bool = false, colorFGBG: String? = nil) {
        self.term = term
        self.colorterm = colorterm
        self.termProgram = termProgram
        self.kittyWindowID = kittyWindowID
        self.hasGhosttyMarker = hasGhosttyMarker
        self.stdoutIsTTY = stdoutIsTTY
        self.colorFGBG = colorFGBG
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
            stdoutIsTTY: isatty(fileno(stdout)) != 0,
            colorFGBG: env["COLORFGBG"])
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

    // MARK: - Background detection (auto theme)

    /// Resolve a `--theme` preference to a concrete background. `dark`/`light`
    /// are honored verbatim; `auto` queries the terminal via OSC 11 (only when
    /// stdout is a TTY — a piped run has no terminal to answer and must not
    /// stall), falls back to `$COLORFGBG`, and finally defaults to dark.
    public static func detectBackground(theme: ThemePreference,
                                        env: TerminalEnvironment) -> TerminalBackground {
        switch theme {
        case .dark:  return .dark
        case .light: return .light
        case .auto:
            if env.stdoutIsTTY, let bg = queryBackgroundOSC11() { return bg }
            if let cfg = env.colorFGBG, let bg = backgroundFromCOLORFGBG(cfg) { return bg }
            return .dark
        }
    }

    /// Parse an OSC 11 background reply — `…rgb:RRRR/GGGG/BBBB…` with 1–4 hex
    /// digits per channel (any trailing channels ignored) — into channel
    /// intensities in `0...1`. Returns nil when there's no `rgb:` triple.
    public static func parseOSC11Color(_ reply: String) -> (r: Double, g: Double, b: Double)? {
        guard let marker = reply.range(of: "rgb:") else { return nil }
        // Body runs to the first terminator (ST `ESC \` or BEL) or end.
        let body = reply[marker.upperBound...].prefix { $0 != "\u{1b}" && $0 != "\u{07}" }
        let parts = body.split(separator: "/")
        guard parts.count >= 3 else { return nil }
        func channel(_ s: Substring) -> Double? {
            let hex = s.prefix { $0.isHexDigit }
            guard !hex.isEmpty, hex.count <= 4, let v = UInt32(hex, radix: 16) else { return nil }
            return Double(v) / Double((1 << (4 * hex.count)) - 1)
        }
        guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else {
            return nil
        }
        return (r, g, b)
    }

    /// Classify a background color by relative luminance (Rec. 709 weights):
    /// light at/above the midpoint, dark below.
    public static func classifyBackground(r: Double, g: Double, b: Double) -> TerminalBackground {
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance >= 0.5 ? .light : .dark
    }

    /// Fallback classification from `$COLORFGBG` (`fg;bg` or `fg;default;bg`).
    /// The last field is the background palette index; index ≥ 7 (the light
    /// half of the 16-color set) reads as a light terminal.
    public static func backgroundFromCOLORFGBG(_ value: String) -> TerminalBackground? {
        let fields = value.split(separator: ";")
        guard let last = fields.last, let index = Int(last) else { return nil }
        return index >= 7 ? .light : .dark
    }

    /// Query the terminal's background via OSC 11 on `/dev/tty`. Puts the tty in
    /// non-canonical, no-echo mode with the given read deadline, writes the
    /// query, reads the reply (poll-gated so a silent terminal just times out),
    /// then restores the original termios. Returns nil on any failure/timeout.
    public static func queryBackgroundOSC11(timeout: TimeInterval = 0.2) -> TerminalBackground? {
        let fd = open("/dev/tty", O_RDWR)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard isatty(fd) != 0 else { return nil }

        var original = termios()
        guard tcgetattr(fd, &original) == 0 else { return nil }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        guard tcsetattr(fd, TCSANOW, &raw) == 0 else { return nil }
        defer { _ = tcsetattr(fd, TCSANOW, &original) }

        let query = "\u{1b}]11;?\u{1b}\\"
        let wrote: Int = query.withCString { write(fd, $0, strlen($0)) }
        guard wrote > 0 else { return nil }

        func terminated(_ b: [UInt8]) -> Bool {
            if b.contains(0x07) { return true }               // BEL
            guard b.count >= 2 else { return false }
            for i in 1..<b.count where b[i - 1] == 0x1b && b[i] == 0x5c { return true } // ST
            return false
        }

        var reply = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 256)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let remainingMs = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, remainingMs) > 0 else { break }
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { break }
            reply.append(contentsOf: buf[0..<n])
            if terminated(reply) { break }
        }

        guard let text = String(bytes: reply, encoding: .utf8),
              let rgb = parseOSC11Color(text) else { return nil }
        return classifyBackground(r: rgb.r, g: rgb.g, b: rgb.b)
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
