// SeedoMac/Tracker/ActivityTracker.swift
import AppKit
import Combine

final class ActivityTracker {
    private let appState: AppState
    private let eventStore: EventStore
    private var timer: DispatchSourceTimer?
    private var flushTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "tech.seedo.tracker", qos: .utility)
    private lazy var buffer = SessionBuffer { [weak self] events in
        self?.flush(events)
    }
    private var isAFK = false

    init(appState: AppState,
         eventStore: EventStore = EventStore()) {
        self.appState = appState
        self.eventStore = eventStore
    }

    func start() {
        // 1s activity tick
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .seconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t

        // 30s periodic flush
        let ft = DispatchSource.makeTimerSource(queue: queue)
        ft.schedule(deadline: .now() + 30, repeating: .seconds(30))
        ft.setEventHandler { [weak self] in self?.buffer.flushAll() }
        ft.resume()
        flushTimer = ft

        // Flush on app quit (prevents data loss)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.buffer.flushAll()
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        flushTimer?.cancel()
        flushTimer = nil
        buffer.flushAll()
    }

    // MARK: - Private

    private func tick() {
        guard appState.isTracking else { return }

        // AFK detection using CoreGraphics idle time
        let idleSecs = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        if idleSecs > appState.afkThresholdSecs {
            if !isAFK { isAFK = true }
            return
        }
        isAFK = false

        // Frontmost app info
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appName  = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? ""
        let pid      = app.processIdentifier

        // Window title via Accessibility API (gracefully degrades if no permission)
        let rawTitle = WindowInfoProvider.getTitle(pid: pid) ?? ""
        let title    = appState.isRedactTitles ? "" : rawTitle

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        buffer.process(app: appName, title: title, bundleId: bundleId, nowMs: nowMs)

        // Update shared state on main thread for UI
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.currentApp = appName
            self.appState.currentTitle = title
            // Only update session start if the buffer's current event is still for the same app
            if self.buffer.currentEvent?.appOrDomain == appName {
                self.appState.currentSessionStartMs = self.buffer.currentEvent?.startTs ?? nowMs
            } else {
                self.appState.currentSessionStartMs = nowMs
            }
            self.appState.hasAccessibilityPermission = WindowInfoProvider.isPermissionGranted
        }
    }

    private func flush(_ events: [Event]) {
        guard !events.isEmpty else { return }
        do {
            try eventStore.bulkInsert(events)
        } catch {
            print("[ActivityTracker] Failed to flush \(events.count) events: \(error)")
        }
    }
}
