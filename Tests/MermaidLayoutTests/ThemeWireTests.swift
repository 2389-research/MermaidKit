import XCTest
@testable import MermaidLayout

/// Exercises ``ThemeWire`` — the language-neutral theme JSON a caller passes
/// across the C ABI to theme a scene with its own colors. Confirms it round-trips
/// a ``RenderTheme`` (modulo 8-bit color), decodes hex colors, and rejects a
/// malformed color rather than trapping.
final class ThemeWireTests: XCTestCase {

    private let theme = RenderTheme(
        ink: DiagramColor(hex: 0x1D1D1F),
        accent: DiagramColor(hex: 0x5B8FF9),
        canvas: DiagramColor(hex: 0xFFFFFF),
        hairline: DiagramColor(hex: 0x000000, alpha: 0.12),
        secondaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.55),
        tertiaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.38),
        palette: [DiagramColor(hex: 0x5B8FF9), DiagramColor(hex: 0x5AD8A6)],
        prefersDark: true)

    func testRoundTripsThroughWire() throws {
        // The wire quantizes color to 8 bits, so the canonical hex form — not an
        // arbitrary Double alpha — is what round-trips exactly: wire → theme →
        // wire must be identical.
        let wire = ThemeWire(theme)
        let rebuilt = ThemeWire(try wire.renderTheme())
        XCTAssertEqual(rebuilt, wire)
    }

    func testDecodesFromJSON() throws {
        let json = """
        {"ink":"#1D1D1FFF","accent":"#5B8FF9FF","canvas":"#FFFFFFFF",
         "hairline":"#0000001F","secondaryText":"#1D1D1F8C","tertiaryText":"#1D1D1F61",
         "palette":["#5B8FF9FF","#5AD8A6FF"],"prefersDark":true}
        """
        let wire = try JSONDecoder().decode(ThemeWire.self, from: Data(json.utf8))
        let resolved = try wire.renderTheme()
        XCTAssertTrue(resolved.prefersDark)
        XCTAssertEqual(resolved.accent, DiagramColor(hex: 0x5B8FF9))
        XCTAssertEqual(resolved.palette.count, 2)
    }

    func testBadColorThrows() {
        let wire = ThemeWire(ink: "nope", accent: "#000000FF", canvas: "#FFFFFFFF",
                             hairline: "#000000FF", secondaryText: "#000000FF",
                             tertiaryText: "#000000FF", palette: [], prefersDark: false)
        XCTAssertThrowsError(try wire.renderTheme()) { error in
            XCTAssertEqual(error as? ThemeWire.DecodeError, .badColor("nope"))
        }
    }

    func testEncodesSelfDescribingJSON() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = String(decoding: try enc.encode(ThemeWire(theme)), as: UTF8.self)
        XCTAssertTrue(json.contains("\"accent\":\"#5B8FF9FF\""))
        XCTAssertTrue(json.contains("\"prefersDark\":true"))
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
