// SeedoMac/State/AppState.swift
import Foundation
import Combine

final class AppState: ObservableObject {
    // Tracking status
    @Published var isTracking: Bool = true
    @Published var currentApp: String = ""
    @Published var currentTitle: String = ""
    @Published var currentURL: String = ""
    @Published var currentSessionStartMs: Int64 = 0

    // Today summary (refreshed every 5s)
    @Published var todayTotalSecs: Double = 0
    @Published var todayCategoryStats: [CategoryStat] = []
    @Published var todayTopApps: [AppStat] = []
    @Published var todayTimelineEvents: [TimelineEvent] = []

    // Permissions
    @Published var hasAccessibilityPermission: Bool = false

    // Settings (loaded from DB on startup)
    @Published var afkThresholdSecs: Double = 900   // 15 min default
    @Published var isRedactTitles: Bool = false

    // Computed: how long the current session has been running
    var currentDurationSecs: Double {
        guard currentSessionStartMs > 0 else { return 0 }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return Double(nowMs - currentSessionStartMs) / 1000.0
    }
}
