import Foundation

// Tier 3: half-block truecolor raster. Each character cell is the upper-half
// block "▀" with the FOREGROUND set to the top pixel and the BACKGROUND set to
// the bottom pixel, both as 24-bit SGR. That packs a 1-wide × 2-tall full-color
// pixel pair into every cell — a near-photographic image in any truecolor
// terminal, with no graphics protocol.
//
// This file is deliberately graphics-free (no CoreGraphics): it maps an
// already-decoded RGBA pixel grid to the ANSI byte stream, so the pixel→SGR
// mapping is unit-testable headless. The raster itself (PNG → RGBA downsample)
// is produced by `MermaidRenderer.rgbaRaster` in the render module.

/// A straight-alpha 8-bit-per-channel pixel.
public struct RGBA: Equatable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    /// From a `0xRRGGBB` literal (fully opaque).
    public init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }
}

public enum HalfBlockRenderer {
    /// The single glyph every cell draws: the upper half block.
    public static let upperHalf: Character = "▀"

    /// Composite a straight-alpha pixel over an opaque background.
    static func composite(_ px: RGBA, over bg: RGBA) -> (r: UInt8, g: UInt8, b: UInt8) {
        switch px.a {
        case 255: return (px.r, px.g, px.b)
        case 0:   return (bg.r, bg.g, bg.b)
        default:
            let a = Double(px.a) / 255.0
            func mix(_ f: UInt8, _ b: UInt8) -> UInt8 {
                UInt8((Double(f) * a + Double(b) * (1 - a)).rounded())
            }
            return (mix(px.r, bg.r), mix(px.g, bg.g), mix(px.b, bg.b))
        }
    }

    /// The SGR sequence + glyph for ONE cell: `▀` with fg = top pixel and
    /// bg = bottom pixel (each composited over `background`). Both channels ride
    /// a single `38;2;…;48;2;…` SGR so the cell is one escape + one glyph.
    ///
    /// When both pixels are fully transparent the cell blends with the terminal
    /// instead: reset SGR + a space, so image margins take the terminal's own
    /// background rather than a painted rectangle.
    public static func cell(top: RGBA, bottom: RGBA, over background: RGBA) -> String {
        if top.a == 0 && bottom.a == 0 { return "\u{1B}[0m " }
        let t = composite(top, over: background)
        let b = composite(bottom, over: background)
        return "\u{1B}[38;2;\(t.r);\(t.g);\(t.b);48;2;\(b.r);\(b.g);\(b.b)m▀"
    }

    /// Render a row-major RGBA grid (`width` × `height`) as half-block rows.
    /// Consumes two pixel rows per text row (top → fg, bottom → bg); an odd
    /// final row pairs against `background`. Every line ends with a `\u{1B}[0m`
    /// reset so no color leaks past the row.
    public static func render(pixels: [RGBA], width: Int, height: Int,
                              background: RGBA) -> String {
        guard width > 0, height > 0, pixels.count >= width * height else { return "" }
        var lines: [String] = []
        lines.reserveCapacity((height + 1) / 2)
        var row = 0
        while row < height {
            var line = ""
            line.reserveCapacity(width * 24)
            for c in 0..<width {
                let top = pixels[row * width + c]
                let bottom = (row + 1 < height) ? pixels[(row + 1) * width + c] : background
                line += cell(top: top, bottom: bottom, over: background)
            }
            line += "\u{1B}[0m"
            lines.append(line)
            row += 2
        }
        return lines.joined(separator: "\n")
    }
}
