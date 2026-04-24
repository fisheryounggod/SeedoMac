// Seedo/Data/WorkSessionStore.swift
import Foundation
import GRDB

final class WorkSessionStore {
    private let db: any DatabaseWriter & DatabaseReader

    convenience init() { self.init(db: AppDatabase.shared.pool) }
    init(db: some DatabaseWriter & DatabaseReader) { self.db = db }

    func insert(_ session: inout WorkSession) throws {
        try db.write { d in try session.insert(d) }
        // Sync to calendar
        CalendarSyncService.shared.sync(session: session)
    }

    func update(_ session: WorkSession) throws {
        try db.write { d in try session.update(d) }
        // Sync to calendar
        CalendarSyncService.shared.sync(session: session)
    }

    func delete(id: Int64) throws {
        // Find session first to delete from calendar
        if let session = try db.read({ d in try WorkSession.fetchOne(d, key: id) }) {
            CalendarSyncService.shared.delete(session: session)
        }
        try db.write { d in try WorkSession.deleteOne(d, key: id) }
    }

    /// Fetches sessions starting within the given timestamp range (Unix ms).
    func sessions(from startMs: Int64, to endMs: Int64) throws -> [WorkSession] {
        try db.read { d in
            try WorkSession
                .filter(Column("start_ts") >= startMs && Column("start_ts") < endMs)
                .order(Column("start_ts").asc)
                .fetchAll(d)
        }
    }

    /// Fetches all sessions for a specific date (YYYY-MM-DD).
    func sessions(for dateStr: String) throws -> [WorkSession] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let day = f.date(from: dateStr) else { return [] }
        let startMs = Int64(day.timeIntervalSince1970 * 1000)
        let endMs   = startMs + 86_400_000
        return try sessions(from: startMs, to: endMs)
    }

    // MARK: - Daily Summary (Moved from OfflineStore)

    func saveSummary(_ summary: DailySummary) throws {
        try db.write { d in try summary.save(d) }
    }

    func deleteSummary(date: String) throws {
        try db.write { d in _ = try DailySummary.deleteOne(d, key: date) }
    }

    func summary(for date: String) throws -> DailySummary? {
        try db.read { d in try DailySummary.fetchOne(d, key: date) }
    }

    func allSummaries() throws -> [DailySummary] {
        try db.read { d in
            try DailySummary.order(Column("date").desc).fetchAll(d)
        }
    }
    
    /// Fetches summaries for days that have sessions in the given timeframe.
    func summaries(from startMs: Int64, to endMs: Int64) throws -> [DailySummary] {
        try db.read { d in
            // Map timestamps to YYYY-MM-DD to match DailySummary keys
            let dates = try Row.fetchAll(d, sql: """
                SELECT DISTINCT strftime('%Y-%m-%d', start_ts / 1000, 'unixepoch', 'localtime') AS day
                FROM work_sessions
                WHERE start_ts >= ? AND start_ts < ?
            """, arguments: [startMs, endMs]).map { $0["day"] as String }
            
            return try DailySummary
                .filter(dates.contains(Column("date")))
                .order(Column("date").asc)
                .fetchAll(d)
        }
    }

    // MARK: - Import / Export Helpers
    
    func allSessions() throws -> [WorkSession] {
        try db.read { d in try WorkSession.order(Column("start_ts").desc).fetchAll(d) }
    }
    
    func allCategories() throws -> [SessionCategory] {
        try db.read { d in try SessionCategory.order(Column("display_order").asc).fetchAll(d) }
    }
    
    func bulkInsertSessions(_ sessions: [WorkSession]) throws {
        try db.write { d in
            for var s in sessions {
                // Remove ID to avoid PK conflicts, let GRDB handle it
                s.id = nil
                try s.insert(d)
            }
        }
    }
    
    func bulkInsertSummaries(_ summaries: [DailySummary]) throws {
        try db.write { d in
            for s in summaries {
                try s.save(d) // save() handles insert or update
            }
        }
    }
    
    func bulkInsertCategories(_ categories: [SessionCategory]) throws {
        try db.write { d in
            for var c in categories {
                try c.save(d)
            }
        }
    }

    // MARK: - Unified Logs
    
    /// Distinct calendar days (YYYY-MM-DD) that have sessions or summaries, newest first.
    func deduplicate() throws -> Int {
        try db.write { d in
            try d.execute(sql: """
                DELETE FROM work_sessions
                WHERE id NOT IN (
                    SELECT MIN(id)
                    FROM work_sessions
                    GROUP BY start_ts, end_ts, summary, category_id
                )
            """)
            return d.changesCount
        }
    }

    /// Distinct calendar days (YYYY-MM-DD) that have sessions or summaries, newest first.
    func allLogDates() throws -> [String] {
        try db.read { d in
            let rows = try Row.fetchAll(d, sql: """
                SELECT DISTINCT strftime('%Y-%m-%d', start_ts / 1000, 'unixepoch', 'localtime') AS day
                FROM work_sessions
                ORDER BY day DESC
            """)
            return rows.map { $0["day"] as String }
        }
    }
}
