// Seedo/Views/Popover/TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var appState: AppState
    let openDashboard: (DashboardTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.hasAccessibilityPermission {
                accessibilityBanner
            }
            header
            Divider()
            
            TimerSection(appState: appState)
            
            Divider()
            todayGoalSection
            
            Divider()
            
            aiCoachSection
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    // ... (accessibilityBanner and header remains same)

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("请授予辅助功能权限以追踪窗口")
                .font(.caption2)
            Spacer()
            Button("授权") { WindowInfoProvider.requestPermission() }
                .buttonStyle(.borderless)
                .font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.1))
    }

    private var header: some View {
        HStack {
            Text("🌱 Seedo").font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(appState.todayTotalSecs))
                    .font(.title3)
                    .fontWeight(.bold)
                Text("今日专注时长")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // Moved breakProgressSection logic to TimerSection

    @State private var isHoveringGoal = false
    @State private var isEditingGoal = false
    @State private var draftGoal = ""
    @FocusState private var goalFieldFocused: Bool

    private var todayGoalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("今日目标", systemImage: "target")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isEditingGoal {
                    Button("完成") {
                        commitGoal()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                } else {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isHoveringGoal ? .secondary : .tertiary)
                }
            }
            
            if isEditingGoal {
                TextField("输入今日目标...", text: $draftGoal, axis: .vertical)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .lineLimit(3...5)
                    .focused($goalFieldFocused)
                    .onSubmit { commitGoal() }
                    .onExitCommand { cancelGoal() }
                    .padding(8)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )
            } else {
                Text(appState.todayGoal.isEmpty ? "点击编辑今日目标..." : appState.todayGoal)
                    .font(.system(size: 12))
                    .foregroundStyle(appState.todayGoal.isEmpty ? .tertiary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(isHoveringGoal && !isEditingGoal ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringGoal = hovering
        }
        .onTapGesture {
            if !isEditingGoal {
                startEditing()
            }
        }
    }

    @State private var isRefreshingCoach = false
    @State private var coachError: String? = nil

    private var aiCoachSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("执行力教练", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isRefreshingCoach {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        refreshCoachTasks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if let error = coachError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else if appState.aiCoachTasks.isEmpty {
                Text("点击刷新由 AI 生成今日优先建议")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(appState.aiCoachTasks, id: \.self) { task in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .padding(.top, 5)
                                .foregroundStyle(.blue.opacity(0.7))
                            Text(task)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private func refreshCoachTasks() {
        isRefreshingCoach = true
        coachError = nil
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let todayStr = df.string(from: Date())
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let context = try SummaryContextBuilder().build(for: todayStr)

                AIService.shared.generateCoachTasks(context: context) { result in
                    DispatchQueue.main.async {
                        isRefreshingCoach = false
                        switch result {
                        case .success(let tasks):
                            self.appState.aiCoachTasks = tasks
                            if let data = try? JSONEncoder().encode(tasks),
                               let json = String(data: data, encoding: .utf8) {
                                AppDatabase.shared.saveSetting(key: "ai_coach_tasks:\(todayStr)", value: json)
                            }
                        case .failure(let error):
                            self.coachError = error.localizedDescription
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isRefreshingCoach = false
                    self.coachError = "构建上下文失败"
                }
            }
        }
    }
    
    private func startEditing() {
        draftGoal = appState.todayGoal
        isEditingGoal = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            goalFieldFocused = true
        }
    }
    
    private func commitGoal() {
        let trimmed = draftGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.todayGoal = trimmed
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let todayKey = "plan_daily:\(df.string(from: Date()))"
        AppDatabase.shared.saveSetting(key: todayKey, value: trimmed)
        
        isEditingGoal = false
        goalFieldFocused = false
    }
    
    private func cancelGoal() {
        isEditingGoal = false
        goalFieldFocused = false
        draftGoal = ""
    }
}

// MARK: - TimerSection (Isolated to prevent parent re-renders)
struct TimerSection: View {
    @ObservedObject var appState: AppState
    @ObservedObject var breakScheduler = BreakScheduler.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                let displaySecs = breakScheduler.timerMode == .countdown
                    ? breakScheduler.remainingSecs
                    : breakScheduler.workElapsedSecs
                let mins = displaySecs / 60
                let secs = displaySecs % 60

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%02d:%02d", mins, secs))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(timerStatusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(appState.isTracking ? .green : .orange)
                }

                Spacer()

                Button {
                    breakScheduler.toggleTimerMode()
                } label: {
                    Image(systemName: breakScheduler.timerMode == .countdown ? "timer" : "stopwatch")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(breakScheduler.timerMode == .countdown ? "切换为正计时" : "切换为倒计时")

                Button {
                    appState.isTracking.toggle()
                } label: {
                    Image(systemName: appState.isTracking ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(appState.isTracking ? "暂停计时" : "继续计时")
            }

            let progress = min(1.0, breakScheduler.workElapsedSecsDetailed / max(1.0, breakScheduler.workIntervalSecs))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.green.opacity(0.8), .green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var timerStatusText: String {
        guard appState.isTracking else { return "已暂停" }
        return breakScheduler.timerMode == .countdown ? "倒计时专注中..." : "正计时专注中..."
    }
}
