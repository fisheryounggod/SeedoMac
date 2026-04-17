// SeedoMac/App/AppDelegate.swift
import AppKit
import SwiftUI
import KeyboardShortcuts


// Support keyboard input in borderless windows
class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var dashboardWindowController: DashboardWindowController?
    private var afkReturnPopover: NSPopover?
    private var deepFocusWindowController: NSWindowController?
    let appState = AppState()
    private var tracker: ActivityTracker!
    private var refreshTimer: Timer?
    private var obsidianImportTimer: Timer?
    private var autoSummaryTimer: Timer?
    private var breakOverlayController: BreakOverlayWindowController?

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
    }

    private func setupBreakObserver() {
        NotificationCenter.default.addObserver(forName: .breakShouldStart, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            guard let startTs = note.userInfo?["startTs"] as? Int64,
                  let endTs = note.userInfo?["endTs"] as? Int64,
                  let durationSecs = note.userInfo?["durationSecs"] as? Double,
                  let canPostpone = note.userInfo?["canPostpone"] as? Bool,
                  let isLong = note.userInfo?["isLongBreak"] as? Bool,
                  let durMins = note.userInfo?["durationMins"] as? Int,
                  let idx = note.userInfo?["sessionIndex"] as? Int,
                  let total = note.userInfo?["totalSessions"] as? Int else { return }
            
            self.showBreakOverlay(
                startTs: startTs, 
                endTs: endTs, 
                durationSecs: durationSecs, 
                canPostpone: canPostpone,
                isLongBreak: isLong,
                durationMins: durMins,
                sessionIndex: idx,
                totalSessions: total
            )
        }

        NotificationCenter.default.addObserver(forName: .afkReturnDetected, object: nil, queue: .main) { [weak self] note in
            if let start = note.userInfo?["startTs"] as? Int64,
               let end = note.userInfo?["endTs"] as? Int64 {
                self?.showAFKReturnPopup(start: start, end: end)
            }
        }
    }
    
    private func showBreakOverlay(
        startTs: Int64, 
        endTs: Int64, 
        durationSecs: Double, 
        canPostpone: Bool,
        isLongBreak: Bool,
        durationMins: Int,
        sessionIndex: Int,
        totalSessions: Int
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
            totalSessions: totalSessions
        )
        breakOverlayController?.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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
            // Toggle today's status
            let current = (AppDatabase.shared.setting(for: "break_disabled_day") ?? "") != DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            if current {
                let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                AppDatabase.shared.saveSetting(key: "break_disabled_day", value: todayStr)
            } else {
                AppDatabase.shared.saveSetting(key: "break_disabled_day", value: "")
            }
            BreakScheduler.shared.refreshConfig()
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
        popover.contentSize = NSSize(width: 320, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: TodayView(appState: appState, openDashboard: { [weak self] in
                self?.openDashboard(tab: .stats)
            })
        )
    }

    private func startTracker() {
        tracker = ActivityTracker(appState: appState)
        tracker.start()
        // Re-sync cached settings whenever the user saves settings; also
        // kick off an Obsidian import in case the toggle just flipped on.
        NotificationCenter.default.addObserver(
            forName: .settingsDidSave, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.tracker.syncSettings(from: self.appState)
            self.runObsidianImportIfEnabled()
        }
    }

    private func scheduleUIRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshTodayStats()
        }
        refreshTodayStats()  // immediate first load
    }

    /// Schedules an hourly Obsidian auto-import in addition to an immediate
    /// run on launch. The import is gated on the `obsidian_auto_import` KV
    /// setting so it's a no-op until Fisher explicitly opts in.
    private func scheduleObsidianAutoImport() {
        runObsidianImportIfEnabled()
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
        let store = EventStore()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let includedApps = (try? store.todayStats()) ?? []
            let total = includedApps.reduce(0.0) { $0 + $1.totalSecs }

            DispatchQueue.main.async {
                self.appState.todayTotalSecs = total
                self.appState.todayTopApps = Array(includedApps.prefix(10))

                // Update menu bar title
                let hrs  = Int(total) / 3600
                let mins = (Int(total) % 3600) / 60
                self.statusItem.button?.title = hrs > 0 ? "🌱\(hrs)h\(mins)m" : "🌱\(mins)m"
            }
        }
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "详细统计", action: #selector(openStats), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ";"))
        menu.addItem(NSMenuItem(title: "手动添加记录", action: #selector(addManualRecord), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "今日AI总结", action: #selector(todayAISummary), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "纯专注模式", action: #selector(enterDeepFocus), keyEquivalent: "d"))
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

    @objc private func openStats() {
        openDashboard(tab: .stats)
    }

    @objc private func openSettings() {
        openDashboard(tab: .stats)
        // Ensure settings sheet is triggered. 
        // We'll broadcast a notification that StatsView listens to.
        NotificationCenter.default.post(name: .shouldShowSettings, object: nil)
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

    private func openDashboard(tab: DashboardTab) {
        popover.performClose(nil)
        appState.selectedTab = tab
        
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(appState: appState)
        }
        dashboardWindowController?.showWindow(nil)
        dashboardWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func enterDeepFocus() {
        if deepFocusWindowController == nil {
            let view = DeepFocusView(appState: appState, onClose: { [weak self] in
                self?.deepFocusWindowController?.close()
                self?.deepFocusWindowController = nil
            })
            let controller = NSHostingController(rootView: view)
            let window = KeyWindow(contentViewController: controller)
            window.styleMask = [.borderless, .fullSizeContentView]
            window.level = .mainMenu + 1 // High level
            window.isOpaque = false
            window.backgroundColor = .clear
            
            deepFocusWindowController = NSWindowController(window: window)
        }
        
        deepFocusWindowController?.window?.setFrame(NSScreen.main?.frame ?? .zero, display: true)
        deepFocusWindowController?.showWindow(nil)
        deepFocusWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAFKReturnPopup(start: Int64, end: Int64) {
        if afkReturnPopover == nil {
            afkReturnPopover = NSPopover()
            afkReturnPopover?.behavior = .transient
        }
        
        afkReturnPopover?.contentViewController = NSHostingController(
            rootView: AFKReturnView(
                startTs: start,
                endTs: end,
                onSave: { [weak self] summary in
                    self?.saveOfflineActivity(start: start, end: end, summary: summary)
                    self?.afkReturnPopover?.performClose(nil)
                },
                onDismiss: { [weak self] in
                    self?.afkReturnPopover?.performClose(nil)
                }
            )
        )
        
        if let button = statusItem.button {
            afkReturnPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func saveOfflineActivity(start: Int64, end: Int64, summary: String) {
        var session = WorkSession(
            startTs: start,
            endTs: end,
            topAppsJson: "[]",
            summary: summary,
            outcome: "completed",
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        try? WorkSessionStore().insert(&session)
        NotificationCenter.default.post(name: .workSessionDidSave, object: nil)
    }
}
