// A SQL schema parsed to `ERDiagram` must render to a PNG (with PK/FK badges)
// in both themes without trapping — the same "never trap on a parsed diagram"
// contract the other front-ends hold.
#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
@testable import MermaidRender
@testable import MermaidLayout

final class SQLRenderTests: XCTestCase {

    func testSQLSchemaRendersBothThemes() throws {
        let src = """
        CREATE TABLE customer (
          id INT PRIMARY KEY,
          name VARCHAR(100) UNIQUE
        );
        CREATE TABLE orders (
          id INT PRIMARY KEY,
          customer_id INT REFERENCES customer(id),
          total DECIMAL(10,2)
        );
        """
        let er = try XCTUnwrap(SQLDDLParser.parse(src), "SQL schema failed to parse")
        let diagram = MermaidDiagram.er(er)
        for prefersDark in [false, true] {
            let theme = DiagramTheme(prefersDark: prefersDark)
            let png = try XCTUnwrap(
                MermaidRenderer.pngData(diagram: diagram, theme: theme),
                "SQL-derived ER rendered nil (prefersDark=\(prefersDark))")
            XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47],
                           "not a PNG (prefersDark=\(prefersDark))")
        }
    }
}
#endif
