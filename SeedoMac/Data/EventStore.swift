// Seedo/Data/EventStore.swift
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

    private static let heatmapFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Write

    func insert(_ event: inout Event) throws {
        try db.write { d in try event.insert(d) }
    }

    func bulkInsert(_ events: [Event]) throws {
        guard !events.isEmpty else { return }
        try db.write { d in
            var previous = try Event
                .order(Column("start_ts").desc, Column("id").desc)
                .fetchOne(d)

            for event in events.sorted(by: { $0.startTs < $1.startTs }) {
                if let previousID = previous?.id,
                   canCoalesce(previous, with: event) {
                    let mergedEnd = max(previous?.endTs ?? event.endTs, event.endTs)
                    try d.execute(
                        sql: "UPDATE events SET end_ts = ? WHERE id = ?",
                        arguments: [mergedEnd, previousID]
                    )
                    previous?.endTs = mergedEnd
                    continue
                }

                var mutableEvent = event
                try mutableEvent.insert(d)
                previous = mutableEvent
            }
        }
    }

    private func canCoalesce(_ previous: Event?, with next: Event) -> Bool {
        guard let previous else { return false }
        let gapMs = next.startTs - previous.endTs
        return gapMs >= 0 && gapMs <= 5_000
            && previous.source == next.source
            && previous.appOrDomain == next.appOrDomain
            && previous.bundleId == next.bundleId
            && previous.title == next.title
            && previous.url == next.url
            && previous.path == next.path
            && previous.pageType == next.pageType
            && previous.isRedacted == next.isRedacted
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
                FROM   events INDEXED BY idx_events_end_ts
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
                FROM   events INDEXED BY idx_events_end_ts
                WHERE  start_ts < ? AND end_ts > ?
                GROUP  BY day
            """, arguments: [endMs, startMs, endMs, startMs])

            return rows.compactMap { row -> HeatmapDay? in
                let dateStr: String = row["day"]
                let totalSecs: Double = row["total_secs"]
                guard let date = Self.heatmapFormatter.date(from: dateStr) else { return nil }
                let weekday = (cal.component(.weekday, from: date) + 5) % 7  // 0=Mon
                let weekOfYear = cal.component(.weekOfYear, from: date) - 1
                return HeatmapDay(date: dateStr, totalSecs: totalSecs,
                                  weekIndex: weekOfYear, weekdayIndex: weekday)
            }
        }
    }

    func topApps(startMs: Int64, endMs: Int64, limit: Int = 10) throws -> [AppStat] {
        try db.read { d in
            let rows = try Row.fetchAll(d, sql: """
                SELECT app_or_domain,
                       SUM((MIN(end_ts, ?) - MAX(start_ts, ?)) / 1000.0) AS total_secs
                FROM   events INDEXED BY idx_events_end_ts
                WHERE  start_ts < ? AND end_ts > ?
                GROUP  BY app_or_domain
                ORDER  BY total_secs DESC
                LIMIT  ?
            """, arguments: [endMs, startMs, endMs, startMs, max(0, limit)])
            return rows.map { AppStat(appOrDomain: $0["app_or_domain"], totalSecs: $0["total_secs"]) }
        }
    }

    func topURLs(startMs: Int64, endMs: Int64, limit: Int = 10) throws -> [(url: String, totalSecs: Double)] {
        try db.read { d in
            let rows = try Row.fetchAll(d, sql: """
                SELECT url,
                       SUM((MIN(end_ts, ?) - MAX(start_ts, ?)) / 1000.0) AS total_secs
                FROM   events INDEXED BY idx_events_end_ts
                WHERE  start_ts < ? AND end_ts > ?
                  AND  url IS NOT NULL AND url != ''
                GROUP  BY url
                ORDER  BY total_secs DESC
                LIMIT  ?
            """, arguments: [endMs, startMs, endMs, startMs, limit])
            return rows.map { (url: $0["url"] as String, totalSecs: $0["total_secs"] as Double) }
        }
    }
}
