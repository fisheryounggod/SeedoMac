// SeedoMac/Views/Popover/TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var breakScheduler = BreakScheduler.shared
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.hasAccessibilityPermission {
                accessibilityBanner
            }
            header
            Divider()
            
            VStack(spacing: 0) {
                breakProgressSection
                sessionCounterSection
            }
            .background(Color.primary.opacity(0.03))
            
            Divider()
            currentActivity
            Divider()
            footer
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }

    // MARK: - Accessibility Banner

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

    // MARK: - Header

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

    // MARK: - Sections

    private var breakProgressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("专注进度", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let remainingMins = max(0, Int(breakScheduler.workIntervalSecs - breakScheduler.workElapsedSecsDetailed) / 60)
                Text("还需 \(remainingMins) 分钟休息")
                    .font(.system(size: 10, weight: .semibold))
            }
            
            let progress = min(1.0, breakScheduler.workElapsedSecsDetailed / max(1.0, breakScheduler.workIntervalSecs))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [.green.opacity(0.8), .green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var sessionCounterSection: some View {
        HStack(spacing: 12) {
            let current = breakScheduler.sessionsSinceLongBreak
            let total = 4 // Default freq
            
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { idx in
                    Capsule()
                        .fill(idx < current ? Color.green : Color.primary.opacity(0.1))
                        .frame(width: 20, height: 6)
                }
            }
            
            Spacer()
            
            Text("\(current)/\(total) 轮")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.1))
                .foregroundStyle(.green)
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Current Activity

    private var currentActivity: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(appState.isTracking ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: appState.isTracking ? "waveform.path.ecg" : "pause.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(appState.isTracking ? .green : .gray)
            }

            if appState.isTracking && !appState.currentApp.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.currentApp)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(appState.currentTitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(formatDuration(appState.currentDurationSecs))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.isTracking ? "正在等待活动..." : "已暂停追踪")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: { appState.isTracking.toggle() }) {
                Image(systemName: appState.isTracking ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { openDashboard() }) {
                Text("详细统计")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(100)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}



