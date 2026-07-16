#if canImport(AppKit)
import XCTest
import AppKit
@testable import MermaidRender
import MermaidLayout

/// Regenerates the README's images from the fixtures. Gated:
/// `GEN_DOC_IMAGES=1 swift test --filter DocImageGeneration`
final class DocImageGeneration: XCTestCase {

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func png(_ source: String, dark: Bool, scale: CGFloat = 2, pad: CGFloat = 20) -> Data? {
        guard let image = MermaidRenderer.image(source: source, theme: DiagramTheme(prefersDark: dark)) else { return nil }
        let size = NSSize(width: image.size.width * scale + pad * 2, height: image.size.height * scale + pad * 2)
        let card = NSImage(size: size)
        card.lockFocus()
        (dark ? NSColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1D / 255, alpha: 1) : .white).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(x: pad, y: pad, width: image.size.width * scale, height: image.size.height * scale),
                   from: .zero, operation: .sourceOver, fraction: 1)
        card.unlockFocus()
        guard let tiff = card.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    func testGenerateDocImages() throws {
        guard ProcessInfo.processInfo.environment["GEN_DOC_IMAGES"] != nil else {
            throw XCTSkip("set GEN_DOC_IMAGES=1 to regenerate README images")
        }
        let outDir = packageRoot.appendingPathComponent("docs/images")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let fixtures = packageRoot.appendingPathComponent("Fixtures/diagrams")

        // Hero: the sankey, light and dark.
        let hero = try String(contentsOf: fixtures.appendingPathComponent("sankey.mmd"), encoding: .utf8)
        try png(hero, dark: false)?.write(to: outDir.appendingPathComponent("hero-light.png"))
        try png(hero, dark: true)?.write(to: outDir.appendingPathComponent("hero-dark.png"))

        // One standalone image per diagram type, light and dark — first-class
        // assets for the README gallery page and the website.
        let types = outDir.appendingPathComponent("types")
        try FileManager.default.createDirectory(at: types, withIntermediateDirectories: true)
        for url in try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "mmd" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let source = try String(contentsOf: url, encoding: .utf8)
            let name = url.deletingPathExtension().lastPathComponent
            try png(source, dark: false)?.write(to: types.appendingPathComponent("\(name).png"))
            try png(source, dark: true)?.write(to: types.appendingPathComponent("\(name)-dark.png"))
        }
        print("DOCGEN wrote hero + per-type images to \(outDir.path)")
    }
}
#endif
