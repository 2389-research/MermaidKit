#if canImport(AppKit) || canImport(UIKit)
import XCTest
import MermaidLayout
@testable import MermaidRender
final class RTmp: XCTestCase {
    func testR() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diagrams")
        for name in ["gantt", "flowchart", "pie", "timeline"] {
            let src = try String(contentsOf: dir.appendingPathComponent("\(name).mmd"), encoding: .utf8)
            let attr = MermaidRenderer.attachmentString(source: src, theme: DiagramTheme(prefersDark: false))
            print("R \(name) -> \(attr == nil ? "nil" : "ok")")
        }
    }
}
#endif
