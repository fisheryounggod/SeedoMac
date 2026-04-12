// SeedoMacTests/CategoryStoreTests.swift
import XCTest
import GRDB
@testable import SeedoMac

final class CategoryStoreTests: XCTestCase {
    var db: DatabaseQueue!
    var store: CategoryStore!

    override func setUp() {
        db = try! DatabaseQueue()
        try! db.write { d in
            try d.execute(sql: """
                CREATE TABLE categories (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    color TEXT NOT NULL DEFAULT '#4A90D9', rules TEXT NOT NULL DEFAULT '[]'
                );
                CREATE TABLE category_rules (
                    app_or_domain TEXT PRIMARY KEY, category_id TEXT NOT NULL
                );
            """)
        }
        store = CategoryStore(db: db)
    }

    func test_saveAndFetch() throws {
        let cat = Category(id: "work", name: "Work", color: "#00FF00", rules: "[]")
        try store.save(cat)
        let all = try store.allCategories()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Work")
    }

    func test_matchCategory_byAppName() throws {
        let rules = #"[{"field":"app","op":"contains","value":"Xcode"}]"#
        let cat = Category(id: "work", name: "Work", color: "#00FF00", rules: rules)
        try store.save(cat)
        let matched = try store.matchCategory(for: "Xcode", title: "")
        XCTAssertEqual(matched?.id, "work")
    }

    func test_matchCategory_noMatch_returnsNil() throws {
        let rules = #"[{"field":"app","op":"contains","value":"Xcode"}]"#
        let cat = Category(id: "work", name: "Work", color: "#00FF00", rules: rules)
        try store.save(cat)
        let matched = try store.matchCategory(for: "Safari", title: "")
        XCTAssertNil(matched)
    }

    func test_delete_removesCategory() throws {
        let cat = Category(id: "work", name: "Work", color: "#00FF00", rules: "[]")
        try store.save(cat)
        try store.delete(id: "work")
        let all = try store.allCategories()
        XCTAssertTrue(all.isEmpty)
    }
}
