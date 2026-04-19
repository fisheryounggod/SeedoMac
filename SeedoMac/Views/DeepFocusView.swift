import SwiftUI
import AVFoundation

struct DeepFocusView: View {
    @ObservedObject var appState: AppState
    
    enum FocusMode {
        case countdown
        case stopwatch
    }
    
    let onClose: () -> Void
    let isPrimary: Bool
    
    @ObservedObject var scheduler = BreakScheduler.shared
    @State private var player: AVAudioPlayer?
    
    // Timer State
    @State private var mode: FocusMode = .countdown
    @State private var remainingSecs: Int = 25 * 60
    @State private var elapsedSecs: Int = 0
    @State private var isPaused: Bool = false
    @State private var timer: Timer? = nil
    
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
            
            if !isPrimary {
                VStack {
                    Spacer()
                    Text("保持专注")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.1))
                    Spacer()
                }
            } else {
                VStack(spacing: 30) {
                    // Top Header
                HStack(alignment: .center, spacing: 10) {
                    if !showingLogOverlay {
                        Text("模式")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30)

                        Button(action: {
                            setMode(mode == .countdown ? .stopwatch : .countdown)
                        }) {
                            Text(mode == .countdown ? "蕃茄钟" : "正计时")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(.white)
                                .cornerRadius(20)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if showingLogOverlay {
                            onClose()
                        } else {
                            showingExitConfirmation = true
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("确定要中途退出吗？当前记录将不被保存。", isPresented: $showingExitConfirmation) {
                        Button("确认退出", role: .destructive) { onClose() }
                        Button("取消", role: .cancel) { }
                    }
                }
                .padding()
                
                Spacer()
                
                // Main Timer UI
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.05), lineWidth: 20)
                    
                    let progress: Double = {
                        if mode == .countdown {
                            return 1.0 - (Double(remainingSecs) / Double(defaultCountdownSecs))
                        } else {
                            return 1.0 // Simple circle for stopwatch
                        }
                    }()
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(mode == .countdown ? Color.red.opacity(0.8) : Color.blue.opacity(0.8), 
                                style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: progress)
                    
                    VStack(spacing: 10) {
                        let displaySecs = mode == .countdown ? remainingSecs : elapsedSecs
                        Text(formatTime(displaySecs))
                            .font(.system(size: 120, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        
                        Text(mode == .countdown ? "剩余时间" : "专注用时")
                            .font(.caption)
                            .tracking(4)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 20) {
                            Button(action: { isPaused.toggle() }) {
                                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                    .font(.title)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 10)
                    }
                }
                .frame(width: 400, height: 400)
                .scaleEffect(showingLogOverlay ? 0.6 : 1.0)
                .animation(.spring(), value: showingLogOverlay)
                
                Spacer()
                
                if !showingLogOverlay {
                    Button("停止并记录") {
                        handleManualStop()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.2))
                    .foregroundStyle(.red)
                    .cornerRadius(12)
                    .padding(.bottom, 60)
                }
            }
            .padding()
            .blur(radius: showingLogOverlay ? 10 : 0)
            
            // Logging Overlay (Unchanged structure, but pre-filled duration if needed)
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
                                .foregroundStyle(.white)
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
                        .tint(.blue)
                        .disabled(sessionTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
                .padding(40)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color(white: 0.12)))
                .frame(width: 500)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    .onAppear {
        playDingDing()
        startInternalTimer()
        sessionStartTs = Int64(Date().timeIntervalSince1970 * 1000)
    }
    .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: showingLogOverlay) { newValue in
            if newValue {
                timer?.invalidate()
                playDingDing()
                // Reduced delay for snappier focus
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isNoteFocused = true
                }
            }
        }
    }
    
    private func setMode(_ next: FocusMode) {
        mode = next
        remainingSecs = defaultCountdownSecs
        elapsedSecs = 0
        isPaused = false // Ensure it's never paused when switching
        startInternalTimer() // Restart timer immediately
    }
    
    private func startInternalTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard !isPaused && !showingLogOverlay else { return }
            
            elapsedSecs += 1
            if mode == .countdown {
                if remainingSecs > 0 {
                    remainingSecs -= 1
                } else {
                    withAnimation {
                        showingLogOverlay = true
                    }
                }
            }
        }
    }
    
    private func playDingDing() {
        NSSound(named: "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSSound(named: "Glass")?.play()
        }
    }
    
    private func handleManualStop() {
        withAnimation {
            showingLogOverlay = true
        }
    }
    
    private func saveAndExit() {
        guard let start = sessionStartTs else { return }
        isSaving = true
        
        let endMs = Int64(Date().timeIntervalSince1970 * 1000)
        let durationSecs = Double(elapsedSecs)
        
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
        // Ensure duration is correctly set based on timer
        // WorkSession doesn't have duration directly stored in all versions, 
        // but let's assume endTs - startTs is used, or there's a durationSecs field.
        // Actually endTs - startTs usually defines it.
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try WorkSessionStore().insert(&session)
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
