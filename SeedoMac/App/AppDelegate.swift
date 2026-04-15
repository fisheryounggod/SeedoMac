// SeedoMac/App/AppDelegate.swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var dashboardWindowController: DashboardWindowController?
    let appState = AppState()
    private var tracker: ActivityTracker!
    private var refreshTimer: Timer?
    private var obsidianImportTimer: Timer?
    private var autoSummaryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        setupMenuBar()
        startTracker()
        scheduleUIRefresh()
        scheduleObsidianAutoImport()
        scheduleAutoDailySummary()
        checkAccessibilityPermission()
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

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌱"
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: TodayView(appState: appState, openDashboard: { [weak self] in
                self?.openDashboard()
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

    /// Builds today's app/category/total data using the same pipeline as
    /// StatsView (with excluded-category filtering), calls AIService, and
    /// persists the result silently on success.
    private func runAutoDailySummary(todayKey: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let cal = Calendar.current
            let now = Date()
            let start = cal.startOfDay(for: now)
            let startMs = Int64(start.timeIntervalSince1970 * 1000)
            let endMs = Int64(now.timeIntervalSince1970 * 1000)

            let rawApps = (try? EventStore().topApps(
                startMs: startMs, endMs: endMs, limit: 50
            )) ?? []
            let catStore = CategoryStore()

            // Match + filter excluded categories, same semantics as refreshTodayStats
            var catMap: [String: Category?] = [:]
            for app in rawApps {
                catMap[app.appOrDomain] = try? catStore.matchCategory(
                    for: app.appOrDomain, title: ""
                )
            }
            let includedApps = rawApps.filter { app in
                if let cat = catMap[app.appOrDomain] ?? nil, cat.includeInStats == false {
                    return false
                }
                return true
            }
            let limitedApps = Array(includedApps.prefix(10))

            // Build category totals over the INCLUDED apps only
            var catTotals: [String: (name: String, color: String, secs: Double)] = [:]
            for app in includedApps {
                if let cat = catMap[app.appOrDomain] ?? nil, cat.includeInStats {
                    var entry = catTotals[cat.id] ?? (cat.name, cat.color, 0.0)
                    entry.secs += app.totalSecs
                    catTotals[cat.id] = entry
                }
            }
            let catStats: [CategoryStat] = catTotals
                .map { CategoryStat(id: $0.key, name: $0.value.name,
                                    color: $0.value.color, totalSecs: $0.value.secs) }
                .sorted { $0.totalSecs > $1.totalSecs }
            let totalSecs = includedApps.reduce(0.0) { $0 + $1.totalSecs }

            print("[AutoSummary] firing for \(todayKey) — \(limitedApps.count) apps, \(catStats.count) cats")

            AIService.shared.generateSummary(
                periodKey: todayKey,
                periodLabel: "Today",
                apps: limitedApps,
                categories: catStats,
                totalSecs: totalSecs
            ) { result in
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
        }
    }

    private func refreshTodayStats() {
        let store = EventStore()
        let catStore = CategoryStore()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let rawApps = (try? store.todayStats()) ?? []

            // Filter out apps whose matched category is excluded from stats
            var includedApps: [AppStat] = []
            var catTotals: [String: (name: String, color: String, secs: Double)] = [:]
            for app in rawApps {
                let matched = try? catStore.matchCategory(for: app.appOrDomain, title: "")
                if let cat = matched, cat.includeInStats == false { continue }
                includedApps.append(app)
                if let cat = matched {
                    var entry = catTotals[cat.id] ?? (cat.name, cat.color, 0.0)
                    entry.secs += app.totalSecs
                    catTotals[cat.id] = entry
                }
            }
            let total = includedApps.reduce(0.0) { $0 + $1.totalSecs }
            let catStats = catTotals
                .map { CategoryStat(id: $0.key, name: $0.value.name,
                                    color: $0.value.color, totalSecs: $0.value.secs) }
                .sorted { $0.totalSecs > $1.totalSecs }

            DispatchQueue.main.async {
                self.appState.todayTotalSecs = total
                self.appState.todayCategoryStats = catStats
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

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openDashboard() {
        popover.performClose(nil)
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(appState: appState)
        }
        dashboardWindowController?.showWindow(nil)
        dashboardWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
