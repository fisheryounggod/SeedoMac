// Seedo/BreakReminder/BreakScheduler.swift
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
    @Published var isDeepFocusActive: Bool = false
    @Published var isFocusActive: Bool = true // Enabled by default as "Normal Mode"
    
    /// Tracks how many focus sessions have been completed since the last long break.
    @Published var sessionsSinceLongBreak: Int = UserDefaults.standard.integer(forKey: "break_session_count")
    
    // Accumulation state for "Skip Break" logic
    private var accumulatedWorkSecs: Double = 0
    private var lastSkippedSummary: String = ""
    private var lastSkippedNotes: String = ""
    private var lastSkippedCategoryId: String? = nil
    private var sessionStartTs: Int64?
    
    private init() {
        loadPersistence()
        setupObservers()
        startTimer()
    }
    
    func refreshConfig() {
        self.config = BreakConfig.load()
    }
    
    var isLongBreak: Bool {
        guard config.isLongBreakEnabled else { return false }
        return sessionsSinceLongBreak >= config.longBreakFrequency - 1
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
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Ensure timer keeps ticking during window dragging/scrolling
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    private func tick() {
        // Only tick if focus is active, tracking is on, and break isn't in progress
        guard isFocusActive && AppState.shared.isTracking else { return }
        guard !isBreakInProgress else { return }
        
        // Even if disabled today from automatic break reminders, 
        // we still track "Focus Time" for the MenuBar ring.
        // But if enabled, we also check for break thresholds.
        
        if !isAFK {
            if workElapsedSecsDetailed == 0 && accumulatedWorkSecs == 0 {
                sessionStartTs = Int64(Date().timeIntervalSince1970 * 1000)
            }
            workElapsedSecsDetailed += 1
            
            // Persist every 5 seconds to avoid over-saving while keeping it responsive
            if Int(workElapsedSecsDetailed) % 5 == 0 {
                savePersistence()
            }
            
            if config.isEnabledToday {
                let threshold = Double(config.workIntervalMins * 60)
                if workElapsedSecsDetailed >= threshold {
                    triggerBreak()
                }
            }
        }
    }
    
    private func triggerBreak() {
        print("[BreakScheduler] Threshold reached! Triggering break.")
        isBreakInProgress = true
        
        // Prepare session draft
        let totalElapsed = workElapsedSecsDetailed + accumulatedWorkSecs
        let startTs = sessionStartTs ?? Int64((Date().timeIntervalSince1970 - totalElapsed) * 1000)
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
                "durationSecs": totalElapsed,
                "canPostpone": !postponedOnce,
                "isLongBreak": willBeLong,
                "durationMins": durationMins,
                "sessionIndex": sessionsSinceLongBreak + 1,
                "totalSessions": config.longBreakFrequency,
                "previousSummary": lastSkippedSummary,
                "previousNotes": lastSkippedNotes,
                "previousCategoryId": lastSkippedCategoryId
            ]
        )
    }
    
    // MARK: - Handlers from UI
    
    func startBreak() {
        // Transition to resting logic in UI
    }
    
    func endBreak(summary: String, title: String = "", categoryId: String? = nil, outcome: String, startTs: Int64, endTs: Int64) {
        // Persistence
        var session = WorkSession(
            startTs: startTs,
            endTs: endTs,
            topAppsJson: fetchTopAppsJson(start: startTs, end: endTs),
            summary: summary,
            outcome: outcome,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            title: title,
            categoryId: categoryId
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
        savePersistence()
        isBreakInProgress = false
    }
    
    func skipBreak(summary: String, title: String = "", categoryId: String? = nil, startTs: Int64, endTs: Int64) {
        // Accumulate duration and preserve content for the next prompt
        accumulatedWorkSecs += workElapsedSecsDetailed
        lastSkippedSummary = summary
        lastSkippedNotes = title
        lastSkippedCategoryId = categoryId
        
        // Reset only the current interval, but keep isBreakInProgress false to resume tracking
        workElapsedSecsDetailed = 0
        isBreakInProgress = false
        savePersistence()
    }
    
    func disableToday() {
        AppDatabase.shared.saveSetting(key: "break_disabled_day", 
                                      value: DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))
        refreshConfig()
        resetWork()
        isBreakInProgress = false
    }
    
    func resetWork() {
        workElapsedSecsDetailed = 0
        accumulatedWorkSecs = 0
        lastSkippedSummary = ""
        lastSkippedNotes = ""
        lastSkippedCategoryId = nil
        sessionStartTs = nil
        postponedOnce = false
        clearPersistence()
    }
    
    // MARK: - Persistence
    
    private let kElapsedKey = "focus_timer_elapsed"
    private let kPostponedKey = "focus_timer_postponed"
    private let kLastSavedKey = "focus_timer_last_saved"

    private func savePersistence() {
        let defaults = UserDefaults.standard
        defaults.set(workElapsedSecsDetailed, forKey: kElapsedKey)
        defaults.set(postponedOnce, forKey: kPostponedKey)
        defaults.set(Int64(Date().timeIntervalSince1970), forKey: kLastSavedKey)
    }
    
    private func loadPersistence() {
        let defaults = UserDefaults.standard
        let lastSaved = defaults.integer(forKey: kLastSavedKey)
        let now = Int64(Date().timeIntervalSince1970)
        
        // Only resume if the session was active within the last 4 hours
        // This prevents resuming a session from yesterday.
        if lastSaved > 0 && (now - Int64(lastSaved)) < (4 * 3600) {
            self.workElapsedSecsDetailed = defaults.double(forKey: kElapsedKey)
            self.postponedOnce = defaults.bool(forKey: kPostponedKey)
            print("[BreakScheduler] Recovered session: \(workElapsedSecsDetailed)s elapsed")
        }
    }
    
    private func clearPersistence() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: kElapsedKey)
        defaults.removeObject(forKey: kPostponedKey)
        defaults.removeObject(forKey: kLastSavedKey)
    }
    
    private func fetchTopAppsJson(start: Int64, end: Int64) -> String {
        let apps = (try? EventStore().topApps(startMs: start, endMs: end, limit: 10)) ?? []
        struct RawStat: Codable { let appOrDomain: String; let totalSecs: Double }
        let raw = apps.map { RawStat(appOrDomain: $0.appOrDomain, totalSecs: $0.totalSecs) }
        let data = (try? JSONEncoder().encode(raw)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
