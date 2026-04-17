// SeedoMac/BreakReminder/BreakScheduler.swift
import Foundation
import Combine

final class BreakScheduler: ObservableObject {
    static let shared = BreakScheduler()
    
    @Published var workElapsedSecsDetailed: Double = 0
    var workElapsedSecs: Int { Int(workElapsedSecsDetailed) }
    
    var workIntervalSecs: Double {
        Double(config.workIntervalMins * 60)
    }
    
    private var config = BreakConfig.load()
    private var timer: Timer?
    private var isAFK = false
    private var afkStartTs: Date?
    private var isBreakInProgress = false
    private var postponedOnce = false
    
    /// Tracks how many focus sessions have been completed since the last long break.
    @Published var sessionsSinceLongBreak: Int = UserDefaults.standard.integer(forKey: "break_session_count")
    
    private init() {
        setupObservers()
        startTimer()
    }
    
    func refreshConfig() {
        self.config = BreakConfig.load()
    }
    
    var isLongBreak: Bool {
        sessionsSinceLongBreak >= config.longBreakFrequency - 1
    }
 
    private func setupObservers() {
        NotificationCenter.default.addObserver(forName: .afkStateDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            if let isAFK = note.userInfo?["isAFK"] as? Bool {
                if isAFK {
                    self.afkStartTs = Date()
                    print("[BreakScheduler] User went AFK at \(self.afkStartTs!)")
                } else if let start = self.afkStartTs {
                    let duration = Date().timeIntervalSince(start)
                    print("[BreakScheduler] User returned after \(Int(duration))s")
                    
                    // If away for more than the threshold, it's a "significant absence"
                    if duration >= self.appStateThreshold() {
                        self.handleReturnFromSignificantAbsence(start: start, end: Date())
                    }
                    self.afkStartTs = nil
                }
                
                self.isAFK = isAFK
                print("[BreakScheduler] isAFK: \(isAFK)")
            }
        }
    }

    private func appStateThreshold() -> Double {
        // Fallback to 15 mins if not found
        let secsStr = AppDatabase.shared.setting(for: "afk_threshold_secs") ?? "900"
        return Double(secsStr) ?? 900
    }

    private func handleReturnFromSignificantAbsence(start: Date, end: Date) {
        print("[BreakScheduler] Significant absence detected. Interrupting session.")
        
        // Broadcast for the UI to show the AFK Return popup
        NotificationCenter.default.post(
            name: .afkReturnDetected,
            object: nil,
            userInfo: [
                "startTs": Int64(start.timeIntervalSince1970 * 1000),
                "endTs": Int64(end.timeIntervalSince1970 * 1000)
            ]
        )
        
        // Reset the timer as requested ("restart timing")
        self.resetWork()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    private func tick() {
        guard config.isEnabledToday else { return }
        guard !isBreakInProgress else { return }
        
        if !isAFK {
            workElapsedSecsDetailed += 1
            
            let threshold = Double(config.workIntervalMins * 60)
            if workElapsedSecsDetailed >= threshold {
                triggerBreak()
            }
        }
    }
    
    private func triggerBreak() {
        print("[BreakScheduler] Threshold reached! Triggering break.")
        isBreakInProgress = true
        
        // Prepare session draft
        let startTs = Int64((Date().timeIntervalSince1970 - workElapsedSecsDetailed) * 1000)
        let endTs   = Int64(Date().timeIntervalSince1970 * 1000)
        
        let willBeLong = isLongBreak
        let durationMins = willBeLong ? config.longBreakDurationMins : config.breakDurationMins
        
        // Broadcast for the OverlayWindowController to pick up
        NotificationCenter.default.post(
            name: .breakShouldStart,
            object: nil,
            userInfo: [
                "startTs": startTs,
                "endTs": endTs,
                "durationSecs": workElapsedSecsDetailed,
                "canPostpone": !postponedOnce,
                "isLongBreak": willBeLong,
                "durationMins": durationMins,
                "sessionIndex": sessionsSinceLongBreak + 1,
                "totalSessions": config.longBreakFrequency
            ]
        )
    }
    
    // MARK: - Handlers from UI
    
    func startBreak() {
        // Transition to resting logic in UI
    }
    
    func endBreak(summary: String, outcome: String, startTs: Int64, endTs: Int64) {
        // Persistence
        var session = WorkSession(
            startTs: startTs,
            endTs: endTs,
            topAppsJson: fetchTopAppsJson(start: startTs, end: endTs),
            summary: summary,
            outcome: outcome,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        try? WorkSessionStore().insert(&session)
        NotificationCenter.default.post(name: .workSessionDidSave, object: nil)
        
        // Sync to Calendar
        CalendarSyncService.shared.sync(session: session)
        
        // Update session tracking
        if outcome == "completed" {
            if isLongBreak {
                sessionsSinceLongBreak = 0
            } else {
                sessionsSinceLongBreak += 1
            }
            UserDefaults.standard.set(sessionsSinceLongBreak, forKey: "break_session_count")
        }
        
        // Reset
        resetWork()
        postponedOnce = false
        isBreakInProgress = false
    }
    
    func postponeBreak() {
        postponedOnce = true
        workElapsedSecsDetailed = Double((config.workIntervalMins - 5) * 60) // Back off 5 mins
        isBreakInProgress = false
    }
    
    func skipBreak(summary: String, startTs: Int64, endTs: Int64) {
        endBreak(summary: summary, outcome: "skipped", startTs: startTs, endTs: endTs)
    }
    
    func disableToday() {
        AppDatabase.shared.saveSetting(key: "break_disabled_day", 
                                      value: DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))
        refreshConfig()
        resetWork()
        isBreakInProgress = false
    }
    
    private func resetWork() {
        workElapsedSecsDetailed = 0
    }
    
    private func fetchTopAppsJson(start: Int64, end: Int64) -> String {
        let apps = (try? EventStore().topApps(startMs: start, endMs: end, limit: 10)) ?? []
        struct RawStat: Codable { let appOrDomain: String; let totalSecs: Double }
        let raw = apps.map { RawStat(appOrDomain: $0.appOrDomain, totalSecs: $0.totalSecs) }
        let data = (try? JSONEncoder().encode(raw)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
