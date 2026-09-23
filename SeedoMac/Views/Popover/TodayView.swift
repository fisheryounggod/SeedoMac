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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TodayTasksView(appState: appState).seedoCard(padding: 14)
                    TodayGoalEditor()
                    CoachTasksView(appState: appState).seedoCard(padding: 0)
                }
                .padding(14)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 380, height: 600)
        .background(SeedoStyle.canvas)
        .tint(SeedoStyle.accent)
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
            Label("Seedo", systemImage: "leaf")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(SeedoStyle.accent)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(appState.todayTotalSecs))
                    .font(.title3)
                    .fontWeight(.bold)
                Text("今日专注时长")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // Moved breakProgressSection logic to TimerSection

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
                        .font(.system(size: 38, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(timerStatusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(appState.isTracking ? SeedoStyle.accent : .orange)

                    if !breakScheduler.boundTaskTitle.isEmpty {
                        Label(breakScheduler.boundTaskTitle, systemImage: "checklist")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help("当前绑定的今日任务")
                    }
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
                        .fill(SeedoStyle.accent)
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
