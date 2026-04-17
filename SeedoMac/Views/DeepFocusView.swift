import SwiftUI
import AVFoundation

struct DeepFocusView: View {
    @ObservedObject var appState: AppState
    
    enum FocusMode {
        case countdown
        case stopwatch
    }
    
    let onClose: () -> Void
    
    @State private var mode: FocusMode = .countdown
    @State private var timeRemaining: Int = 25 * 60
    @State private var timeElapsed: Int = 0
    @State private var timer: Timer?
    @State private var player: AVAudioPlayer?
    
    // Session Tracking
    @State private var sessionStartTs: Int64? = nil
    @State private var showingLogOverlay = false
    @State private var sessionTitle: String = ""
    @State private var selectedCategoryId: String = "focus"
    @State private var sessionSummary: String = ""
    @State private var isSaving = false
    @FocusState private var isNoteFocused: Bool
    
    // UI Logic
    @State private var showingExitConfirmation = false
    
    private let defaultCountdownSecs = 25 * 60
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Top Header
                HStack(alignment: .center, spacing: 10) {
                    if !showingLogOverlay {
                        Text("模式")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                        
                        Picker("", selection: $mode) {
                            Text("番茄钟").tag(FocusMode.countdown)
                            Text("正计时").tag(FocusMode.stopwatch)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                        .onChange(of: mode) { _ in resetTimer() }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if timer != nil {
                            showingExitConfirmation = true
                        } else {
                            onClose()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("确定要提前退出吗？", isPresented: $showingExitConfirmation, titleVisibility: .visible) {
                        Button("确认退出", role: .destructive) { onClose() }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("当前专注进度将不会被记录。")
                    }
                }
                .padding()
                
                Spacer()
                
                // Main Timer UI
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.05), lineWidth: 20)
                    
                    if mode == .countdown {
                        Circle()
                            .trim(from: 0, to: CGFloat(timeRemaining) / CGFloat(defaultCountdownSecs))
                            .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear, value: timeRemaining)
                    } else {
                        Circle()
                            .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    }
                    
                    VStack(spacing: 10) {
                        Text(mode == .countdown ? formatTime(timeRemaining) : formatTime(timeElapsed))
                            .font(.system(size: 100, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        
                        Text(mode == .countdown ? "FOCUSING" : "ELAPSED")
                            .font(.caption)
                            .tracking(4)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 400, height: 400)
                .scaleEffect(showingLogOverlay ? 0.6 : 1.0)
                .animation(.spring(), value: showingLogOverlay)
                
                Spacer()
                
                if !showingLogOverlay {
                    if mode == .stopwatch && timer != nil {
                        Button("停止并记录") {
                            handleSessionFinished()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .padding(.bottom, 60)
                    }
                }
            }
            .padding()
            .blur(radius: showingLogOverlay ? 10 : 0)
            
            // Logging Overlay
            if showingLogOverlay {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 25) {
                    VStack(spacing: 12) {
                        Text("🎉 专注于此！").font(.system(size: 32, weight: .bold))
                        Text("这段专注已经结束，请记录一下你的活动")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 10)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("备注").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            if sessionTitle.isEmpty {
                                Text("例如：阅读、写作、离线设计...")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.2))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                            }
                            
                            TextEditor(text: $sessionTitle)
                                .font(.system(size: 18))
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(12)
                                .frame(height: 100)
                                .focused($isNoteFocused)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("类别").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ForEach(SessionCategory.all) { cat in
                                Button {
                                    selectedCategoryId = cat.id
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(cat.color).frame(width: 8, height: 8)
                                        Text(cat.name).font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(selectedCategoryId == cat.id ? cat.color.opacity(0.2) : Color.white.opacity(0.06))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedCategoryId == cat.id ? cat.color.opacity(0.5) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                    
                    HStack(spacing: 20) {
                        Button("直接退出") {
                            onClose()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        
                        Button(action: saveAndExit) {
                            if isSaving {
                                ProgressView().controlSize(.small)
                                    .frame(width: 100)
                            } else {
                                Text("保存并退出")
                                    .font(.system(size: 16, weight: .bold))
                                    .padding(.horizontal, 20)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color(white: 0.2))
                        .disabled(sessionTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
                .padding(40)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color(white: 0.12)))
                .frame(width: 500)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            appState.isTracking = false // Pause global tracking
            sessionStartTs = Int64(Date().timeIntervalSince1970 * 1000)
            startTimer()
        }
        .onDisappear {
            appState.isTracking = true // Resume global tracking
            stopTimer()
            player?.stop()
        }
        .onChange(of: showingLogOverlay) { newValue in
            if newValue {
                // Focus the notes field as soon as it appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isNoteFocused = true
                }
            }
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if mode == .countdown {
                if timeRemaining > 0 {
                    timeRemaining -= 1
                } else {
                    handleSessionFinished()
                }
            } else {
                timeElapsed += 1
            }
        }
    }
    
    // ... remaining methods same as before ...
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetTimer() {
        stopTimer()
        timeElapsed = 0
        timeRemaining = defaultCountdownSecs
        sessionStartTs = Int64(Date().timeIntervalSince1970 * 1000)
        startTimer()
    }
    
    private func handleSessionFinished() {
        stopTimer()
        NSSound(named: "Glass")?.play()
        withAnimation {
            showingLogOverlay = true
        }
    }
    
    private func saveAndExit() {
        guard let start = sessionStartTs else { return }
        isSaving = true
        
        let endMs = Int64(Date().timeIntervalSince1970 * 1000)
        var session = WorkSession(
            startTs: start,
            endTs: endMs,
            topAppsJson: "[]",
            summary: sessionSummary,
            outcome: "completed",
            createdAt: endMs,
            isManual: true,
            title: sessionTitle.trimmingCharacters(in: .whitespaces),
            categoryId: selectedCategoryId
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try WorkSessionStore().insert(&session)
                // Sync to calendar if enabled
                CalendarSyncService.shared.sync(session: session)
                
                DispatchQueue.main.async {
                    onClose()
                }
            } catch {
                print("[DeepFocus] Save failed: \(error)")
                DispatchQueue.main.async { isSaving = false }
            }
        }
    }
    
    private func formatTime(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%02d:%02d", m, s)
    }
}
