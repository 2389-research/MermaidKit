import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// The SQL-DDL front-end: `CREATE TABLE …` → `ERDiagram`. Covers column typing,
/// inline and table-level keys, foreign-key relationships and their cardinality,
/// dialect quoting, the graceful-degradation contract, and a clean layout.
final class SQLDDLParserTests: XCTestCase {

    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
    }

    func testColumnsBecomeTypedAttributes() throws {
        let er = try XCTUnwrap(SQLDDLParser.parse("""
        CREATE TABLE customer (
          id INT,
          name VARCHAR(100),
          balance DECIMAL(10,2),
          created_at TIMESTAMP
        );
        """))
        XCTAssertEqual(er.entities.map(\.name), ["customer"])
        let attrs = er.entities[0].attributes
        XCTAssertEqual(attrs.map(\.name), ["id", "name", "balance", "created_at"])
        XCTAssertEqual(attrs.map(\.type), ["INT", "VARCHAR(100)", "DECIMAL(10,2)", "TIMESTAMP"])
        XCTAssertTrue(attrs.allSatisfy { $0.keys.isEmpty })
    }

    func testInlineKeysAndReferences() throws {
        let er = try XCTUnwrap(SQLDDLParser.parse("""
        CREATE TABLE customer (id INT PRIMARY KEY, name TEXT);
        CREATE TABLE orders (
          id INT PRIMARY KEY,
          customer_id INT REFERENCES customer(id),
          total DECIMAL(10,2)
        );
        """))
        XCTAssertEqual(Set(er.entities.map(\.name)), ["customer", "orders"])
        let orders = try XCTUnwrap(er.entities.first { $0.name == "orders" })
        XCTAssertEqual(orders.attributes.first { $0.name == "id" }?.keys, [.primary])
        let cid = try XCTUnwrap(orders.attributes.first { $0.name == "customer_id" })
        XCTAssertEqual(cid.keys, [.foreign])
        XCTAssertEqual(cid.keyBadge, "FK")

        // One foreign key ⇒ one parent-to-many relationship.
        XCTAssertEqual(er.relations.count, 1)
        let rel = try XCTUnwrap(er.relations.first)
        XCTAssertEqual(rel.from, "customer")
        XCTAssertEqual(rel.to, "orders")
        XCTAssertEqual(rel.fromCard, .one)
        XCTAssertEqual(rel.toCard, .zeroOrMore)
    }

    func testTableLevelConstraints() throws {
        let er = try XCTUnwrap(SQLDDLParser.parse("""
        CREATE TABLE line_item (
          order_id INT,
          product_id INT,
          qty INT,
          PRIMARY KEY (order_id, product_id),
          FOREIGN KEY (order_id) REFERENCES orders (id),
          CONSTRAINT fk_prod FOREIGN KEY (product_id) REFERENCES product (id)
        );
        CREATE TABLE orders (id INT PRIMARY KEY);
        CREATE TABLE product (id INT PRIMARY KEY);
        """))
        let li = try XCTUnwrap(er.entities.first { $0.name == "line_item" })
        XCTAssertEqual(li.attributes.first { $0.name == "order_id" }?.keys, [.primary, .foreign])
        XCTAssertEqual(li.attributes.first { $0.name == "product_id" }?.keys, [.primary, .foreign])
        XCTAssertEqual(Set(er.relations.map { "\($0.from)->\($0.to)" }),
                       ["orders->line_item", "product->line_item"])
    }

    func testUniqueConstraint() throws {
        let er = try XCTUnwrap(SQLDDLParser.parse("""
        CREATE TABLE account (id INT PRIMARY KEY, email VARCHAR(255) UNIQUE);
        """))
        let email = try XCTUnwrap(er.entities[0].attributes.first { $0.name == "email" })
        XCTAssertEqual(email.keys, [.unique])
        XCTAssertEqual(email.keyBadge, "UK")
    }

    func testDialectQuotingAndComments() throws {
        let er = try XCTUnwrap(SQLDDLParser.parse("""
        -- a schema with mixed quoting
        CREATE TABLE "Order Item" (
          `id` INT PRIMARY KEY,   /* the key */
          [note] TEXT
        );
        """))
        XCTAssertEqual(er.entities.map(\.name), ["Order Item"])
        XCTAssertEqual(er.entities[0].attributes.map(\.name), ["id", "note"])
        XCTAssertEqual(er.entities[0].attributes.first { $0.name == "id" }?.keys, [.primary])
    }

    func testForwardReferencesResolveAndUnknownTargetsDrop() throws {
        // FK to a table that is never defined ⇒ the relation is dropped (its
        // endpoint isn't a known entity), but the column keeps its FK badge.
        let er = try XCTUnwrap(SQLDDLParser.parse("""
        CREATE TABLE post (id INT PRIMARY KEY, author_id INT REFERENCES author(id));
        """))
        XCTAssertEqual(er.entities.map(\.name), ["post"])
        XCTAssertEqual(er.entities[0].attributes.first { $0.name == "author_id" }?.keys, [.foreign])
        XCTAssertTrue(er.relations.isEmpty, "relation to an undefined table should drop")
    }

    // MARK: - Degradation contract

    func testAdversarialInputsDoNotCrash() {
        let cases = [
            "", "not sql at all", "CREATE TABLE", "CREATE TABLE x", "CREATE TABLE x (",
            "CREATE TABLE x ();", "SELECT * FROM t;", "CREATE TABLE x AS SELECT 1;",
            "((((((", "CREATE TABLE 你好 (id INT);", "create table t(a,b,c);",
        ]
        for c in cases { _ = SQLDDLParser.parse(c) }   // must not crash; nil is acceptable
    }

    func testHugeInputReturnsNil() {
        XCTAssertNil(SQLDDLParser.parse(String(repeating: "a ", count: MermaidParser.maxTextSize)))
    }

    func testNonDDLReturnsNil() {
        XCTAssertNil(SQLDDLParser.parse("SELECT 1;"))
        XCTAssertNil(SQLDDLParser.parse("flowchart TD\n A --> B"))
    }

    // MARK: - Pipeline

    func testParseLayoutSceneLintsClean() throws {
        let er = try XCTUnwrap(SQLDDLParser.parse("""
        CREATE TABLE customer (id INT PRIMARY KEY, name VARCHAR(100));
        CREATE TABLE orders (id INT PRIMARY KEY, customer_id INT REFERENCES customer(id), total DECIMAL(10,2));
        """))
        let scene = DiagramScene.lower(.er(er), measure: measure)
        let errors = DiagramLayoutLinter.lint(scene).filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "layout errors: \(errors)")
    }

    /// Regression: Mermaid `erDiagram` sources leave `keys` empty, so the new
    /// badge/width code is a no-op for them (existing ER renders unchanged).
    func testMermaidERLeavesKeysEmpty() throws {
        let d = try XCTUnwrap(MermaidParser.parse("""
        erDiagram
          CUSTOMER {
            string name
            int id
          }
        """))
        guard case .er(let er) = d else { return XCTFail("expected .er") }
        XCTAssertTrue(er.entities.allSatisfy { $0.attributes.allSatisfy { $0.keys.isEmpty } })
    }
}
