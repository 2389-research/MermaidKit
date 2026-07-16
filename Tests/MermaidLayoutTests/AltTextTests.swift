import XCTest
@testable import MermaidLayout

/// Alt-text must be deterministic, name the diagram type, and carry enough
/// content that a listener learns what the diagram is ABOUT. Every fixture
/// produces one; two are pinned exactly to catch phrasing regressions.
final class AltTextTests: XCTestCase {
    private func fixtureSource(_ name: String) throws -> String {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        return try String(contentsOf: dir.appendingPathComponent("\(name).mmd"), encoding: .utf8)
    }

    func testEveryFixtureDescribes() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mmd" }
        XCTAssertEqual(files.count, 30)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let text = try XCTUnwrap(MermaidAltText.describe(source: source),
                                     "\(file.lastPathComponent) failed to describe")
            XCTAssertGreaterThan(text.count, 30, "\(file.lastPathComponent): too thin to be useful")
            XCTAssertTrue(text.hasSuffix("."), "\(file.lastPathComponent): sentences end with periods")
            XCTAssertEqual(text, MermaidAltText.describe(source: source), "must be deterministic")
        }
    }

    func testPinnedPhrasings() throws {
        let pie = try XCTUnwrap(MermaidAltText.describe(source: """
        pie title Languages
            "Swift" : 60
            "Other" : 40
        """))
        XCTAssertEqual(pie, "Pie chart titled “Languages” with 2 slices: Swift 60 percent, Other 40 percent.")

        let flow = try XCTUnwrap(MermaidAltText.describe(source: """
        flowchart TD
            A[Start] --> B[End]
        """))
        XCTAssertEqual(flow, "Flowchart with 2 nodes and 1 connection: Start, End.")
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(MermaidAltText.describe(source: "not a diagram"))
    }
}
