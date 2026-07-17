// Cross-process render determinism — the gap StabilityTests can't cover.
//
// Swift randomizes the Set/Dictionary hash seed PER PROCESS, so a layout that
// iterates a hashed collection into coordinates can render one source two ways
// across app launches (issue #1). A single test process has one fixed seed, so
// `StabilityTests.testLayoutIsDeterministicAcrossRuns` (two calls, same process)
// can't see it. This test only DUMPS a raster signature per fixture; the actual
// assertion runs it in two fresh processes and diffs — see
// `scripts/check-determinism.sh`. Gated, so it's inert in the normal suite.
#if canImport(AppKit) || canImport(UIKit)
import XCTest
import Foundation
@testable import MermaidRender
@testable import MermaidLayout

final class DeterminismSignatureTests: XCTestCase {

    /// Seed-independent (FNV-1a) so signatures are comparable across processes —
    /// `Hasher`/`hashValue` are themselves seeded and would differ every launch.
    private func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    func testEmitRasterSignatures() throws {
        guard let path = ProcessInfo.processInfo.environment["DETERMINISM_OUT"] else {
            throw XCTSkip("gated: set DETERMINISM_OUT (run via scripts/check-determinism.sh)")
        }
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let bg: (r: UInt8, g: UInt8, b: UInt8) = (255, 255, 255)
        var lines: [String] = []
        for f in files {
            let src = try String(contentsOf: f, encoding: .utf8)
            guard let diagram = MermaidParser.parse(src) else { continue }
            let name = f.deletingPathExtension().lastPathComponent
            if let r = MermaidRenderer.rgbaRaster(diagram: diagram, theme: DiagramTheme(prefersDark: false),
                                                  targetWidth: 500, background: bg) {
                lines.append("\(name)\t\(r.width)x\(r.height):\(fnv1a(r.pixels))")
            } else {
                lines.append("\(name)\tnil")
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
