#if canImport(AppKit) || canImport(UIKit)
import XCTest
import MermaidLayout
@testable import MermaidRender

/// `DiagramTheme.resolved` is the platform-free color surface future
/// backends consume; it must agree with the fingerprint (same pinned
/// appearance) and carry the preset's actual values.
final class ThemeResolvedTests: XCTestCase {
    func testPresetResolvesToDocumentedValues() {
        let light = DiagramTheme(prefersDark: false)
        XCTAssertEqual(light.resolved.ink.hexString, "1D1D1FFF")
        XCTAssertEqual(light.resolved.canvas.hexString, "FFFFFFFF")
        XCTAssertEqual(light.resolved.palette.count, 6)
        XCTAssertEqual(light.resolved.palette[0].hexString, "5B8FF9FF")

        let dark = DiagramTheme(prefersDark: true)
        XCTAssertEqual(dark.resolved.ink.hexString, "F2F2F4FF")
        XCTAssertEqual(dark.resolved.canvas.hexString, "1B1B1DFF")
    }

    func testFingerprintDerivesFromResolved() {
        let theme = DiagramTheme(prefersDark: false)
        // The fingerprint is exactly the resolved colors' digests in order.
        let expected = "l" + ([theme.resolved.ink, theme.resolved.secondaryText,
                               theme.resolved.tertiaryText, theme.resolved.canvas,
                               theme.resolved.accent, theme.resolved.hairline]
                              + theme.resolved.palette).map(\.hexString).joined()
        XCTAssertEqual(theme.fingerprint, expected)
    }
}
#endif
