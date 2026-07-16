import XCTest
@testable import MermaidLayout

final class DiagramColorTests: XCTestCase {
    func testHexRoundTrip() {
        let c = DiagramColor(hex: 0x5B8FF9)
        XCTAssertEqual(c.hexString, "5B8FF9FF")
        XCTAssertEqual(DiagramColor(hex: 0x000000, alpha: 0.5).hexString, "00000080")
    }

    func testComponentsClamp() {
        let c = DiagramColor(red: 2, green: -1, blue: 0.5, alpha: 7)
        XCTAssertEqual(c.red, 1); XCTAssertEqual(c.green, 0)
        XCTAssertEqual(c.blue, 0.5); XCTAssertEqual(c.alpha, 1)
    }

    func testCodableRoundTrip() throws {
        let c = DiagramColor(hex: 0xE8684A, alpha: 0.25)
        let back = try JSONDecoder().decode(DiagramColor.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
}
