// Seedo/Data/AppDatabase.swift
import Foundation
import GRDB

final class AppDatabase {
    static let shared = AppDatabase()

    let pool: DatabasePool

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = appSupport.appendingPathComponent("Seedo")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // Directory may already exist — only log if it's a real error
            if (error as NSError).code != NSFileWriteFileExistsError {
                print("[AppDatabase] Failed to create app directory: \(error)")
            }
        }

        let dbURL = dir.appendingPathComponent("seedo.db")

        do {
            pool = try DatabasePool(path: dbURL.path)
        } catch {
            // Fatal: can't open database. Show error and terminate gracefully.
            print("[AppDatabase] FATAL: Cannot open database at \(dbURL.path): \(error)")
            // Provide a last-resort in-memory queue so the app doesn't crash silently mid-init
            pool = try! DatabasePool(path: ":memory:")
            return
        }

        do {
            try migrate()
        } catch {
            print("[AppDatabase] Migration failed: \(error)")
            // Don't crash — app can still run with existing schema
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS events (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    source        TEXT    NOT NULL DEFAULT 'desktop',
                    start_ts      INTEGER NOT NULL,
                    end_ts        INTEGER NOT NULL,
                    app_or_domain TEXT    NOT NULL,
                    bundle_id     TEXT,
                    title         TEXT    NOT NULL DEFAULT '',
                    url           TEXT,
                    path          TEXT,
                    page_type     TEXT,
                    is_redacted   INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_events_start_ts ON events(start_ts);
                CREATE INDEX IF NOT EXISTS idx_events_app ON events(app_or_domain);

                CREATE TABLE IF NOT EXISTS categories (
                    id    TEXT PRIMARY KEY,
                    name  TEXT NOT NULL,
                    color TEXT NOT NULL DEFAULT '#4A90D9',
                    rules TEXT NOT NULL DEFAULT '[]'
                );

                CREATE TABLE IF NOT EXISTS category_rules (
                    app_or_domain TEXT PRIMARY KEY,
                    category_id   TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS offline_activities (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    start_ts      INTEGER NOT NULL,
                    duration_secs INTEGER NOT NULL,
                    label         TEXT    NOT NULL,
                    tag_id        TEXT,
                    created_at    INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS daily_summaries (
                    date       TEXT PRIMARY KEY,
                    content    TEXT NOT NULL DEFAULT '',
                    score      INTEGER NOT NULL DEFAULT 0,
                    keywords   TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS settings (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
            """)
        }

        migrator.registerMigration("v2_category_include_in_stats") { db in
            try db.execute(sql: """
                ALTER TABLE categories
                ADD COLUMN include_in_stats INTEGER NOT NULL DEFAULT 1;
            """)
        }

        migrator.registerMigration("v4_unify_storage") { db in
            // 1. Update work_sessions table
            try db.execute(sql: "ALTER TABLE work_sessions ADD COLUMN is_manual INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "ALTER TABLE work_sessions ADD COLUMN title TEXT NOT NULL DEFAULT ''")

            // 2. Migrate data from offline_activities
            try db.execute(sql: """
                INSERT INTO work_sessions (start_ts, end_ts, top_apps_json, summary, outcome, created_at, is_manual, title)
                SELECT start_ts, (start_ts + duration_secs * 1000), '[]', '', 'completed', created_at, 1, label
                FROM offline_activities
            """)

            // 3. Drop old tables
            try db.execute(sql: "DROP TABLE offline_activities")
            try db.execute(sql: "DROP TABLE categories")
            try db.execute(sql: "DROP TABLE category_rules")
        }

        migrator.registerMigration("v6_dynamic_categories") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS categories (
                    id    TEXT PRIMARY KEY,
                    name  TEXT NOT NULL,
                    color TEXT NOT NULL,
                    display_order INTEGER NOT NULL DEFAULT 0
                );
                
                INSERT OR IGNORE INTO categories (id, name, color, display_order) VALUES ('focus', '专注工作', '#4A90D9', 0);
                INSERT OR IGNORE INTO categories (id, name, color, display_order) VALUES ('daily', '日常事务', '#52C41A', 1);
                INSERT OR IGNORE INTO categories (id, name, color, display_order) VALUES ('distraction', '其他干扰', '#F5222D', 2);
            """)
        }

        try migrator.migrate(pool)
    }

    // MARK: - Convenience helpers

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try pool.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try pool.write(block)
    }

    func setting(for key: String) -> String? {
        do {
            return try read { db in
                try AppSetting.fetchOne(db, key: key)?.value
            }
        } catch {
            print("[AppDatabase] Failed to read setting '\(key)': \(error)")
            return nil
        }
    }

    func saveSetting(key: String, value: String) {
        do {
            try write { db in
                try AppSetting(key: key, value: value).save(db)
            }
        } catch {
            print("[AppDatabase] Failed to save setting '\(key)': \(error)")
        }
    }

    func allSettings() -> [AppSetting] {
        do {
            return try read { db in
                try AppSetting.fetchAll(db)
            }
        } catch {
            print("[AppDatabase] Failed to read all settings: \(error)")
            return []
        }
    }
    
    /// Returns the daily plan ONLY if it was explicitly set for that exact date.
    /// Used by the history list — does NOT inherit from previous days.
    func exactDailyPlan(for dateString: String) -> String {
        let key = "plan_daily:\(dateString)"
        return setting(for: key) ?? ""
    }

    /// Returns the daily plan for a specific date string (yyyy-MM-dd).
    /// If today's plan is empty, it looks back for the most recent non-empty plan.
    func dailyPlan(for dateString: String) -> String {
        let keyPrefix = "plan_daily:"
        let targetKey = keyPrefix + dateString
        
        do {
            return try read { db in
                // Find latest non-empty plan BEFORE or ON this date
                // We exclude empty strings to ensure real content is inherited
                let sql = """
                    SELECT value FROM settings 
                    WHERE key LIKE '\(keyPrefix)%' 
                    AND key <= ? 
                    AND value != '' 
                    ORDER BY key DESC LIMIT 1
                """
                let found = try String.fetchOne(db, sql: sql, arguments: [targetKey])
                print("[AppDatabase] dailyPlan lookup for \(dateString) -> \(found ?? "nil")")
                return found ?? ""
            }
        } catch {
            print("[AppDatabase] dailyPlan lookup failed: \(error)")
            return ""
        }
    }

    /// Returns the content of the most recent summary record across all dates.
    func latestSummary() -> String {
        do {
            return try read { db in
                let sql = "SELECT content FROM daily_summaries ORDER BY date DESC LIMIT 1"
                return try String.fetchOne(db, sql: sql) ?? ""
            }
        } catch {
            return ""
        }
    }

    func savePlan(date: String, content: String) {
        let key = "plan_daily:\(date)"
        saveSetting(key: key, value: content)
    }
}
