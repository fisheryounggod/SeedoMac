import XCTest
import GRDB
@testable import SeedoMac

final class WorkSessionStorePerformanceTests: XCTestCase {
    var db: DatabaseQueue!
    var store: WorkSessionStore!

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
                CREATE TABLE work_sessions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    start_ts INTEGER NOT NULL,
                    end_ts INTEGER NOT NULL,
                    top_apps_json TEXT NOT NULL DEFAULT '[]',
                    summary TEXT NOT NULL DEFAULT '',
                    outcome TEXT NOT NULL DEFAULT 'completed',
                    created_at INTEGER NOT NULL,
                    is_manual INTEGER NOT NULL DEFAULT 0,
                    title TEXT NOT NULL DEFAULT '',
                    category_id TEXT
                );
                INSERT INTO categories (id, name, color) VALUES
                    ('focus', '专注工作', '#4A90D9'),
                    ('daily', '日常事务', '#52C41A');
                INSERT INTO work_sessions
                    (start_ts, end_ts, created_at, category_id)
                VALUES
                    (1000, 61000, 61000, 'focus'),
                    (61000, 181000, 181000, 'daily'),
                    (181000, 211000, 211000, 'focus');
            """)
        }
        store = WorkSessionStore(db: db)
    }

    func test_focusedDuration_aggregatesOnlyFocusCategoriesInRange() throws {
        let duration = try store.focusedDuration(from: 0, to: 300_000)
        XCTAssertEqual(duration, 90, accuracy: 0.001)
    }

    func test_focusedDuration_respectsStartRange() throws {
        let duration = try store.focusedDuration(from: 100_000, to: 300_000)
        XCTAssertEqual(duration, 30, accuracy: 0.001)
    }
}
