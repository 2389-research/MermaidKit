import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import MermaidLayout
import MermaidKitC

/// Exercises the C ABI (`mmk_*`) end-to-end, from Swift, using a non-capturing
/// `@convention(c)` measure callback — proving the bridge is faithful to a
/// `RenderScene.from(...)` computed directly with the same measurer and theme,
/// that the null-measure fallback still lowers, that narration threads through,
/// that failures return nil (never trap), that frees don't crash, and that the
/// wire form is deterministic.
final class MermaidKitCTests: XCTestCase {

    // MARK: Fixtures

    private let flowchart = """
    flowchart TD
        A[Start] --> B{Choice}
        B -->|yes| C[Store]
        B -->|no| D[End]
    """

    private let sequence = """
    sequenceDiagram
        Alice->>Bob: Hello
        Bob-->>Alice: Hi
    """

    private let state = """
    stateDiagram-v2
        [*] --> Idle
        Idle --> Running
        Running --> [*]
    """

    private var fixtures: [String] { [flowchart, sequence, state] }

    // MARK: Measurers

    /// A non-capturing `@convention(c)` measure callback — the shape a JNI
    /// consumer supplies. Mirrors the coarse glyph-box metric so we can compute
    /// the reference scene in-process with the same numbers.
    private static let cMeasure: MmkMeasure = { text, size, _, w, h in
        w?.pointee = Double(strlen(text!)) * size * 0.6
        h?.pointee = size + 4
    }

    /// The Swift-side twin of `cMeasure` after it wraps into a
    /// `DiagramTextMeasurer` — `strlen` counts UTF-8 bytes, so `utf8.count`.
    private let directMeasure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(Double(text.utf8.count) * size * 0.6),
               height: size + 4)
    }

    // The reference theme, identical to MermaidKitC's private light preset.
    private let referenceTheme = RenderTheme(
        ink: DiagramColor(hex: 0x1D1D1F),
        accent: DiagramColor(hex: 0x5B8FF9),
        canvas: DiagramColor(hex: 0xFFFFFF),
        hairline: DiagramColor(hex: 0x000000, alpha: 0.12),
        secondaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.55),
        tertiaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.38),
        palette: [
            DiagramColor(hex: 0x5B8FF9), DiagramColor(hex: 0x5AD8A6),
            DiagramColor(hex: 0xF6BD16), DiagramColor(hex: 0xE8684A),
            DiagramColor(hex: 0x6DC8EC), DiagramColor(hex: 0x9270CA),
        ],
        prefersDark: false)

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: Helpers

    /// Calls `mmk_scene_json` and returns the JSON as a Swift string, freeing
    /// the malloc'd result via `mmk_free` (also proving free doesn't crash).
    private func sceneJSON(_ source: String, prefersDark: Int32 = 0,
                           measure: MmkMeasure? = MermaidKitCTests.cMeasure) -> String? {
        guard let ptr = source.withCString({
            mmk_scene_json($0, prefersDark, measure, nil)
        }) else { return nil }
        defer { mmk_free(ptr) }
        return String(cString: ptr)
    }

    // MARK: - Faithfulness

    func testSceneJSONMatchesDirectLowering() throws {
        for source in fixtures {
            guard let abiJSON = sceneJSON(source) else {
                XCTFail("mmk_scene_json returned nil for a valid fixture")
                continue
            }

            // The ABI emits the explicit `SceneWire` schema (not RenderScene's
            // synthesized Codable). Decode it and confirm it's a real, non-empty
            // scene tagged with the current schema version.
            let data = Data(abiJSON.utf8)
            let decoded = try JSONDecoder().decode(SceneWire.self, from: data)
            XCTAssertGreaterThan(decoded.elements.count, 0,
                                 "ABI scene must have elements")
            XCTAssertEqual(decoded.version, SceneWire.currentVersion)

            // Compute the reference scene in-process with the SAME measurer and
            // theme, project it to the wire form, encode it the same way, and
            // require byte-for-byte equality — the proof the ABI faithfully
            // wraps RenderScene.from(...) through SceneWire.
            guard let diagram = MermaidParser.parse(source),
                  let reference = RenderScene.from(diagram, theme: referenceTheme,
                                                   measure: directMeasure) else {
                XCTFail("reference lowering failed for a valid fixture")
                continue
            }
            let referenceJSON = String(decoding: try encoder.encode(SceneWire(reference)),
                                       as: UTF8.self)
            XCTAssertEqual(abiJSON, referenceJSON,
                           "ABI JSON must match SceneWire(RenderScene.from(...))")

            // And the decoded size / element count match the reference.
            XCTAssertEqual(decoded.size.w, Double(reference.size.width))
            XCTAssertEqual(decoded.size.h, Double(reference.size.height))
            XCTAssertEqual(decoded.elements.count, reference.elements.count)
        }
    }

    // MARK: - Null-measure fallback

    func testNullMeasureFallsBackAndStillLowers() throws {
        guard let json = sceneJSON(flowchart, measure: nil) else {
            XCTFail("null-measure path returned nil")
            return
        }
        let scene = try JSONDecoder().decode(SceneWire.self, from: Data(json.utf8))
        XCTAssertGreaterThan(scene.elements.count, 0,
                             "fallback measurer must still produce a scene")
        XCTAssertGreaterThan(scene.size.w, 0)
        XCTAssertGreaterThan(scene.size.h, 0)
    }

    // MARK: - Dark theme

    func testDarkThemeChangesBackground() throws {
        let light = try XCTUnwrap(sceneJSON(flowchart, prefersDark: 0))
        let dark = try XCTUnwrap(sceneJSON(flowchart, prefersDark: 1))
        XCTAssertNotEqual(light, dark, "prefers_dark must change the scene")

        let darkScene = try JSONDecoder().decode(SceneWire.self, from: Data(dark.utf8))
        // Background is a #RRGGBBAA string; dark canvas is near-black (0x1B1B1D),
        // so well below mid-gray once parsed back to a color.
        let bg = try XCTUnwrap(DiagramColor(hexString: darkScene.background))
        XCTAssertLessThan(bg.red, 0.5)
    }

    // MARK: - Explicit theme (mmk_scene_json_themed)

    private func themedJSON(_ source: String, theme: String?) -> String? {
        let call: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { src in
            if let theme {
                return theme.withCString { t in
                    mmk_scene_json_themed(src, t, MermaidKitCTests.cMeasure, nil)
                }
            }
            return mmk_scene_json_themed(src, nil, MermaidKitCTests.cMeasure, nil)
        }
        guard let ptr = source.withCString(call) else { return nil }
        defer { mmk_free(ptr) }
        return String(cString: ptr)
    }

    func testThemedCanvasUsesCallerColor() throws {
        // A caller theme with a distinctive canvas must paint that background.
        let theme = """
        {"ink":"#101010FF","accent":"#FF0000FF","canvas":"#123456FF",
         "hairline":"#0000001F","secondaryText":"#1010108C","tertiaryText":"#10101061",
         "palette":["#FF0000FF"],"prefersDark":false}
        """
        let json = try XCTUnwrap(themedJSON(flowchart, theme: theme))
        let scene = try JSONDecoder().decode(SceneWire.self, from: Data(json.utf8))
        XCTAssertEqual(scene.background.uppercased(), "#123456FF",
                       "themed scene must use the caller's canvas color")
    }

    func testThemedNilFallsBackToLightPreset() throws {
        // nil theme == the light preset, i.e. equal to mmk_scene_json(prefersDark: 0).
        let themed = try XCTUnwrap(themedJSON(flowchart, theme: nil))
        let preset = try XCTUnwrap(sceneJSON(flowchart, prefersDark: 0))
        XCTAssertEqual(themed, preset)
    }

    func testThemedInvalidJSONReturnsNil() {
        XCTAssertNil(themedJSON(flowchart, theme: "{ not valid json"))
        XCTAssertNil(themedJSON(flowchart, theme: #"{"ink":"bogus"}"#))
    }

    // MARK: - Narration

    func testNarrateReturnsWalkthrough() throws {
        let ptr = try XCTUnwrap(flowchart.withCString { mmk_narrate($0) },
                                "mmk_narrate returned nil for a valid fixture")
        defer { mmk_free(ptr) }
        let narration = String(cString: ptr)
        XCTAssertFalse(narration.isEmpty)

        // Must match the library's own narration exactly.
        let expected = try XCTUnwrap(MermaidAltText.narrate(source: flowchart))
        XCTAssertEqual(narration, expected)
        // And mention a node label from the walkthrough.
        XCTAssertTrue(narration.contains("Start"),
                      "narration should reference the Start node")
    }

    // MARK: - Nil / failure paths

    func testNilSourceReturnsNil() {
        XCTAssertNil(mmk_scene_json(nil, 0, MermaidKitCTests.cMeasure, nil))
        XCTAssertNil(mmk_narrate(nil))
    }

    func testUnparseableSourceReturnsNil() {
        let garbage = "this is not a mermaid diagram at all"
        XCTAssertNil(sceneJSON(garbage))
    }

    func testFreeOnNilDoesNotCrash() {
        mmk_free(nil) // must be a no-op, not a trap.
    }

    // MARK: - Version

    func testVersionIsStable() {
        let a = try? XCTUnwrap(mmk_version())
        let b = try? XCTUnwrap(mmk_version())
        XCTAssertNotNil(a)
        // Same static pointer every call — never freed by the caller.
        XCTAssertEqual(a, b)
        let v = String(cString: mmk_version()!)
        XCTAssertTrue(v.contains("MermaidKitC"), "version string: \(v)")
    }

    // MARK: - Determinism

    func testDeterministicAcrossCalls() throws {
        for source in fixtures {
            let first = try XCTUnwrap(sceneJSON(source))
            let second = try XCTUnwrap(sceneJSON(source))
            XCTAssertEqual(first, second,
                           "identical inputs must yield identical JSON")
        }
    }
}
