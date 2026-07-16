#if canImport(AppKit)
import XCTest
import CoreGraphics
@testable import MermaidRender
import MermaidLayout

/// End-to-end timings (parse → layout → render to image) for every fixture.
/// Guards the "renders in interactive time" claim; run with BENCH_TABLE=1 to
/// print the markdown table the README's numbers come from.
final class RenderBenchmarks: XCTestCase {

    private var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
    }

    /// Correctness smoke over every fixture: each one parses, renders, and
    /// rasterizes (forcing the deferred CoreGraphics work). No wall-clock
    /// assertion — timing gates flake under CI load, so performance is never a
    /// pass/fail here. The perf table the README's numbers come from is opt-in:
    /// `BENCH_TABLE=1 swift test --filter RenderBenchmarks` measures and prints
    /// it (and still never asserts on time).
    func testEveryFixtureRendersAndRasterizes() throws {
        let theme = DiagramTheme(prefersDark: false)
        let files = try FileManager.default.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 20)
        let sources: [(name: String, source: String)] = try files.map {
            ($0.deletingPathExtension().lastPathComponent,
             try String(contentsOf: $0, encoding: .utf8))
        }

        // Timing is measured ONLY when benchmarking is requested, so a normal
        // run does no wall-clock work at all. Round-robin sampling (every type
        // once per round, best of rounds) avoids the heat/cache bias consecutive
        // per-type samples showed — a 2x swing (23 ms isolated vs 45 ms
        // in-suite) on the same fixture.
        let benching = ProcessInfo.processInfo.environment["BENCH_TABLE"] != nil
        var parseBestByName: [String: Double] = [:]
        var totalBestByName: [String: Double] = [:]
        for run in 0..<(benching ? 3 : 1) {
            for entry in sources {
                // A run-unique comment busts the render cache so each pass is a
                // true cold parse+layout+render.
                let src = entry.source + "\n%% bench-\(entry.name)-\(run)"
                let t0 = benching ? CFAbsoluteTimeGetCurrent() : 0
                let parsed = MermaidParser.parse(src)
                let parseMS = benching ? (CFAbsoluteTimeGetCurrent() - t0) * 1000 : 0
                XCTAssertNotNil(parsed, entry.name)

                let t1 = benching ? CFAbsoluteTimeGetCurrent() : 0
                let image = MermaidRenderer.image(source: src, theme: theme)
                // Force rasterization: a handler-backed NSImage defers drawing
                // until first use, so the actual CoreGraphics work must be
                // triggered to know the render truly succeeded.
                let rasterized = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                let totalMS = benching ? (CFAbsoluteTimeGetCurrent() - t1) * 1000 : 0
                XCTAssertNotNil(image, entry.name)
                XCTAssertNotNil(rasterized, entry.name)
                if benching {
                    parseBestByName[entry.name] = min(parseBestByName[entry.name] ?? .infinity, parseMS)
                    totalBestByName[entry.name] = min(totalBestByName[entry.name] ?? .infinity, totalMS)
                }
            }
        }

        if benching {
            print("BENCH | Diagram | Parse | Parse + layout + render |")
            print("BENCH |---|---:|---:|")
            for entry in sources {
                print(String(format: "BENCH | %@ | %.2f ms | %.2f ms |",
                             entry.name, parseBestByName[entry.name] ?? 0, totalBestByName[entry.name] ?? 0))
            }
            print(String(format: "BENCH worst: %.1f ms", totalBestByName.values.max() ?? 0))
        }
    }
}
#endif
