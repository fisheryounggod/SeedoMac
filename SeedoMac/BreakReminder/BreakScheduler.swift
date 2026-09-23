// Seedo/BreakReminder/BreakScheduler.swift
import Foundation
import Combine

final class BreakScheduler: ObservableObject {
    static let shared = BreakScheduler()

    enum TimerMode: String {
        case countdown
        case stopwatch
    }

    enum FocusSurface {
        case normal
        case deepFocus
    }
    
    @Published var workElapsedSecsDetailed: Double = 0
    var workElapsedSecs: Int { Int(workElapsedSecsDetailed) }

    @Published var timerMode: TimerMode = .countdown {
        didSet {
            UserDefaults.standard.set(timerMode.rawValue, forKey: kTimerModeKey)
        }
    }
    @Published private(set) var focusSurface: FocusSurface = .normal
    
    var workIntervalSecs: Double {
        Double(config.workIntervalMins * 60)
    }
    
    private var config = BreakConfig.load()
    private var timer: Timer?
    private var isAFK = false
    private var afkStartTs: Date?
    @Published var isBreakInProgress = false
    private var postponedOnce = false
    @Published var isFocusActive: Bool = true // Enabled by default as "Normal Mode"

    /// Task selected from 今日任务 for the current focus session.
    /// This is separate from AppState.currentTitle, which the activity
    /// tracker continuously replaces with the foreground window title.
    @Published private(set) var boundTaskTitle: String = ""
    
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

    var remainingSecs: Int {
        max(0, Int(ceil(workIntervalSecs - workElapsedSecsDetailed)))
    }

    var totalElapsedSecs: Double {
        workElapsedSecsDetailed + accumulatedWorkSecs
    }

    var currentSessionStartTs: Int64 {
        sessionStartTs ?? Int64((Date().timeIntervalSince1970 - totalElapsedSecs) * 1000)
    }

    func enterDeepFocusSurface() {
        focusSurface = .deepFocus
    }

    func exitDeepFocusSurface() {
        focusSurface = .normal
    }

    func toggleTimerMode() {
        timerMode = timerMode == .countdown ? .stopwatch : .countdown
    }

    func startTask(_ title: String, mode: TimerMode) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        // The two controls in 今日任务 are two views of the same running
        // session. Switching between countdown and stopwatch must keep the
        // task, elapsed time, start timestamp, and accumulated skipped rounds.
        if boundTaskTitle == normalized {
            timerMode = mode
            isFocusActive = true
            savePersistence()
            return
        }

        // Selecting a different task intentionally starts a fresh session.
        resetWork()
        timerMode = mode
        boundTaskTitle = normalized
        isFocusActive = true
        savePersistence()
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
        guard isFocusActive && AppState.shared.isTracking else {
            return
        }
        
        if isBreakInProgress {
            // Log once every minute if stuck in break mode
            if Int(Date().timeIntervalSince1970) % 60 == 0 {
                print("[BreakScheduler] Tick skipped: isBreakInProgress is true")
            }
            return
        }
        
        if !isAFK {
            if workElapsedSecsDetailed == 0 && accumulatedWorkSecs == 0 {
                sessionStartTs = Int64(Date().timeIntervalSince1970 * 1000)
            }
            workElapsedSecsDetailed += 1
            
            // Persist every 5 seconds to avoid over-saving while keeping it responsive
            if Int(workElapsedSecsDetailed) % 5 == 0 {
                savePersistence()
            }
            
            let threshold = Double(config.workIntervalMins * 60)
            if timerMode == .countdown && workElapsedSecsDetailed >= threshold {
                triggerBreak()
            }
        } else {
            // Log once every minute if stuck in AFK mode
            if Int(Date().timeIntervalSince1970) % 60 == 0 {
                print("[BreakScheduler] Tick skipped: isAFK is true")
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
        let taskTitle = boundTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionAlreadyRecorded: Bool

        if taskTitle.isEmpty {
            sessionAlreadyRecorded = false
        } else {
            var session = WorkSession(
                startTs: startTs,
                endTs: endTs,
                topAppsJson: fetchTopAppsJson(start: startTs, end: endTs),
                summary: taskTitle,
                outcome: "completed",
                createdAt: endTs,
                isManual: true,
                title: taskTitle,
                categoryId: "focus"
            )
            do {
                try WorkSessionStore().insert(&session)
                completeSessionCount(wasLongBreak: willBeLong)
                resetWork()
                isBreakInProgress = true
                sessionAlreadyRecorded = true
                NotificationCenter.default.post(name: .workSessionDidSave, object: nil)
            } catch {
                // Keep the session intact and fall back to the editable review
                // instead of losing a record when persistence fails.
                print("[BreakScheduler] Bound task auto-save failed: \(error)")
                sessionAlreadyRecorded = false
            }
        }
        
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
                "sessionAlreadyRecorded": sessionAlreadyRecorded,
                "previousSummary": lastSkippedSummary,
                "previousNotes": sessionAlreadyRecorded ? "" : (taskTitle.isEmpty ? lastSkippedNotes : taskTitle),
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

        // Update session tracking
        if outcome == "completed" { completeSessionCount(wasLongBreak: isLongBreak) }
        
        // Reset
        resetWork()
        postponedOnce = false
        isBreakInProgress = false
    }

    func finishAlreadyRecordedBreak() {
        resetWork()
        isBreakInProgress = false
    }

    private func completeSessionCount(wasLongBreak: Bool) {
        sessionsSinceLongBreak = wasLongBreak ? 0 : sessionsSinceLongBreak + 1
        UserDefaults.standard.set(sessionsSinceLongBreak, forKey: "break_session_count")
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
    
    func pauseTracking() {
        DispatchQueue.main.async {
            AppState.shared.isTracking = false
        }
        resetWork()
        isBreakInProgress = false
    }

    func stopAndRecordCurrentSession(
        title: String,
        summary: String,
        categoryId: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let startTs = currentSessionStartTs
        let endTs = Int64(Date().timeIntervalSince1970 * 1000)

        DispatchQueue.global(qos: .userInitiated).async {
            var session = WorkSession(
                startTs: startTs,
                endTs: endTs,
                topAppsJson: self.fetchTopAppsJson(start: startTs, end: endTs),
                summary: summary,
                outcome: "completed",
                createdAt: endTs,
                isManual: true,
                title: title,
                categoryId: categoryId
            )

            do {
                try WorkSessionStore().insert(&session)
                DispatchQueue.main.async {
                    self.resetWork()
                    NotificationCenter.default.post(name: .workSessionDidSave, object: nil)
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Records a task-bound session without opening an input form.
    /// Returns false when the current session has no bound task so callers can
    /// retain the existing manual-record flow.
    @discardableResult
    func stopAndRecordBoundTask(completion: @escaping (Result<Void, Error>) -> Void) -> Bool {
        let title = boundTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        // Keep the task in both fields: summary is the primary activity text
        // in statistics, while title remains available as the session note.
        stopAndRecordCurrentSession(title: title, summary: title, categoryId: "focus", completion: completion)
        return true
    }
    
    func resetWork() {
        workElapsedSecsDetailed = 0
        accumulatedWorkSecs = 0
        lastSkippedSummary = ""
        lastSkippedNotes = ""
        lastSkippedCategoryId = nil
        sessionStartTs = nil
        boundTaskTitle = ""
        postponedOnce = false
        isBreakInProgress = false
        clearPersistence()
    }
    
    // MARK: - Persistence
    
    private let kElapsedKey = "focus_timer_elapsed"
    private let kAccumulatedKey = "focus_timer_accumulated"
    private let kSessionStartKey = "focus_timer_session_start"
    private let kPostponedKey = "focus_timer_postponed"
    private let kLastSavedKey = "focus_timer_last_saved"
    private let kTimerModeKey = "focus_timer_mode"
    private let kBoundTaskTitleKey = "focus_timer_bound_task_title"

    private func savePersistence() {
        let defaults = UserDefaults.standard
        defaults.set(workElapsedSecsDetailed, forKey: kElapsedKey)
        defaults.set(accumulatedWorkSecs, forKey: kAccumulatedKey)
        if let sessionStartTs {
            defaults.set(sessionStartTs, forKey: kSessionStartKey)
        } else {
            defaults.removeObject(forKey: kSessionStartKey)
        }
        defaults.set(postponedOnce, forKey: kPostponedKey)
        if boundTaskTitle.isEmpty {
            defaults.removeObject(forKey: kBoundTaskTitleKey)
        } else {
            defaults.set(boundTaskTitle, forKey: kBoundTaskTitleKey)
        }
        defaults.set(Int64(Date().timeIntervalSince1970), forKey: kLastSavedKey)
    }
    
    private func loadPersistence() {
        let defaults = UserDefaults.standard
        if let rawMode = defaults.string(forKey: kTimerModeKey),
           let savedMode = TimerMode(rawValue: rawMode) {
            timerMode = savedMode
        }
        let lastSaved = defaults.integer(forKey: kLastSavedKey)
        let now = Int64(Date().timeIntervalSince1970)
        
        // Only resume if the session was active within the last 4 hours
        // This prevents resuming a session from yesterday.
        if lastSaved > 0 && (now - Int64(lastSaved)) < (4 * 3600) {
            self.workElapsedSecsDetailed = defaults.double(forKey: kElapsedKey)
            self.accumulatedWorkSecs = defaults.double(forKey: kAccumulatedKey)
            let savedStartTs = defaults.object(forKey: kSessionStartKey) as? NSNumber
            self.sessionStartTs = savedStartTs?.int64Value
                ?? Int64((Date().timeIntervalSince1970 - totalElapsedSecs) * 1000)
            self.boundTaskTitle = defaults.string(forKey: kBoundTaskTitleKey) ?? ""
            self.postponedOnce = defaults.bool(forKey: kPostponedKey)
            print("[BreakScheduler] Recovered session: \(workElapsedSecsDetailed)s elapsed")
        }
    }
    
    private func clearPersistence() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: kElapsedKey)
        defaults.removeObject(forKey: kAccumulatedKey)
        defaults.removeObject(forKey: kSessionStartKey)
        defaults.removeObject(forKey: kPostponedKey)
        defaults.removeObject(forKey: kBoundTaskTitleKey)
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
