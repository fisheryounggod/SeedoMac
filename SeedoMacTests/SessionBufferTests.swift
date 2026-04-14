// SeedoMacTests/SessionBufferTests.swift
import XCTest
@testable import SeedoMac

final class SessionBufferTests: XCTestCase {
    func test_sameApp_extendsCurrentSession() {
        var flushed: [Event] = []
        let buf = SessionBuffer { events in flushed.append(contentsOf: events) }

        buf.process(app: "Xcode", title: "main.swift", url: "", bundleId: "com.apple.dt.Xcode", nowMs: 1000)
        buf.process(app: "Xcode", title: "main.swift", url: "", bundleId: "com.apple.dt.Xcode", nowMs: 2000)
        buf.process(app: "Xcode", title: "main.swift", url: "", bundleId: "com.apple.dt.Xcode", nowMs: 3000)

        XCTAssertEqual(flushed.count, 0, "Same app should not flush")
        let current = buf.currentEvent
        XCTAssertEqual(current?.appOrDomain, "Xcode")
        XCTAssertEqual(current?.startTs, 1000)
        XCTAssertEqual(current?.endTs, 3000)
    }

    func test_differentApp_startsNewSession() {
        var flushed: [Event] = []
        let buf = SessionBuffer { events in flushed.append(contentsOf: events) }

        buf.process(app: "Xcode",  title: "main.swift", url: "", bundleId: "com.apple.dt.Xcode", nowMs: 1000)
        buf.process(app: "Xcode",  title: "main.swift", url: "", bundleId: "com.apple.dt.Xcode", nowMs: 3000)
        buf.process(app: "Safari", title: "GitHub",     url: "", bundleId: "com.apple.Safari",   nowMs: 4000)

        XCTAssertEqual(buf.pendingCount, 1)   // Xcode session is pending (not yet flushed)
        XCTAssertEqual(buf.currentEvent?.appOrDomain, "Safari")
    }

    func test_flushAll_emitsEverything() {
        var flushed: [Event] = []
        let buf = SessionBuffer { events in flushed.append(contentsOf: events) }

        buf.process(app: "Xcode",  title: "", url: "", bundleId: "", nowMs: 1000)
        buf.process(app: "Safari", title: "", url: "", bundleId: "", nowMs: 2000)
        buf.flushAll()

        XCTAssertEqual(flushed.count, 2)
        XCTAssertEqual(buf.pendingCount, 0)
        XCTAssertNil(buf.currentEvent)
    }

    func test_tenPending_triggersAutoFlush() {
        var flushed: [Event] = []
        let buf = SessionBuffer { events in flushed.append(contentsOf: events) }

        // 11 distinct app switches → 10 pending auto-flush at switch #11
        for i in 0..<11 {
            buf.process(app: "App\(i)", title: "", url: "", bundleId: "", nowMs: Int64(i * 1000))
        }

        XCTAssertEqual(flushed.count, 10)
        XCTAssertEqual(buf.pendingCount, 0)
    }
}
