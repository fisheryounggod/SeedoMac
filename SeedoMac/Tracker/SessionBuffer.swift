// SeedoMac/Tracker/SessionBuffer.swift
import Foundation

final class SessionBuffer {
    private let queue = DispatchQueue(label: "tech.seedo.SessionBuffer", qos: .utility)
    private var _currentEvent: Event?
    private var _pending: [Event] = []
    private let flushHandler: ([Event]) -> Void

    var currentEvent: Event? { queue.sync { _currentEvent } }
    var pendingCount: Int    { queue.sync { _pending.count } }

    init(flushHandler: @escaping ([Event]) -> Void) {
        self.flushHandler = flushHandler
    }

    func process(app: String, title: String, url: String, bundleId: String, nowMs: Int64) {
        var batchToFlush: [Event]? = nil
        queue.sync {
            let currentURL = _currentEvent?.url ?? ""
            let sameSession = _currentEvent.map {
                $0.appOrDomain == app && $0.title == title && currentURL == url
            } ?? false

            if sameSession {
                _currentEvent?.endTs = nowMs
            } else {
                if let finished = _currentEvent {
                    _pending.append(finished)
                }
                var newEvent = Event(startTs: nowMs, endTs: nowMs, appOrDomain: app,
                                     bundleId: bundleId.isEmpty ? nil : bundleId, title: title)
                newEvent.url = url.isEmpty ? nil : url
                _currentEvent = newEvent
                if _pending.count >= 10 {
                    batchToFlush = _pending
                    _pending.removeAll()
                }
            }
        }
        // Call handler OUTSIDE the lock to avoid deadlock
        if let batch = batchToFlush {
            flushHandler(batch)
        }
    }

    /// Called every 30s and on app quit. Emits pending + current to flushHandler.
    func flushAll() {
        var toFlush: [Event] = []
        queue.sync {
            if let curr = _currentEvent { toFlush.append(curr) }
            toFlush += _pending
            _currentEvent = nil
            _pending.removeAll()
        }
        if !toFlush.isEmpty {
            flushHandler(toFlush)
        }
    }
}
