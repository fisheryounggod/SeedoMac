// Seedo/State/AppState.swift
import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()
    
    // Tracking status
    @Published var isTracking: Bool = true
    @Published var currentApp: String = ""
    @Published var currentTitle: String = ""
    @Published var currentURL: String = ""
    @Published var currentSessionStartMs: Int64 = 0

    @Published var isDeepFocusActive: Bool = false
    
    // Today summary (refreshed every 5s)
    @Published var todayTotalSecs: Double = 0
    @Published var todayTopApps: [AppStat] = []

    // UI State
    @Published var selectedTab: DashboardTab = .stats

    // Permissions
    @Published var hasAccessibilityPermission: Bool = false

    // Settings (loaded from DB on startup)
    @Published var afkThresholdSecs: Double = 900   // 15 min default
    @Published var isRedactTitles: Bool = false
    @Published var appearance: String = "system"   // system, light, dark
    @Published var todayGoal: String = ""

    // Reminders
    @Published var isUsageReminderEnabled: Bool = false
    @Published var usageReminderThresholdMins: Int = 60
    @Published var isDailyRemindersEnabled: Bool = false
    @Published var dailyReminderTimes: [Date] = []

    init() {
        print("[AppState] Initializing AppState...")
        
        self.afkThresholdSecs = Double(AppDatabase.shared.setting(for: "afk_threshold_secs") ?? "900") ?? 900
        self.isRedactTitles = AppDatabase.shared.setting(for: "redact_titles") == "true"
        self.appearance = AppDatabase.shared.setting(for: "appearance") ?? "system"
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let todayStr = df.string(from: Date())
        
        self.todayGoal = AppDatabase.shared.dailyPlan(for: todayStr)
        print("[AppState] Initial goal loaded: '\(todayGoal)'")

        // Load Reminders
        self.isUsageReminderEnabled = AppDatabase.shared.setting(for: "usage_reminder_enabled") == "true"
        self.usageReminderThresholdMins = Int(AppDatabase.shared.setting(for: "usage_reminder_threshold_mins") ?? "60") ?? 60
        self.isDailyRemindersEnabled = AppDatabase.shared.setting(for: "daily_reminders_enabled") == "true"
        if let json = AppDatabase.shared.setting(for: "daily_reminder_times"),
           let data = json.data(using: .utf8),
           let times = try? JSONDecoder().decode([Date].self, from: data) {
            self.dailyReminderTimes = times
        }
    }

    // Computed: how long the current session has been running
    var currentDurationSecs: Double {
        guard currentSessionStartMs > 0 else { return 0 }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return Double(nowMs - currentSessionStartMs) / 1000.0
    }
}
