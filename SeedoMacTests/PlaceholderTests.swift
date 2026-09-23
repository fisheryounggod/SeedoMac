import XCTest
@testable import SeedoMac

final class ManualRecordPrefillTests: XCTestCase {
    func testDefaultDurationStartsNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = AddActivitySheet.prefill(duration: nil, now: now)
        XCTAssertEqual(result.start, now)
        XCTAssertEqual(result.minutes, 30)
    }

    func testCrossMidnightUsesPreviousDate() {
        let now = ISO8601DateFormatter().date(from: "2026-09-18T00:10:00Z")!
        let result = AddActivitySheet.prefill(duration: 1800, now: now)
        let expected = ISO8601DateFormatter().date(from: "2026-09-17T23:40:00Z")!
        XCTAssertEqual(result.start, expected)
        XCTAssertEqual(result.minutes, 30)
    }

    func testInvalidDurationsUseDefault() {
        let now = Date()
        for duration in [Double.nan, .infinity, -.infinity, -60, 0] {
            let result = AddActivitySheet.prefill(duration: duration, now: now)
            XCTAssertEqual(result.start, now)
            XCTAssertEqual(result.minutes, 30)
        }
    }

    func testDurationBounds() {
        let now = Date()
        XCTAssertEqual(AddActivitySheet.prefill(duration: 1, now: now).minutes, 1)
        let result = AddActivitySheet.prefill(duration: Double.greatestFiniteMagnitude, now: now)
        XCTAssertEqual(result.minutes, 1440)
        XCTAssertEqual(result.start, now.addingTimeInterval(-86_400))
    }
}

final class TaskTimerModeTests: XCTestCase {
    func testSwitchingModeForSameTaskPreservesElapsedTime() {
        let scheduler = BreakScheduler.shared
        let previousTracking = AppState.shared.isTracking
        AppState.shared.isTracking = false
        defer {
            scheduler.resetWork()
            AppState.shared.isTracking = previousTracking
        }

        scheduler.resetWork()
        scheduler.startTask("研究推进", mode: .countdown)
        scheduler.workElapsedSecsDetailed = 325

        scheduler.startTask("研究推进", mode: .stopwatch)

        XCTAssertEqual(scheduler.boundTaskTitle, "研究推进")
        XCTAssertEqual(scheduler.timerMode, .stopwatch)
        XCTAssertEqual(scheduler.workElapsedSecsDetailed, 325)
    }

    func testStartingDifferentTaskCreatesFreshTimer() {
        let scheduler = BreakScheduler.shared
        let previousTracking = AppState.shared.isTracking
        AppState.shared.isTracking = false
        defer {
            scheduler.resetWork()
            AppState.shared.isTracking = previousTracking
        }

        scheduler.resetWork()
        scheduler.startTask("研究推进", mode: .countdown)
        scheduler.workElapsedSecsDetailed = 325

        scheduler.startTask("整理文献", mode: .stopwatch)

        XCTAssertEqual(scheduler.boundTaskTitle, "整理文献")
        XCTAssertEqual(scheduler.timerMode, .stopwatch)
        XCTAssertEqual(scheduler.workElapsedSecsDetailed, 0)
    }
}
