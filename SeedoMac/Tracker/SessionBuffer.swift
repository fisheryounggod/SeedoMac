// SeedoMac/Tracker/SessionBuffer.swift
import Foundation

final class SessionBuffer {
    private(set) var currentEvent: Event?
    private var pending: [Event] = []
    private let flushHandler: ([Event]) -> Void

    var pendingCount: Int { pending.count }

    init(flushHandler: @escaping ([Event]) -> Void) {
        self.flushHandler = flushHandler
    }

    func process(app: String, title: String, bundleId: String, nowMs: Int64) {
        let sameSession = currentEvent.map { $0.appOrDomain == app && $0.title == title } ?? false

        if sameSession {
            currentEvent?.endTs = nowMs
        } else {
            if let finished = currentEvent {
                pending.append(finished)
            }
            currentEvent = Event(startTs: nowMs, endTs: nowMs, appOrDomain: app,
                                 bundleId: bundleId.isEmpty ? nil : bundleId, title: title)
            if pending.count >= 10 {
                flushHandler(pending)
                pending.removeAll()
            }
        }
    }

    /// Called every 30s and on app quit. Emits pending + current to flushHandler.
    func flushAll() {
        var toFlush = pending
        if let curr = currentEvent { toFlush.append(curr) }
        pending.removeAll()
        currentEvent = nil
        if !toFlush.isEmpty { flushHandler(toFlush) }
    }
}
