// SeedoMacTests/EventStoreTests.swift
import XCTest
import GRDB
@testable import SeedoMac

final class EventStoreTests: XCTestCase {
    var db: DatabaseQueue!
    var store: EventStore!

    override func setUp() {
        super.setUp()
        db = try! DatabaseQueue()
        try! db.write { d in
            try d.execute(sql: """
                CREATE TABLE events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source TEXT NOT NULL DEFAULT 'desktop',
                    start_ts INTEGER NOT NULL,
                    end_ts INTEGER NOT NULL,
                    app_or_domain TEXT NOT NULL,
                    bundle_id TEXT,
                    title TEXT NOT NULL DEFAULT '',
                    url TEXT, path TEXT, page_type TEXT,
                    is_redacted INTEGER NOT NULL DEFAULT 0
                );
            """)
        }
        store = EventStore(db: db)
    }

    func test_insertAndFetch() throws {
        var event = Event(startTs: 1000, endTs: 5000, appOrDomain: "Xcode", title: "main.swift")
        try store.insert(&event)
        XCTAssertNotNil(event.id)

        let fetched = try store.recentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].appOrDomain, "Xcode")
    }

    func test_statsByRange_sumsCorrectly() throws {
        let baseMs: Int64 = 1_700_000_000_000  // arbitrary fixed time
        var e1 = Event(startTs: baseMs, endTs: baseMs + 3_600_000, appOrDomain: "Xcode", title: "")
        var e2 = Event(startTs: baseMs + 3_600_000, endTs: baseMs + 5_400_000, appOrDomain: "Slack", title: "")
        try store.insert(&e1)
        try store.insert(&e2)

        let stats = try store.statsByRange(startMs: baseMs, endMs: baseMs + 10_000_000)
        let xcodeTotal = stats.first(where: { $0.appOrDomain == "Xcode" })?.totalSecs ?? 0
        let slackTotal = stats.first(where: { $0.appOrDomain == "Slack" })?.totalSecs ?? 0
        XCTAssertEqual(xcodeTotal, 3600.0, accuracy: 1.0)
        XCTAssertEqual(slackTotal, 1800.0, accuracy: 1.0)
    }

    func test_heatmapData_groupsByDay() throws {
        // 2025-01-01 00:00:00 UTC in ms
        let jan1Ms: Int64 = 1_735_689_600_000
        var e = Event(startTs: jan1Ms, endTs: jan1Ms + 7_200_000, appOrDomain: "Xcode", title: "")
        try store.insert(&e)

        let days = try store.heatmapData(year: 2025)
        XCTAssertFalse(days.isEmpty)
        // The exact date string depends on local timezone; just check a day in Jan 2025 appears
        let jan = days.first(where: { $0.date.hasPrefix("2025-01") })
        XCTAssertNotNil(jan)
        XCTAssertGreaterThan(jan!.totalSecs, 0)
    }

    func test_topApps_respectsLimit() throws {
        let baseMs: Int64 = 1_700_000_000_000
        for i in 0..<15 {
            var e = Event(startTs: baseMs + Int64(i) * 60_000,
                          endTs: baseMs + Int64(i) * 60_000 + 30_000,
                          appOrDomain: "App\(i)", title: "")
            try store.insert(&e)
        }
        let top5 = try store.topApps(startMs: baseMs, endMs: baseMs + 1_000_000_000, limit: 5)
        XCTAssertEqual(top5.count, 5)
    }
}
