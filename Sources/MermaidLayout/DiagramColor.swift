import Foundation

/// A platform-free color value: sRGB components in 0...1. This is the color
/// currency for anything that must work without AppKit/UIKit — future
/// backends (SVG, draw-list goldens) and theme fingerprints consume these,
/// while `MermaidRender`'s `DiagramTheme` keeps its platform colors for
/// CoreGraphics drawing and exposes its `resolved` counterpart built from
/// this type.
public struct DiagramColor: Hashable, Sendable, Codable {
    /// Red component, sRGB 0...1.
    public var red: Double
    /// Green component, sRGB 0...1.
    public var green: Double
    /// Blue component, sRGB 0...1.
    public var blue: Double
    /// Opacity, 0...1.
    public var alpha: Double

    /// Component-wise initializer; values are clamped to 0...1.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    /// From a 24-bit `0xRRGGBB` value, e.g. `DiagramColor(hex: 0x5B8FF9)`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha)
    }

    /// Uppercase `RRGGBBAA` — the canonical digest form used in theme
    /// fingerprints, and directly usable in SVG/CSS as `#RRGGBBAA`.
    public var hexString: String {
        String(format: "%02X%02X%02X%02X",
               Int((red * 255).rounded()), Int((green * 255).rounded()),
               Int((blue * 255).rounded()), Int((alpha * 255).rounded()))
    }

    /// A copy with a different opacity (clamped to 0...1).
    public func withAlpha(_ value: Double) -> DiagramColor {
        DiagramColor(red: red, green: green, blue: blue, alpha: value)
    }

    /// Parse the inverse of `hexString`: `RRGGBBAA` or `RRGGBB` (a leading `#`
    /// is tolerated; a 6-digit form is fully opaque). Returns nil on any other
    /// length or a non-hex digit. This is the wire form's color decoder —
    /// symmetric with `hexString` so `SceneWire` round-trips.
    public init?(hexString: String) {
        var s = Substring(hexString)
        if s.first == "#" { s = s.dropFirst() }
        guard s.count == 6 || s.count == 8,
              let value = UInt32(s, radix: 16) else { return nil }
        if s.count == 8 {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255)
        } else {
            self.init(hex: value)
        }
    }
}
