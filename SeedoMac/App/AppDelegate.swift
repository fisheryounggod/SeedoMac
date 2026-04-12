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

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        setupMenuBar()
        startTracker()
        scheduleUIRefresh()
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
    }

    private func scheduleUIRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshTodayStats()
        }
        refreshTodayStats()  // immediate first load
    }

    private func refreshTodayStats() {
        let store = EventStore()
        let catStore = CategoryStore()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let apps = (try? store.todayStats()) ?? []
            let total = apps.reduce(0.0) { $0 + $1.totalSecs }

            // Group apps into categories
            var catTotals: [String: (name: String, color: String, secs: Double)] = [:]
            for app in apps {
                if let cat = try? catStore.matchCategory(for: app.appOrDomain, title: "") {
                    var entry = catTotals[cat.id] ?? (cat.name, cat.color, 0.0)
                    entry.secs += app.totalSecs
                    catTotals[cat.id] = entry
                }
            }
            let catStats = catTotals
                .map { CategoryStat(id: $0.key, name: $0.value.name,
                                    color: $0.value.color, totalSecs: $0.value.secs) }
                .sorted { $0.totalSecs > $1.totalSecs }

            DispatchQueue.main.async {
                self.appState.todayTotalSecs = total
                self.appState.todayCategoryStats = catStats
                self.appState.todayTopApps = Array(apps.prefix(10))

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
