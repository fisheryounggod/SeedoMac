// SeedoMac/BreakReminder/BreakConfig.swift
import Foundation

struct BreakConfig {
    /// Total focused work time in minutes before a break is required.
    var workIntervalMins: Int
    /// Short break duration in minutes.
    var breakDurationMins: Int
    /// Long break duration in minutes.
    var longBreakDurationMins: Int
    /// Number of sessions before a long break is required.
    var longBreakFrequency: Int
    /// Whether the break reminder is enabled today.
    var isEnabledToday: Bool
    /// Whether long breaks are enabled in the cycle.
    var isLongBreakEnabled: Bool
    /// Background color hex string.
    var backgroundColorHex: String
    /// Custom background image path.
    var backgroundImagePath: String?
    
    static func load() -> BreakConfig {
        let work = Int(AppDatabase.shared.setting(for: "break_work_interval_mins") ?? "45") ?? 45
        let dur  = Int(AppDatabase.shared.setting(for: "break_duration_mins") ?? "5") ?? 5
        let lDur = Int(AppDatabase.shared.setting(for: "break_long_duration_mins") ?? "15") ?? 15
        let freq = Int(AppDatabase.shared.setting(for: "break_long_frequency") ?? "4") ?? 4
        
        let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let disabledDay = AppDatabase.shared.setting(for: "break_disabled_day") ?? ""
        let bgHex = AppDatabase.shared.setting(for: "break_background_hex") ?? "#000000"
        let bgImg = AppDatabase.shared.setting(for: "break_background_image_path")
        let lEnabled = AppDatabase.shared.setting(for: "break_long_enabled") != "false"
        
        return BreakConfig(
            workIntervalMins: work,
            breakDurationMins: dur,
            longBreakDurationMins: lDur,
            longBreakFrequency: freq,
            isEnabledToday: disabledDay != todayStr,
            isLongBreakEnabled: lEnabled,
            backgroundColorHex: bgHex,
            backgroundImagePath: bgImg
        )
    }
}
