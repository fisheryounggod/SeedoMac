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
                        .stroke(Color.white.opacity(0.05), lineWidth: 20)
                    
                    let progress: Double = {
                        if scheduler.timerMode == .countdown {
                            return min(1.0, scheduler.workElapsedSecsDetailed / max(1.0, scheduler.workIntervalSecs))
                        } else {
                            return 1.0
                        }
                    }()
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(scheduler.timerMode == .countdown ? Color.red.opacity(0.8) : Color.blue.opacity(0.8),
                                style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: progress)
                    
                    VStack(spacing: 10) {
                        let displaySecs = scheduler.timerMode == .countdown
                            ? scheduler.remainingSecs
                            : scheduler.workElapsedSecs
                        Text(formatTime(displaySecs))
                            .font(.system(size: 120, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        
                        Text(scheduler.timerMode == .countdown ? "剩余时间" : "专注用时")
                            .font(.caption)
                            .tracking(4)
                            .foregroundStyle(.secondary)
                        
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
            }
            
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
        .onAppear {
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
        withAnimation {
            showingLogOverlay = true
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
