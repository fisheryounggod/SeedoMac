import SwiftUI

struct DeepFocusView: View {
    @ObservedObject var appState: AppState
    
    let onClose: () -> Void
    let isPrimary: Bool
    
    @ObservedObject var scheduler = BreakScheduler.shared

    @State private var showingLogOverlay = false
    @State private var sessionTitle: String = ""
    @State private var selectedCategoryId: String = "focus"
    @State private var sessionSummary: String = ""
    @State private var isSaving = false
    @FocusState private var isNoteFocused: Bool
    
    // UI Logic
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 800
            let dialSize = min(400, max(120, min(geometry.size.width - 64, geometry.size.height - 280)))
        ZStack {
            SeedoStyle.night.ignoresSafeArea()
            
            if !isPrimary {
                VStack {
                    Spacer()
                    Text("保持专注")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.1))
                    Spacer()
                }
            } else {
                VStack(spacing: compact ? 16 : 30) {
                    // Top Header
                HStack(alignment: .center, spacing: 10) {
                    if !showingLogOverlay {
                        Text("模式")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30)

                        Button(action: {
                            scheduler.toggleTimerMode()
                        }) {
                            Text(scheduler.timerMode == .countdown ? "番茄钟" : "正计时")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(.white)
                                .cornerRadius(20)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.plain)
                        .help(scheduler.timerMode == .countdown ? "切换为正计时" : "切换为倒计时")
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        onClose()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .help("退出纯专注模式，计时继续")
                }
                .padding()
                
                Spacer()
                
                // Main Timer UI
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.05), lineWidth: 6)
                    
                    let progress: Double = {
                        if scheduler.timerMode == .countdown {
                            return min(1.0, scheduler.workElapsedSecsDetailed / max(1.0, scheduler.workIntervalSecs))
                        } else {
                            return 1.0
                        }
                    }()
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(SeedoStyle.mint,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: progress)
                    
                    VStack(spacing: 10) {
                        let displaySecs = scheduler.timerMode == .countdown
                            ? scheduler.remainingSecs
                            : scheduler.workElapsedSecs
                        Text(formatTime(displaySecs))
                            .font(.system(size: dialSize * 0.3, weight: .light, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .padding(.horizontal, 24)
                        
                        Text(scheduler.timerMode == .countdown ? "剩余时间" : "专注用时")
                            .font(.caption)
                            .tracking(4)
                            .foregroundStyle(.secondary)

                        if !scheduler.boundTaskTitle.isEmpty {
                            Text(scheduler.boundTaskTitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SeedoStyle.mint)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        
                        HStack(spacing: 20) {
                            Button(action: { appState.isTracking.toggle() }) {
                                Image(systemName: appState.isTracking ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help(appState.isTracking ? "暂停计时" : "继续计时")
                        }
                        .padding(.top, 10)
                    }
                }
                .frame(width: dialSize, height: dialSize)
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
                    .background(SeedoStyle.mint.opacity(0.12))
                    .foregroundStyle(SeedoStyle.mint)
                    .cornerRadius(12)
                    .padding(.bottom, compact ? 24 : 60)
                }
            }
            .padding()
            .blur(radius: showingLogOverlay ? 10 : 0)
            }
            
            // Logging Overlay (Unchanged structure, but pre-filled duration if needed)
            if showingLogOverlay {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text("每一份投入，都算数。").font(.system(size: 28, weight: .semibold, design: .rounded))
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
                        SeedoCategoryPicker(categories: SessionCategory.all, selection: $selectedCategoryId)
                    }
                    .padding(.bottom, 10)
                    
                    HStack(spacing: 20) {
                        Button("放弃记录并停止") {
                            scheduler.resetWork()
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
                        .tint(SeedoStyle.accent)
                        .disabled(sessionTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
                .seedoCard(padding: 28)
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .tint(SeedoStyle.accent)
        .onAppear {
            // A task started from 今日任务 is already the session content;
            // keep it available if a save needs to be retried.
            sessionTitle = scheduler.boundTaskTitle
            playDingDing()
        }
        .onChange(of: showingLogOverlay) { newValue in
            if newValue {
                playDingDing()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isNoteFocused = true
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
        appState.isTracking = false
        if scheduler.stopAndRecordBoundTask(completion: handleBoundTaskSaveResult) {
            isSaving = true
            return
        }
        withAnimation {
            showingLogOverlay = true
        }
    }

    private func handleBoundTaskSaveResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            onClose()
        case .failure(let error):
            print("[DeepFocus] Bound task save failed: \(error)")
            isSaving = false
            withAnimation { showingLogOverlay = true }
        }
    }
    
    private func saveAndExit() {
        isSaving = true

        scheduler.stopAndRecordCurrentSession(
            title: sessionTitle.trimmingCharacters(in: .whitespaces),
            summary: sessionSummary,
            categoryId: selectedCategoryId
        ) { result in
            switch result {
            case .success:
                onClose()
            case .failure(let error):
                print("[DeepFocus] Save failed: \(error)")
                isSaving = false
            }
        }
    }
    
    private func formatTime(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%02d:%02d", m, s)
    }
}
