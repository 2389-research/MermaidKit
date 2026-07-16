import XCTest
@testable import MermaidLayout

/// `brLines` is the single line-break splitter every renderer shares. It must
/// accept the many interchangeable forms real mermaid diagrams use.
final class LineBreakTests: XCTestCase {
    private func split(_ s: String) -> [String] { DiagramLayoutEngine.brLines(s) }

    func testBrTagVariants() {
        XCTAssertEqual(split("a<br>b"), ["a", "b"])
        XCTAssertEqual(split("a<br/>b"), ["a", "b"])
        XCTAssertEqual(split("a<br />b"), ["a", "b"])
        XCTAssertEqual(split("a<br  />b"), ["a", "b"], "extra whitespace")
        XCTAssertEqual(split("a<br/ >b"), ["a", "b"], "space after slash")
        XCTAssertEqual(split("a<BR>b"), ["a", "b"], "uppercase")
        XCTAssertEqual(split("a<Br/>b"), ["a", "b"], "mixed case")
        XCTAssertEqual(split("a<br class=\"x\">b"), ["a", "b"], "stray attributes")
    }

    func testBackslashN() {
        XCTAssertEqual(split("a\\nb"), ["a", "b"], "literal two-char backslash-n")
        XCTAssertEqual(split("a\\nb\\nc"), ["a", "b", "c"])
    }

    func testRealNewlines() {
        XCTAssertEqual(split("a\nb"), ["a", "b"])
        XCTAssertEqual(split("a\r\nb"), ["a", "b"], "CRLF collapses, no blank")
        XCTAssertEqual(split("a\u{2028}b"), ["a", "b"], "unicode line separator")
    }

    func testMixedAndMessy() {
        XCTAssertEqual(split("one<br/>two<BR>three\\nfour"), ["one", "two", "three", "four"])
        XCTAssertEqual(split("  a <br/> b  "), ["a", "b"], "each line trimmed")
        XCTAssertEqual(split("a<br/><br/>b"), ["a", "b"], "repeated breaks → no blank line")
        XCTAssertEqual(split("<br/>a<br/>"), ["a"], "leading/trailing breaks dropped")
    }

    func testNonBreaks() {
        XCTAssertEqual(split("<brilliant> idea"), ["<brilliant> idea"], "not a <br> tag")
        XCTAssertEqual(split("plain label"), ["plain label"])
        XCTAssertEqual(split(""), [])
        XCTAssertEqual(split("   "), [], "whitespace-only → nothing")
    }
}
