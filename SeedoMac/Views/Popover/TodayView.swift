// SeedoMac/Views/Popover/TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var breakScheduler = BreakScheduler.shared
    let openDashboard: (DashboardTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.hasAccessibilityPermission {
                accessibilityBanner
            }
            header
            Divider()
            
            VStack(spacing: 0) {
                breakProgressSection
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
            // Pause/Play Button (Matching Rounded Square style in screenshot)
            HStack(spacing: 8) {
                Button(action: { appState.isTracking.toggle() }) {
                    Image(systemName: appState.isTracking ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                if appState.isTracking {
                    Button(action: {
                        let duration = appState.currentDurationSecs
                        appState.isTracking = false
                        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                            appDelegate.resetTracking()
                        }
                        openDashboard(.stats)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(name: .shouldShowAddActivity, object: duration)
                        }
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("记录并重置计时")
                }
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 12) {
                // Stats Button
                Button(action: { openDashboard(.stats) }) {
                    Text("统计")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Settings Button
                Button(action: { openDashboard(.settings) }) {
                    Text("设置")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}



