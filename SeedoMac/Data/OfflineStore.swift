// SeedoMac/Data/OfflineStore.swift
import Foundation
import GRDB

final class OfflineStore {
    private let db: any DatabaseWriter & DatabaseReader

    convenience init() { self.init(db: AppDatabase.shared.pool) }
    init(db: some DatabaseWriter & DatabaseReader) { self.db = db }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func insert(_ activity: inout OfflineActivity) throws {
        try db.write { d in try activity.insert(d) }
    }

    func activities(for date: String) throws -> [OfflineActivity] {
        // date: YYYY-MM-DD
        guard let day = Self.dayFormatter.date(from: date) else { return [] }
        let startMs = Int64(day.timeIntervalSince1970 * 1000)
        let endMs   = startMs + 86_400_000
        return try db.read { d in
            try OfflineActivity
                .filter(Column("start_ts") >= startMs && Column("start_ts") < endMs)
                .order(Column("start_ts"))
                .fetchAll(d)
        }
    }

    func delete(id: Int64) throws {
        try db.write { d in try OfflineActivity.deleteOne(d, key: id) }
    }

    func saveSummary(_ summary: DailySummary) throws {
        try db.write { d in try summary.save(d) }
    }

    func deleteSummary(date: String) throws {
        try db.write { d in _ = try DailySummary.deleteOne(d, key: date) }
    }

    func summary(for date: String) throws -> DailySummary? {
        try db.read { d in try DailySummary.fetchOne(d, key: date) }
    }

    /// All DailySummary rows, newest first.
    func allSummaries() throws -> [DailySummary] {
        try db.read { d in
            try DailySummary.order(Column("date").desc).fetchAll(d)
        }
    }

    /// Distinct calendar days (YYYY-MM-DD) that have offline activities, newest first.
    func allActivityDates() throws -> [String] {
        try db.read { d in
            let rows = try Row.fetchAll(d, sql: """
                SELECT DISTINCT strftime('%Y-%m-%d', start_ts / 1000, 'unixepoch', 'localtime') AS day
                FROM offline_activities ORDER BY day DESC
            """)
            return rows.map { $0["day"] as String }
        }
    }
}
