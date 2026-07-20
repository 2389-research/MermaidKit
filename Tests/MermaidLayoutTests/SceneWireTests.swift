import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Exercises ``SceneWire`` — the explicit, language-neutral wire schema the
/// Android/JNI bridge and plugin system read. Confirms it is a lossless
/// projection of ``RenderScene`` (round-trips byte-stably modulo 8-bit color),
/// that its JSON is the intended self-describing `type`-tagged shape (no Swift
/// `_0`/positional-array quirks), that every diagram family lowers to a
/// decodable wire, and that malformed payloads are rejected, not trapped.
final class SceneWireTests: XCTestCase {

    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    private let theme = RenderTheme(
        ink: DiagramColor(hex: 0x1D1D1F),
        accent: DiagramColor(hex: 0x5B8FF9),
        canvas: DiagramColor(hex: 0xFFFFFF),
        hairline: DiagramColor(hex: 0x000000, alpha: 0.12),
        secondaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.55),
        tertiaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.38),
        palette: [DiagramColor(hex: 0x5B8FF9), DiagramColor(hex: 0x61DDAA),
                  DiagramColor(hex: 0xF6BD16), DiagramColor(hex: 0x7262FD)])

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }()

    private func scene(_ source: String) throws -> RenderScene {
        let diagram = try XCTUnwrap(MermaidParser.parse(source), "failed to parse")
        return try XCTUnwrap(RenderScene.from(diagram, theme: theme, measure: measure),
                             "failed to lower")
    }

    // Covers every discriminated case: rounded rect, diamond (polygon), circle
    // (ellipse), routed edges (polyline + arrow), and labels (text + backing).
    private let flowchart = """
    flowchart LR
        A[Start] --> B{Choice}
        B -->|yes| C((Done))
        B -->|no| D[Stop]
    """

    // MARK: - Round-trip

    func testWireRoundTripsByteStable() throws {
        let wire = SceneWire(try scene(flowchart))
        let rebuilt = SceneWire(try wire.scene())
        XCTAssertEqual(try encoder.encode(wire), try encoder.encode(rebuilt),
                       "wire → scene → wire must be byte-identical")
    }

    func testDecodeReencodeIsStable() throws {
        let json = try encoder.encode(SceneWire(try scene(flowchart)))
        let decoded = try JSONDecoder().decode(SceneWire.self, from: json)
        XCTAssertEqual(try encoder.encode(decoded), json,
                       "decode then re-encode must reproduce the exact bytes")
    }

    // MARK: - Schema shape (the contract Android/plugins read)

    func testWireIsSelfDescribing() throws {
        let json = String(decoding: try encoder.encode(SceneWire(try scene(flowchart))),
                          as: UTF8.self)
        // Self-describing discriminators, not Swift's synthesized quirks.
        XCTAssertTrue(json.contains("\"type\":\"polyline\""))
        XCTAssertTrue(json.contains("\"type\":\"shape\""))
        XCTAssertTrue(json.contains("\"type\":\"text\""))
        // Named point fields, not bare [x,y] arrays; hex colors, not {r,g,b,a}.
        XCTAssertTrue(json.contains("\"x\":"))
        XCTAssertTrue(json.contains("\"y\":"))
        XCTAssertTrue(json.contains("\"color\":\"#"))
        XCTAssertTrue(json.contains("\"version\":1"))
        // None of the Swift-Codable leakage.
        XCTAssertFalse(json.contains("\"_0\""), "wire must not carry Swift's _0 wrappers")
    }

    func testShapePathDiscriminatorsPresent() throws {
        let json = String(decoding: try encoder.encode(SceneWire(try scene(flowchart))),
                          as: UTF8.self)
        XCTAssertTrue(json.contains("\"type\":\"roundedRect\""), "rect nodes → roundedRect")
        XCTAssertTrue(json.contains("\"type\":\"polygon\""), "diamond → polygon")
        XCTAssertTrue(json.contains("\"type\":\"ellipse\""), "circle → ellipse")
    }

    // MARK: - Every family lowers to a decodable wire

    func testAllFixturesProduceDecodableWire() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "mmd" }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        try XCTSkipIf(files.isEmpty, "no fixtures found")
        for f in files {
            let name = f.deletingPathExtension().lastPathComponent
            let src = try String(contentsOf: f, encoding: .utf8)
            guard let diagram = MermaidParser.parse(src),
                  let s = RenderScene.from(diagram, theme: theme, measure: measure) else { continue }
            let json = try encoder.encode(SceneWire(s))
            // Decodes back, and reconstructs to a RenderScene without throwing.
            let decoded = try JSONDecoder().decode(SceneWire.self, from: json)
            XCTAssertNoThrow(try decoded.scene(), "\(name): wire failed to reconstruct")
            XCTAssertEqual(decoded.elements.count, s.elements.count, "\(name): element count drift")
        }
    }

    // MARK: - Malformed payloads reject, never trap

    func testUnknownElementTypeThrows() {
        let bad = Data(##"{"version":1,"size":{"w":1,"h":1},"background":"#FFFFFFFF","elements":[{"type":"blob"}]}"##.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SceneWire.self, from: bad))
    }

    func testBadColorStringThrowsOnReconstruct() throws {
        let wire = SceneWire(version: 1, size: .init(w: 1, h: 1), background: "not-a-color",
                             elements: [])
        XCTAssertThrowsError(try wire.scene()) { error in
            XCTAssertEqual(error as? SceneWire.DecodeError, .badColor("not-a-color"))
        }
    }

    func testHexColorRoundTrips() throws {
        // The wire quantizes color to 8 bits per channel, so the canonical hex
        // form — not an arbitrary Double alpha — is the value that round-trips
        // exactly. Parsing then re-stringifying must be idempotent, and 6-digit
        // (opaque) forms decode to alpha 1.
        for hex: String in ["00000000", "FFFFFFFF", "5B8FF959", "1D1D1F8C", "5B8FF9"] {
            let parsed = try XCTUnwrap(DiagramColor(hexString: hex), "\(hex) must parse")
            let expected = hex.count == 6 ? hex + "FF" : hex
            XCTAssertEqual(parsed.hexString, expected, "#\(hex) must round-trip its canonical form")
        }
        XCTAssertNil(DiagramColor(hexString: "xyz"), "non-hex must be rejected")
        XCTAssertNil(DiagramColor(hexString: "12345"), "odd length must be rejected")
    }
}
