// Seedo/App/AppDelegate.swift
import AppKit
import SwiftUI
import KeyboardShortcuts
import Combine


// Support keyboard input in borderless windows
class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var dashboardWindowController: DashboardWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var afkReturnWindowController: NSWindowController?
    private var deepFocusWindows: [NSWindowController] = []
    private var aiReviewWindowController: NSWindowController?
    private var breakOverlayController: BreakOverlayWindowController?
    let appState = AppState.shared
    private var tracker: ActivityTracker!
    private var refreshTimer: Timer?
    private var statsRefreshTimer: Timer?
    private var obsidianImportTimer: Timer?
    private var autoSummaryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var isStatsRefreshInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        setupMenuBar()
        startTracker()
        
        // Init Break Scheduler
        _ = BreakScheduler.shared
        setupBreakObserver()
        
        scheduleUIRefresh()
        scheduleObsidianAutoImport()
        scheduleAutoDailySummary()
        checkAccessibilityPermission()
        setupShortcuts()
        
        NotificationService.shared.requestAuthorization { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.rescheduleDailyReminders()
                }
            }
        }
        rescheduleDailyReminders()

        // Init Auto Export & Focus Mode
        _ = AutoExportService.shared
        _ = FocusModeService.shared
        
        let usageObserver = NotificationCenter.default.addObserver(forName: .usageReminderTriggered, object: nil, queue: .main) { _ in
            NotificationService.shared.showUsageReminder()
        }
        notificationObservers.append(usageObserver)
        
        setupTrackingObserver()
    }
    
    private func setupTrackingObserver() {
        appState.$isTracking
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.tracker.syncSettings(from: self.appState)
            }
            .store(in: &cancellables)
    }

    private func setupBreakObserver() {
        let breakObserver = NotificationCenter.default.addObserver(forName: .breakShouldStart, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }

            self.closeDeepFocusWindows()

            let userInfo = note.userInfo ?? [:]
            let startTs = (userInfo["startTs"] as? NSNumber)?.int64Value ?? 0
            let endTs = (userInfo["endTs"] as? NSNumber)?.int64Value ?? 0
            let durationSecs = (userInfo["durationSecs"] as? NSNumber)?.doubleValue ?? 0
            let canPostpone = (userInfo["canPostpone"] as? NSNumber)?.boolValue ?? false
            let isLong = (userInfo["isLongBreak"] as? NSNumber)?.boolValue ?? false
            let durMins = (userInfo["durationMins"] as? NSNumber)?.intValue ?? 5
            let idx = (userInfo["sessionIndex"] as? NSNumber)?.intValue ?? 1
            let total = (userInfo["totalSessions"] as? NSNumber)?.intValue ?? 4
            let initialSummary = userInfo["previousSummary"] as? String ?? ""
            let initialNotes = userInfo["previousNotes"] as? String ?? ""
            let initialCategoryId = userInfo["previousCategoryId"] as? String
            
            self.showBreakOverlay(
                startTs: startTs, 
                endTs: endTs, 
                durationSecs: durationSecs, 
                canPostpone: canPostpone,
                isLongBreak: isLong,
                durationMins: durMins,
                sessionIndex: idx,
                totalSessions: total,
                initialSummary: initialSummary,
                initialNotes: initialNotes,
                initialCategoryId: initialCategoryId
            )
        }
        notificationObservers.append(breakObserver)

        let afkReturnObserver = NotificationCenter.default.addObserver(forName: .afkReturnDetected, object: nil, queue: .main) { [weak self] note in
            if let start = note.userInfo?["startTs"] as? Int64,
               let end = note.userInfo?["endTs"] as? Int64 {
                self?.showAFKReturnPopup(start: start, end: end)
            }
        }
        notificationObservers.append(afkReturnObserver)

        let afkThresholdObserver = NotificationCenter.default.addObserver(forName: .afkThresholdReached, object: nil, queue: .main) { [weak self] note in
            if let endTs = note.userInfo?["endTs"] as? Int64 {
                self?.handleAFKThresholdReached(endTs: endTs)
            }
        }
        notificationObservers.append(afkThresholdObserver)

        let sessionSaveObserver = NotificationCenter.default.addObserver(forName: .workSessionDidSave, object: nil, queue: .main) { [weak self] _ in
            self?.refreshTodayStats()
        }
        notificationObservers.append(sessionSaveObserver)
    }

    private func handleAFKThresholdReached(endTs: Int64) {
        // 1. Close break overlay if open
        if breakOverlayController != nil {
            breakOverlayController?.close()
            breakOverlayController = nil
            // Ensure we reset the scheduler state so it doesn't get stuck
            BreakScheduler.shared.isBreakInProgress = false
        }

        // 2. Retroactive pause: subtract AFK threshold from current timer
        let scheduler = BreakScheduler.shared
        scheduler.workElapsedSecsDetailed = max(0, scheduler.workElapsedSecsDetailed - appState.afkThresholdSecs)

        // Force stop tracking in appState
        appState.isTracking = false
        appState.currentSessionStartMs = endTs
        
        // Show the AFK record popup (reusing showAFKReturnPopup logic but for threshold exit)
        // We backward-calculate a start time or just uses current session start
        let startTs = appState.currentSessionStartMs
        showAFKReturnPopup(start: startTs, end: endTs)
        
        // Notify others
        NotificationCenter.default.post(name: .workSessionDidSave, object: nil)
    }

    private func showBreakOverlay(
        startTs: Int64, 
        endTs: Int64, 
        durationSecs: Double, 
        canPostpone: Bool,
        isLongBreak: Bool,
        durationMins: Int,
        sessionIndex: Int,
        totalSessions: Int,
        initialSummary: String = "",
        initialNotes: String = "",
        initialCategoryId: String? = nil
    ) {
        // Close existing if any
        breakOverlayController?.close()
        
        breakOverlayController = BreakOverlayWindowController(
            startTs: startTs, 
            endTs: endTs, 
            durationSecs: durationSecs, 
            canPostpone: canPostpone,
            isLongBreak: isLongBreak,
            durationMins: durationMins,
            sessionIndex: sessionIndex,
            totalSessions: totalSessions,
            initialSummary: initialSummary,
            initialNotes: initialNotes,
            initialCategoryId: initialCategoryId
        )
        breakOverlayController?.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        statsRefreshTimer?.invalidate()
        obsidianImportTimer?.invalidate()
        autoSummaryTimer?.invalidate()
        tracker?.stop()
        cancellables.removeAll()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
    }
    

    // MARK: - Setup

    private func loadSettings() {
        if let thresh = AppDatabase.shared.setting(for: "afk_threshold_secs"),
           let val = Double(thresh) {
            appState.afkThresholdSecs = val
        }
        if let redact = AppDatabase.shared.setting(for: "redact_titles") {
            appState.isRedactTitles = (redact == "true")
        }
    }

    private func setupShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .togglePureFocus) { [weak self] in
            self?.enterDeepFocus()
        }
        
        KeyboardShortcuts.onKeyDown(for: .startPauseFocus) { [weak self] in
            self?.toggleTracking()
        }

        KeyboardShortcuts.onKeyDown(for: .openSettings) { [weak self] in
            self?.showSettingsWindow()
        }
    }
    
    private func rescheduleDailyReminders() {
        if appState.isDailyRemindersEnabled {
            NotificationService.shared.scheduleDailyReminders(times: appState.dailyReminderTimes)
        } else {
            NotificationService.shared.cancelAllDailyReminders()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌱"
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.target = self
        // Enable both left and right click
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: TodayView(appState: appState, openDashboard: { [weak self] tab in
                self?.openDashboard(tab: tab)
            })
            .preferredColorScheme(colorScheme)
        )
    }

    private func startTracker() {
        tracker = ActivityTracker(appState: appState)
        tracker.start()
        // Re-sync cached settings whenever the user saves settings; also
        // kick off an Obsidian import in case the toggle just flipped on.
        let settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidSave, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.tracker.syncSettings(from: self.appState)
            self.runObsidianImportIfEnabled()
            self.rescheduleDailyReminders()
        }
        notificationObservers.append(settingsObserver)
    }

    private func scheduleUIRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarIcon()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }

        statsRefreshTimer?.invalidate()
        statsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.refreshTodayStats()
        }
        if let statsRefreshTimer {
            RunLoop.main.add(statsRefreshTimer, forMode: .common)
        }

        updateMenuBarIcon()
        refreshTodayStats()
    }

    /// Schedules an hourly Obsidian auto-import in addition to an immediate
    /// run on launch. The import is gated on the `obsidian_auto_import` KV
    /// setting so it's a no-op until Fisher explicitly opts in.
    private func scheduleObsidianAutoImport() {
        runObsidianImportIfEnabled()
        obsidianImportTimer?.invalidate()
        obsidianImportTimer = Timer.scheduledTimer(
            withTimeInterval: 3600, repeats: true
        ) { [weak self] _ in
            self?.runObsidianImportIfEnabled()
        }
    }

    private func runObsidianImportIfEnabled() {
        guard AppDatabase.shared.setting(for: "obsidian_auto_import") == "true" else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            do {
                let count = try ObsidianImporter.shared.importToday()
                print("[ObsidianImporter] auto-import: \(count) new activities")
            } catch {
                print("[ObsidianImporter] auto-import failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Auto daily AI summary (Change F)

    /// Fires once a minute to see if the configured trigger time has elapsed
    /// today and the day's summary hasn't been generated yet. Check itself is
    /// cheap (2 setting reads + 2 date-comp comparisons).
    private func scheduleAutoDailySummary() {
        autoSummaryTimer?.invalidate()
        autoSummaryTimer = Timer.scheduledTimer(
            withTimeInterval: 60, repeats: true
        ) { [weak self] _ in
            self?.checkAutoDailySummary()
        }
        // Also check immediately in case the app launched after the trigger
        // time — don't make Fisher wait a minute.
        checkAutoDailySummary()
    }

    private static let autoSummaryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func checkAutoDailySummary() {
        guard AppDatabase.shared.setting(for: "auto_summary_enabled") == "true" else {
            return
        }
        let hour = Int(AppDatabase.shared.setting(for: "auto_summary_hour") ?? "23") ?? 23
        let minute = Int(AppDatabase.shared.setting(for: "auto_summary_minute") ?? "0") ?? 0

        let now = Date()
        let todayStr = Self.autoSummaryDateFormatter.string(from: now)
        let lastRun = AppDatabase.shared.setting(for: "auto_summary_last_run_day") ?? ""
        guard lastRun != todayStr else { return }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let targetMinutes = hour * 60 + minute
        guard nowMinutes >= targetMinutes else { return }

        // Mark as run BEFORE kicking off the job so a failure doesn't retry
        // every minute. Fisher can manually retry via the Stats tab.
        AppDatabase.shared.saveSetting(key: "auto_summary_last_run_day", value: todayStr)

        runAutoDailySummary(todayKey: todayStr)
    }

    /// Builds today's full context and triggers the AI summary.
    private func runAutoDailySummary(todayKey: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let context = try SummaryContextBuilder().build(for: todayKey)
                print("[AutoSummary] firing for \(todayKey) — context built")

                AIService.shared.generateSummary(context: context, periodLabel: "Today") { result in
                    switch result {
                    case .success(let summary):
                        do {
                            try AIService.shared.persistSummary(summary)
                            print("[AutoSummary] saved for \(todayKey)")
                            
                            // Auto-export to Obsidian if configured
                            if AppDatabase.shared.setting(for: "obsidian_vault_path")?.isEmpty == false {
                                try? ObsidianImporter.shared.appendSummary(summary.content)
                                print("[AutoSummary] exported to Obsidian")
                            }
                        } catch {
                            print("[AutoSummary] persist failed: \(error.localizedDescription)")
                        }
                    case .failure(let error):
                        print("[AutoSummary] generate failed: \(error.localizedDescription)")
                        // Rollback the last-run marker so the next tick retries
                        // on failure (e.g., transient API outage).
                        AppDatabase.shared.saveSetting(key: "auto_summary_last_run_day", value: "")
                    }
                }
            } catch {
                print("[AutoSummary] context build failed: \(error.localizedDescription)")
                AppDatabase.shared.saveSetting(key: "auto_summary_last_run_day", value: "")
            }
        }
    }

    private func refreshTodayStats() {
        guard !isStatsRefreshInFlight else { return }
        isStatsRefreshInFlight = true

        let store = EventStore()
        let sessionStore = WorkSessionStore()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            // 1. App usage stats (Today)
            let includedApps = (try? store.todayStats()) ?? []
            
            // 2. Focused sessions sum (Today)
            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: Date())
            let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
            let endMs = Int64(Date().timeIntervalSince1970 * 1000)
            
            let focusSecs = (try? sessionStore.focusedDuration(from: startMs, to: endMs)) ?? 0

            DispatchQueue.main.async {
                self.isStatsRefreshInFlight = false
                self.appState.todayTotalSecs = focusSecs
                self.appState.todayTopApps = Array(includedApps.prefix(BreakConfig.load().topAppsLimit))
                self.updateMenuBarIcon()
            }
        }
    }

    private func updateMenuBarIcon() {
        let scheduler = BreakScheduler.shared
        let elapsed = Int(scheduler.workElapsedSecsDetailed)
        let total = Int(scheduler.workIntervalSecs)
        let displayMins = scheduler.timerMode == .countdown
            ? max(0, (total - elapsed) / 60)
            : elapsed / 60
        let progress = min(1.0, Double(elapsed) / Double(total))
        
        // Pulse effect implementation: vary scale between 0.9 and 1.1 if tracking
        let pulseScale: CGFloat
        if appState.isTracking {
            // Use current second for periodic pulse (1s simple heartbeat)
            let second = Calendar.current.component(.second, from: Date())
            pulseScale = second % 2 == 0 ? 1.05 : 0.95
        } else {
            pulseScale = 1.0
        }

        if let button = statusItem.button {
            button.image = generateProgressImage(progress: progress, text: "\(displayMins)", scale: pulseScale)
            button.imagePosition = .imageOnly
        }
    }

    private func generateProgressImage(progress: Double, text: String, scale: CGFloat = 1.0) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        
        // Using drawingHandler for automatic White/Black mode adaptation
        return NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.width / 2, y: rect.height / 2)
            let baseRect = rect.insetBy(dx: 2, dy: 2)
            
            // Adjust radius for pulse
            let radius = (baseRect.width / 2) * scale
            let pulseRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

            // 1. Background full green circle
            let bgPath = NSBezierPath(ovalIn: pulseRect)
            NSColor.systemGreen.withAlphaComponent(0.2).setStroke()
            bgPath.lineWidth = 1.2
            bgPath.stroke()
            
            // 2. Remaining progress arc in Red
            let startAngle: CGFloat = 90
            let endAngle: CGFloat = 90 - CGFloat((1.0 - progress) * 360)
            let arcPath = NSBezierPath()
            arcPath.appendArc(withCenter: center, radius: radius, startAngle: endAngle, endAngle: startAngle)
            
            NSColor.systemRed.setStroke()
            arcPath.lineWidth = 2.0
            arcPath.lineCapStyle = .round
            arcPath.stroke()
            
            // 3. Percentage/Remaining Text
            let font = NSFont.monospacedDigitSystemFont(ofSize: 8 * scale, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor // Auto-adapts to menu bar theme
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: center.x - (textSize.width / 2),
                y: center.y - (textSize.height / 2),
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
            
            return true
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        checkAccessibilityPermission()
    }

    private func checkAccessibilityPermission() {
        appState.hasAccessibilityPermission = WindowInfoProvider.isPermissionGranted
        if !appState.hasAccessibilityPermission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                WindowInfoProvider.requestPermission()
            }
        }
    }

    // MARK: - Actions

    @objc private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Re-activate app to ensure focus
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Force focus on the popover window
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置", action: #selector(showSettingsWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "详细统计", action: #selector(openStats), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "手动添加记录", action: #selector(addManualRecord), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "纯专注模式", action: #selector(enterDeepFocus), keyEquivalent: "d"))
        let trackingTitle = appState.isTracking ? "暂停追踪" : "开始追踪"
        menu.addItem(NSMenuItem(title: trackingTitle, action: #selector(toggleTracking), keyEquivalent: "p"))
        
        if appState.isTracking {
            menu.addItem(NSMenuItem(title: "结束并记录", action: #selector(stopAndRecord), keyEquivalent: "r"))
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        // Final strict icon removal pass
        for item in menu.items {
            item.image = nil
        }
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // Reset so next left-click doesn't show menu
    }

    @objc func openStats() {
        openDashboard(tab: .stats)
    }

    @objc func showSettingsWindow() {
        print("[AppDelegate] Attempting to show settings window...")
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: appState)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        
        // Ensure it's visible if it was hidden
        if let window = settingsWindowController?.window, !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func addManualRecord() {
        openDashboard(tab: .stats)
        NotificationCenter.default.post(name: .shouldShowAddActivity, object: nil)
    }

    @objc private func todayAISummary() {
        NotificationCenter.default.post(name: .shouldRunAISummary, object: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleTracking() {
        appState.isTracking.toggle()
    }

    @objc private func stopAndRecord() {
        let duration = appState.currentDurationSecs
        appState.isTracking = false
        resetTracking()
        openDashboard(tab: .stats)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: .shouldShowAddActivity, object: duration)
        }
    }

    private func openDashboard(tab: DashboardTab) {
        popover.performClose(nil)
        
        if tab == .settings {
            showSettingsWindow()
            return
        }
        appState.selectedTab = tab
        
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(appState: appState)
        }
        dashboardWindowController?.showWindow(nil)
        dashboardWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func enterDeepFocus() {
        appState.isDeepFocusActive = true
        BreakScheduler.shared.enterDeepFocusSurface()
        
        if deepFocusWindows.isEmpty {
            for screen in NSScreen.screens {
                let isPrimary = screen == NSScreen.main
                let view = DeepFocusView(appState: appState, onClose: { [weak self] in
                    self?.closeDeepFocusWindows()
                }, isPrimary: isPrimary)
                
                let controller = NSHostingController(rootView: view)
                let window = KeyWindow(contentViewController: controller)
                window.styleMask = [.borderless, .fullSizeContentView]
                window.level = .screenSaver // Absolute top level
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.collectionBehavior = [.canJoinAllSpaces]
                window.setFrame(screen.frame, display: true)
                
                let winController = NSWindowController(window: window)
                deepFocusWindows.append(winController)
                winController.showWindow(nil)
            }
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeDeepFocusWindows() {
        for controller in deepFocusWindows {
            controller.close()
        }
        deepFocusWindows.removeAll()
        appState.isDeepFocusActive = false
        BreakScheduler.shared.exitDeepFocusSurface()
    }

    private func showAFKReturnPopup(start: Int64, end: Int64) {
        if afkReturnWindowController != nil {
            afkReturnWindowController?.close()
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.setFrameAutosaveName("AFKReturnWindow")
        
        if window.setFrameUsingName("AFKReturnWindow") == false {
            window.center()
        }
        
        let view = AFKReturnView(
            startTs: start,
            endTs: end,
            onSave: { [weak self] (session: WorkSession) in
                self?.saveOfflineActivity(session: session)
                self?.afkReturnWindowController?.close()
                self?.afkReturnWindowController = nil
                self?.finalizeAFKReturn()
            },
            onDismiss: { [weak self] in
                self?.afkReturnWindowController?.close()
                self?.afkReturnWindowController = nil
                self?.finalizeAFKReturn()
            }
        )
        
        window.contentView = NSHostingView(rootView: view)
        
        afkReturnWindowController = NSWindowController(window: window)
        afkReturnWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    private func finalizeAFKReturn() {
        let elapsed = BreakScheduler.shared.workElapsedSecsDetailed
        if elapsed > 0 {
            let alert = NSAlert()
            alert.messageText = "继续上一个计时？"
            alert.informativeText = "检测到之前有一个正在进行的 \(Int(elapsed / 60)) 分钟计时。您想继续吗？"
            alert.addButton(withTitle: "继续")
            alert.addButton(withTitle: "重新开始")

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                BreakScheduler.shared.resetWork()
            }
        }
        appState.isTracking = true
    }

    func showTransientAISummary(context: String, label: String, onSave: ((String) -> Void)? = nil) {
        // This is for manual triggers: display in window, NO SAVE to DB or Obsidian
        DispatchQueue.main.async {
            let view = AIReviewView(content: context, label: label, onSave: onSave, onClose: { [weak self] in
                self?.aiReviewWindowController?.close()
                self?.aiReviewWindowController = nil
            })
            
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "AI 深度复盘 - \(label)"
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            
            self.aiReviewWindowController = NSWindowController(window: window)
            self.aiReviewWindowController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func saveOfflineActivity(session: WorkSession) {
        var mutableSession = session
        try? WorkSessionStore().insert(&mutableSession)
        NotificationCenter.default.post(name: .workSessionDidSave, object: nil)
    }

    /// Resets the current tracking session to zero — used for 'Record and Reset'
    func resetTracking() {
        tracker.reset()
        BreakScheduler.shared.resetWork() // Reset break countdown too
        appState.currentSessionStartMs = Int64(Date().timeIntervalSince1970 * 1000)
        refreshTodayStats()
        updateMenuBarIcon()
    }

    private var colorScheme: ColorScheme? {
        switch appState.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
