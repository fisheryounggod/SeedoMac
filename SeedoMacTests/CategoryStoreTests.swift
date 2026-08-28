import XCTest
import GRDB
@testable import SeedoMac

final class CategoryStoreTests: XCTestCase {
    var db: DatabaseQueue!

    override func setUp() {
        super.setUp()
        db = try! DatabaseQueue()
        try! db.write { database in
            try database.execute(sql: """
                CREATE TABLE categories (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    color TEXT NOT NULL,
                    display_order INTEGER NOT NULL DEFAULT 0
                );
            """)
        }
    }

    func test_saveAndFetchCategory() throws {
        var category = SessionCategory(id: "work", name: "工作", colorHex: "#00FF00", displayOrder: 1)
        try db.write { database in try category.insert(database) }

        let fetched = try db.read { database in
            try SessionCategory.fetchOne(database, key: "work")
        }
        XCTAssertEqual(fetched?.name, "工作")
        XCTAssertEqual(fetched?.colorHex, "#00FF00")
    }

    func test_updateCategory() throws {
        var category = SessionCategory(id: "work", name: "工作", colorHex: "#00FF00")
        try db.write { database in try category.insert(database) }
        category.name = "深度工作"
        try db.write { database in try category.update(database) }

        let fetched = try db.read { database in
            try SessionCategory.fetchOne(database, key: "work")
        }
        XCTAssertEqual(fetched?.name, "深度工作")
    }

    func test_categoriesSortByDisplayOrder() throws {
        var later = SessionCategory(id: "later", name: "稍后", colorHex: "#000000", displayOrder: 2)
        var first = SessionCategory(id: "first", name: "优先", colorHex: "#FFFFFF", displayOrder: 0)
        try db.write { database in
            try later.insert(database)
            try first.insert(database)
        }

        let categories = try db.read { database in
            try SessionCategory.order(Column("display_order").asc).fetchAll(database)
        }
        XCTAssertEqual(categories.map(\.id), ["first", "later"])
    }

    func test_deleteCategory() throws {
        var category = SessionCategory(id: "work", name: "工作", colorHex: "#00FF00")
        try db.write { database in try category.insert(database) }
        try db.write { database in _ = try SessionCategory.deleteOne(database, key: "work") }

        let count = try db.read { database in try SessionCategory.fetchCount(database) }
        XCTAssertEqual(count, 0)
    }
}
