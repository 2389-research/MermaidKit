import Foundation

/// The explicit, language-neutral wire form of a ``RenderTheme`` — the JSON a
/// caller passes across the C ABI (`mmk_scene_json_themed`) to theme a scene
/// with its own colors instead of a built-in light/dark preset.
///
/// Like ``SceneWire``, it's a flat, self-describing schema every language emits
/// with plain data classes: colors are `#RRGGBBAA` strings (8-bit — what every
/// raster backend draws at), and `prefersDark` carries the dark-canvas flag a
/// few tints key off. The Android side builds one from a Material `ColorScheme`
/// (`MermaidTheme.fromMaterial`); a plugin or any other consumer can build one
/// however it likes.
public struct ThemeWire: Codable, Sendable, Equatable {
    /// Primary text + stroke color (node borders, arrows, node labels).
    public var ink: String
    /// Highlight color; node fills use it at low alpha.
    public var accent: String
    /// The diagram background fill.
    public var canvas: String
    /// Thin rules — sequence box-band borders, fragment tabs.
    public var hairline: String
    /// De-emphasized text — the color edge labels wear.
    public var secondaryText: String
    /// Most-de-emphasized text — fragment guards, note captions.
    public var tertiaryText: String
    /// Categorical hues, cycled by index (sequence box bands, note fills, etc.).
    public var palette: [String]
    /// Whether the theme targets a dark canvas.
    public var prefersDark: Bool

    public init(ink: String, accent: String, canvas: String, hairline: String,
                secondaryText: String, tertiaryText: String,
                palette: [String], prefersDark: Bool) {
        self.ink = ink
        self.accent = accent
        self.canvas = canvas
        self.hairline = hairline
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.palette = palette
        self.prefersDark = prefersDark
    }

    /// Errors from reconstructing a ``RenderTheme`` — a malformed color string.
    public enum DecodeError: Error, Equatable {
        case badColor(String)
    }

    /// Build the platform-free ``RenderTheme`` the layout engine paints with,
    /// parsing each `#RRGGBBAA` color. Throws ``DecodeError/badColor(_:)`` on a
    /// malformed color.
    public func renderTheme() throws -> RenderTheme {
        func color(_ s: String) throws -> DiagramColor {
            guard let c = DiagramColor(hexString: s) else { throw DecodeError.badColor(s) }
            return c
        }
        return RenderTheme(
            ink: try color(ink),
            accent: try color(accent),
            canvas: try color(canvas),
            hairline: try color(hairline),
            secondaryText: try color(secondaryText),
            tertiaryText: try color(tertiaryText),
            palette: try palette.map(color),
            prefersDark: prefersDark)
    }

    /// Project an existing ``RenderTheme`` to its wire form (round-trips with
    /// ``renderTheme()`` modulo 8-bit color quantization) — used by tests and any
    /// producer that already has a `RenderTheme`.
    public init(_ theme: RenderTheme) {
        func hex(_ c: DiagramColor) -> String { "#" + c.hexString }
        self.init(
            ink: hex(theme.ink),
            accent: hex(theme.accent),
            canvas: hex(theme.canvas),
            hairline: hex(theme.hairline),
            secondaryText: hex(theme.secondaryText),
            tertiaryText: hex(theme.tertiaryText),
            palette: theme.palette.map(hex),
            prefersDark: theme.prefersDark)
    }
}
