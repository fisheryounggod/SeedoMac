import SwiftUI
import AVFoundation

struct DeepFocusView: View {
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
    
    // UI Logic
    @State private var showingExitConfirmation = false
    
    private let defaultCountdownSecs = 25 * 60
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Top Header
                HStack {
                    if !showingLogOverlay {
                        Picker("模式", selection: $mode) {
                            Text("番茄钟").tag(FocusMode.countdown)
                            Text("正计时").tag(FocusMode.stopwatch)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
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
            
            // Note: Side Note Editor removed per user request
            
            // Logging Overlay
            if showingLogOverlay {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 20) {
                    Text("🎉 专注于此！").font(.title.bold())
                    Text("这段专注已经结束，请记录一下你的活动").font(.subheadline).foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading) {
                        Text("备注").font(.caption2).foregroundStyle(.secondary)
                        TextField("例如：阅读、写作、离线设计...", text: $sessionTitle)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("类别").font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            ForEach(SessionCategory.all) { cat in
                                Button {
                                    selectedCategoryId = cat.id
                                } label: {
                                    HStack {
                                        Circle().fill(cat.color).frame(width: 8, height: 8)
                                        Text(cat.name).font(.caption)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedCategoryId == cat.id ? cat.color.opacity(0.3) : Color.white.opacity(0.05))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    HStack(spacing: 15) {
                        Button("直接退出") {
                            onClose()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        
                        Button(action: saveAndExit) {
                            if isSaving {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("保存并退出").bold()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sessionTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.12)))
                .frame(width: 450)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            sessionStartTs = Int64(Date().timeIntervalSince1970 * 1000)
            startTimer()
        }
        .onDisappear {
            stopTimer()
            player?.stop()
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
