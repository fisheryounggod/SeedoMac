// Seedo/Tracker/ActivityTracker.swift
import AppKit
import Combine

final class ActivityTracker {
    private let appState: AppState
    private let eventStore: EventStore
    private var timer: DispatchSourceTimer?
    private var flushTimer: DispatchSourceTimer?
    private var terminationObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "tech.seedo.tracker", qos: .utility)
    private lazy var buffer = SessionBuffer { [weak self] events in
        self?.flush(events)
    }
    private var isAFK = false

    // Cached settings — only written from main thread, read from tracker queue
    private var _isTracking: Bool = true
    private var _afkThreshold: Double = 900
    private var _isRedactTitles: Bool = false

    // Title caching — only refresh every 2s to reduce Accessibility API overhead
    private var _cachedTitle: String = ""
    private var _cachedURL: String = ""
    private var _lastTitleFetchTime: Int64 = 0
    private let _titleFetchIntervalMs: Int64 = 2000

    // URL fail cooldown — skip AX tree walk for 5s after an empty result
    private var _lastURLFailTime: Int64 = 0
    private let _urlFailCooldownMs: Int64 = 5000

    // Permission check — only re-check every 10s on tracker queue, post to main only on change
    private var _cachedPermission: Bool = false
    private var _lastPermissionCheckTime: Int64 = 0
    private let _permissionCheckIntervalMs: Int64 = 10_000

    // Usage reminder tracking
    private var continuousActiveSecs: Double = 0
    private var _isUsageReminderEnabled: Bool = false
    private var _usageReminderThresholdSecs: Double = 3600

    init(appState: AppState,
         eventStore: EventStore = EventStore()) {
        self.appState = appState
        self.eventStore = eventStore
    }

    /// Call from main thread when settings change.
    func syncSettings(from appState: AppState) {
        _isTracking     = appState.isTracking
        _afkThreshold   = appState.afkThresholdSecs
        _isRedactTitles = appState.isRedactTitles
        
        _isUsageReminderEnabled = appState.isUsageReminderEnabled
        _usageReminderThresholdSecs = Double(appState.usageReminderThresholdMins * 60)
    }

    private func checkAFK() {
        let idleSecs = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        let newAFK = idleSecs >= _afkThreshold
        
        // Debug logging for weird idle times
        if idleSecs > 3600 && !isAFK {
            print("[ActivityTracker] Warning: unusually high idle time detected: \(idleSecs)s")
        }

        if newAFK && !isAFK && _isTracking {
            print("[ActivityTracker] AFK threshold reached: \(idleSecs)s >= \(_afkThreshold)s")
            // First time hitting threshold while tracking
            let endTs = Int64(Date().timeIntervalSince1970 * 1000) - Int64(idleSecs * 1000)
            NotificationCenter.default.post(
                name: .afkThresholdReached,
                object: nil,
                userInfo: ["endTs": endTs]
            )
        }
        
        if newAFK != isAFK {
            isAFK = newAFK
            print("[ActivityTracker] isAFK changed to: \(isAFK) (idle: \(Int(idleSecs))s)")
            NotificationCenter.default.post(
                name: .afkStateDidChange,
                object: nil,
                userInfo: ["isAFK": isAFK]
            )
        }
    }

    func start() {
        guard timer == nil, flushTimer == nil else { return }

        // Snapshot current settings on the main thread before the timer fires
        syncSettings(from: appState)

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
        terminationObserver = NotificationCenter.default.addObserver(
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
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        buffer.flushAll()
    }

    deinit {
        stop()
    }

    /// Clears the current session buffer — used for 'Record and Reset'
    func reset() {
        buffer.flushAll()
    }

    // MARK: - Private

    private func tick() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Fix #1: AX permission check on tracker queue every 10s; post to main only on change.
        // Was: AXIsProcessTrusted() dispatched to main thread every second (TCC syscall → input lag).
        if nowMs - _lastPermissionCheckTime >= _permissionCheckIntervalMs {
            _lastPermissionCheckTime = nowMs
            let granted = WindowInfoProvider.isPermissionGranted
            if granted != _cachedPermission {
                _cachedPermission = granted
                DispatchQueue.main.async { [weak self] in
                    self?.appState.hasAccessibilityPermission = granted
                }
            }
        }

        // Always check AFK to track continuous active time
        checkAFK()

        if isAFK {
            continuousActiveSecs = 0
            return
        }

        if _isTracking {
            continuousActiveSecs = 0
        } else {
            continuousActiveSecs += 1
            if _isUsageReminderEnabled && continuousActiveSecs >= _usageReminderThresholdSecs {
                NotificationCenter.default.post(name: .usageReminderTriggered, object: nil)
                continuousActiveSecs = 0
            }
        }

        guard _isTracking else { return }

        // Frontmost app info
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appName  = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? ""
        let pid      = app.processIdentifier

        // Window title via Accessibility API — only fetch every 2s to reduce CPU overhead
        let title: String
        if _isRedactTitles {
            title = ""
            _cachedTitle = ""
        } else if nowMs - _lastTitleFetchTime >= _titleFetchIntervalMs {
            let rawTitle = WindowInfoProvider.getTitle(pid: pid) ?? ""
            _cachedTitle = rawTitle.isEmpty ? _cachedTitle : rawTitle
            _lastTitleFetchTime = nowMs
            title = _cachedTitle
        } else {
            title = _cachedTitle
        }

        // Fix #3: URL fail cooldown — skip AX tree walk for 5s after an empty result.
        // Was: retried expensive AX tree traversal every second when browser didn't expose URL.
        let currentURL: String
        if !_isRedactTitles && BrowserURLProvider.isBrowser(bundleId: bundleId) {
            if nowMs - _lastTitleFetchTime < _titleFetchIntervalMs && !_cachedURL.isEmpty {
                currentURL = _cachedURL
            } else if _cachedURL.isEmpty && nowMs - _lastURLFailTime < _urlFailCooldownMs {
                currentURL = ""
            } else {
                let url = BrowserURLProvider.getURL(pid: pid, bundleId: bundleId) ?? ""
                if url.isEmpty { _lastURLFailTime = nowMs }
                _cachedURL = url
                currentURL = url
            }
        } else {
            currentURL = ""
            _cachedURL = ""
        }

        buffer.process(app: appName, title: title, url: currentURL, bundleId: bundleId, nowMs: nowMs)

        // Fix #2: Read buffer.currentEvent once here on the tracker queue.
        // Was: main thread called queue.sync twice per second, blocking on DB writes.
        let sessionStartMs = (buffer.currentEvent?.appOrDomain == appName)
            ? (buffer.currentEvent?.startTs ?? nowMs)
            : nowMs

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.appState.currentApp != appName { self.appState.currentApp = appName }
            if self.appState.currentTitle != title { self.appState.currentTitle = title }
            if self.appState.currentURL != currentURL { self.appState.currentURL = currentURL }
            if self.appState.currentSessionStartMs != sessionStartMs {
                self.appState.currentSessionStartMs = sessionStartMs
            }
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

extension Notification.Name {
    static let afkStateDidChange = Notification.Name("tech.seedo.afkStateDidChange")
    static let afkThresholdReached = Notification.Name("tech.seedo.afkThresholdReached")
    static let workSessionDidSave = Notification.Name("tech.seedo.workSessionDidSave")
    static let breakShouldStart   = Notification.Name("tech.seedo.breakShouldStart")
    static let afkReturnDetected  = Notification.Name("tech.seedo.afkReturnDetected")
    static let shouldShowSettings = Notification.Name("tech.seedo.shouldShowSettings")
    static let shouldShowAddActivity = Notification.Name("tech.seedo.shouldShowAddActivity")
    static let shouldRunAISummary = Notification.Name("tech.seedo.shouldRunAISummary")
    static let usageReminderTriggered = Notification.Name("tech.seedo.usageReminderTriggered")
}
