// SeedoMac/Data/EventStore.swift
import Foundation
import GRDB

final class EventStore {
    private let db: any DatabaseWriter & DatabaseReader

    // Production init using shared AppDatabase
    convenience init() {
        self.init(db: AppDatabase.shared.pool)
    }

    // Testable init accepting any GRDB database
    init(db: some DatabaseWriter & DatabaseReader) {
        self.db = db
    }

    // MARK: - Write

    func insert(_ event: inout Event) throws {
        try db.write { d in try event.insert(d) }
    }

    func bulkInsert(_ events: [Event]) throws {
        var copy = events
        try db.write { d in
            for i in copy.indices { try copy[i].insert(d) }
        }
    }

    // MARK: - Read

    func recentEvents(limit: Int) throws -> [Event] {
        try db.read { d in
            try Event.order(Column("start_ts").desc).limit(limit).fetchAll(d)
        }
    }

    /// Returns [AppStat] for the given time range (local midnight → now for today)
    func todayStats() throws -> [AppStat] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let nowMs   = Int64(Date().timeIntervalSince1970 * 1000)
        return try statsByRange(startMs: startMs, endMs: nowMs)
    }

    func statsByRange(startMs: Int64, endMs: Int64) throws -> [AppStat] {
        try db.read { d in
            let rows = try Row.fetchAll(d, sql: """
                SELECT app_or_domain,
                       SUM((MIN(end_ts, ?) - MAX(start_ts, ?)) / 1000.0) AS total_secs
                FROM   events
                WHERE  start_ts < ? AND end_ts > ?
                GROUP  BY app_or_domain
                ORDER  BY total_secs DESC
            """, arguments: [endMs, startMs, endMs, startMs])
            return rows.map { AppStat(appOrDomain: $0["app_or_domain"], totalSecs: $0["total_secs"]) }
        }
    }

    /// Returns one HeatmapDay per calendar day in `year` that has any data
    func heatmapData(year: Int) throws -> [HeatmapDay] {
        let cal = Calendar.current
        var comps = DateComponents(year: year, month: 1, day: 1)
        guard let yearStart = cal.date(from: comps) else { return [] }
        comps.year = year + 1
        guard let yearEnd = cal.date(from: comps) else { return [] }

        let startMs = Int64(yearStart.timeIntervalSince1970 * 1000)
        let endMs   = Int64(yearEnd.timeIntervalSince1970 * 1000)

        return try db.read { d in
            let rows = try Row.fetchAll(d, sql: """
                SELECT
                    strftime('%Y-%m-%d', start_ts / 1000, 'unixepoch', 'localtime') AS day,
                    SUM((MIN(end_ts, ?) - MAX(start_ts, ?)) / 1000.0)              AS total_secs
                FROM   events
                WHERE  start_ts < ? AND end_ts > ?
                GROUP  BY day
            """, arguments: [endMs, startMs, endMs, startMs])

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            return rows.compactMap { row -> HeatmapDay? in
                let dateStr: String = row["day"]
                let totalSecs: Double = row["total_secs"]
                guard let date = formatter.date(from: dateStr) else { return nil }
                let weekday = (cal.component(.weekday, from: date) + 5) % 7  // 0=Mon
                let weekOfYear = cal.component(.weekOfYear, from: date) - 1
                return HeatmapDay(date: dateStr, totalSecs: totalSecs,
                                  weekIndex: weekOfYear, weekdayIndex: weekday)
            }
        }
    }

    func topApps(startMs: Int64, endMs: Int64, limit: Int = 10) throws -> [AppStat] {
        let all = try statsByRange(startMs: startMs, endMs: endMs)
        return Array(all.prefix(limit))
    }
}
