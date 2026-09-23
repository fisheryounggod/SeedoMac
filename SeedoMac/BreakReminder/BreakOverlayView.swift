// Seedo/BreakReminder/BreakOverlayView.swift
import SwiftUI

struct BreakOverlayView: View {
    enum OverlayState: Hashable {
        case summary
        case countdown
    }
    
    @State private var state: OverlayState = .summary
    @State private var summary: String = ""
    @State private var notes: String = ""
    @State private var selectedCategoryId: String = "rest" // Default to rest if possible
    @State private var breakTimeLeft: Int = 0
    @State private var timer: Timer?
    @State private var topApps: [AppStat] = []
    @State private var config: BreakConfig = BreakConfig.load()
    @State private var categories: [SessionCategory] = SessionCategory.all
    @State private var isGenerating = false
    @State private var hasFinished = false
    
    let startTs: Int64
    let endTs: Int64
    let durationSecs: Double
    let canPostpone: Bool
    let isLongBreak: Bool
    let durationMins: Int
    let sessionIndex: Int
    let totalSessions: Int
    let sessionAlreadyRecorded: Bool
    
    // Previous content for skips
    let initialSummary: String
    let initialNotes: String
    let initialCategoryId: String?
    
    let onStartBreak: () -> Void
    let onPostpone: () -> Void
    let onSkip: (String, String, String?) -> Void
    let onFinishBreak: (String, String, String?) -> Void
    let onPauseTracking: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 800
            let inset: CGFloat = geometry.size.width < 600 ? 20 : 40
            let contentWidth = min(860, max(0, geometry.size.width - inset * 2))
            let dialSize = min(280, max(120, min(contentWidth - 40, geometry.size.height - 320)))
            ScrollView {
                Group {
                    if state == .summary {
                        summaryContent(compact: compact, wide: contentWidth >= 720)
                    } else {
                        VStack(spacing: 32) {
                            countdownContent(dialSize: dialSize, compact: compact)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { finishButton; pauseTrackingButton }
                                VStack(spacing: 12) { finishButton; pauseTrackingButton }
                            }
                        }
                    }
                }
                .frame(maxWidth: contentWidth)
                .padding(.horizontal, inset)
                .padding(.vertical, compact ? 28 : 48)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .id(state)
            .background {
                // Always paint an opaque base: underlying apps must never bleed through.
                SeedoStyle.night
                if let path = config.backgroundImagePath,
                   let nsImg = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay(SeedoStyle.night.opacity(0.82))
                } else {
                    if config.backgroundColorHex.uppercased() != "#000000" {
                        Color(hex: config.backgroundColorHex)
                            .overlay(SeedoStyle.night.opacity(0.75))
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .tint(SeedoStyle.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            let loaded = BreakConfig.load()
            self.config = loaded
            // Use the duration passed via notification (Short vs Long)
            self.breakTimeLeft = durationMins * 60
            
            // Pre-fill with previous content if available
            if !initialSummary.isEmpty { self.summary = initialSummary }
            if !initialNotes.isEmpty { self.notes = initialNotes }
            if let catId = initialCategoryId { self.selectedCategoryId = catId }
            
            loadTopApps()

            if sessionAlreadyRecorded {
                state = .countdown
                startCountdown()
                onStartBreak()
            }

            if !sessionAlreadyRecorded && AppDatabase.shared.setting(for: "break_pre_ai_enabled") == "true" {
                generateAISummary()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Summary Phase
    
    private func summaryContent(compact: Bool, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 20 : 28) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: isLongBreak ? "cup.and.saucer" : "leaf")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(SeedoStyle.mint)
                    .frame(width: 64, height: 64)
                    .background(SeedoStyle.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Text("第 \(sessionIndex) / \(totalSessions) 轮专注已完成")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedoStyle.mint)
                    Text(isLongBreak ? "慢下来，好好休息。" : "休息一下，再出发。")
                        .font(.system(size: compact ? 28 : 36, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("已专注 \(Int(durationSecs / 60)) 分钟 · 接下来休息 \(durationMins) 分钟")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if wide {
                HStack(alignment: .top, spacing: 20) {
                    activityOverview.frame(width: 220)
                    reflectionForm.frame(maxWidth: .infinity)
                }
            } else {
                activityOverview
                reflectionForm
            }
            // Goal is a quiet reference after the reflection, never a top banner.
            TodayGoalEditor()
            summaryActions
        }
    }

    private var activityOverview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("本轮活动", systemImage: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(durationSecs / 60))")
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text("分钟").font(.subheadline).foregroundStyle(.secondary)
            }
            if topApps.isEmpty {
                Text("这段专注，值得记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(topApps.prefix(3)) { app in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(app.appOrDomain).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(app.totalSecs < 60 ? "< 1 分钟" : "\(Int(app.totalSecs / 60)) 分钟")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.system(size: 12))
                        GeometryReader { proxy in
                            Capsule().fill(Color.white.opacity(0.06))
                            Capsule().fill(SeedoStyle.mint.opacity(0.65))
                                .frame(width: proxy.size.width * min(1, max(0, app.totalSecs / max(1, durationSecs))))
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .seedoCard()
    }

    private var reflectionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("刚刚在做什么？").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("本轮小结").font(.caption).foregroundStyle(.secondary)
            }
            SeedoCategoryPicker(categories: categories, selection: $selectedCategoryId)
            TextField("用一句话，记下这次进展…", text: $summary, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .seedoInput()
                .accessibilityLabel("本轮小结")
            HStack {
                Text("备注").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button(action: generateAISummary) {
                    Label(isGenerating ? "生成中…" : "AI 帮我整理", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SeedoStyle.mint)
                .disabled(isGenerating)
            }
            TextEditor(text: $notes)
                .font(.system(size: 14))
                .frame(height: 96)
                .scrollContentBackground(.hidden)
                .seedoInput()
                .accessibilityLabel("备注")
        }
        .seedoCard()
    }

    private var summaryActions: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { summaryButtons }
                VStack(spacing: 10) { summaryButtons }
            }
            pauseTrackingButton
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var pauseTrackingButton: some View {
        Button("暂停专注追踪  ⌘P", action: onPauseTracking)
            .keyboardShortcut("p", modifiers: .command)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(8)
    }

    @ViewBuilder private var summaryButtons: some View {
        if canPostpone {
            Button("稍后 5 分钟  Esc", action: onPostpone)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SeedoButtonStyle())
        }
        Button("跳过本轮") { onSkip(summary, notes, selectedCategoryId) }
            .buttonStyle(SeedoButtonStyle())
            .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("填写小结后可跳过本轮休息")
        Button {
            state = .countdown
            startCountdown()
            onStartBreak()
        } label: {
            Label("开始休息", systemImage: "arrow.right")
        }
        .buttonStyle(SeedoButtonStyle(prominent: true))
        .keyboardShortcut(.return, modifiers: .command)
    }

    // MARK: - Countdown Phase
    
    private func countdownContent(dialSize: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 20 : 40) {
            Text("离开座位，远眺一下吧")
                .font(.system(size: compact ? 28 : 40, weight: .bold))
                .multilineTextAlignment(.center)
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(breakTimeLeft) / CGFloat(max(1, durationMins * 60)))
                    .stroke(SeedoStyle.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: breakTimeLeft)
                
                Text("\(breakTimeLeft / 60):\(String(format: "%02d", breakTimeLeft % 60))")
                    .font(.system(size: dialSize * 0.26, weight: .light, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 16)
            }
            .frame(width: dialSize, height: dialSize)
            .onChange(of: breakTimeLeft) { val in
                if val == 0 {
                    NSSound(named: "Glass")?.play()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSSound(named: "Glass")?.play()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard !hasFinished else { return }
                        hasFinished = true
                        onFinishBreak(summary, notes, selectedCategoryId)
                    }
                }
            }

        }
    }

    private var finishButton: some View {
            Button("我已休息好 (完成并记录)") {
                guard !hasFinished else { return }
                hasFinished = true
                NSSound(named: "Glass")?.play()
                onFinishBreak(summary, notes, selectedCategoryId)
            }
            .buttonStyle(SeedoButtonStyle(prominent: true))
    }
    
    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if breakTimeLeft > 0 {
                breakTimeLeft -= 1
            } else {
                timer?.invalidate()
            }
        }
    }
    
    private func loadTopApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = (try? EventStore().topApps(startMs: startTs, endMs: endTs, limit: 5)) ?? []
            DispatchQueue.main.async {
                self.topApps = apps
            }
        }
    }

    private func generateAISummary() {
        isGenerating = true
        AIService.shared.generateSessionSummary(startTs: startTs, endTs: endTs) { result in
            DispatchQueue.main.async {
                isGenerating = false
                switch result {
                case .success(let text):
                    if !text.isEmpty {
                        self.notes = text
                    }
                case .failure(let error):
                    print("AI Generate error: \(error)")
                }
            }
        }
    }
}
