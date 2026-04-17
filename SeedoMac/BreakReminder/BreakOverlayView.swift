// SeedoMac/BreakReminder/BreakOverlayView.swift
import SwiftUI

struct BreakOverlayView: View {
    enum OverlayState {
        case summary
        case countdown
    }
    
    @State private var state: OverlayState = .summary
    @State private var summary: String = ""
    @State private var breakTimeLeft: Int = 0
    @State private var timer: Timer?
    @State private var topApps: [AppStat] = []
    @State private var config: BreakConfig = BreakConfig.load()
    
    let startTs: Int64
    let endTs: Int64
    let durationSecs: Double
    let canPostpone: Bool
    let isLongBreak: Bool
    let durationMins: Int
    let sessionIndex: Int
    let totalSessions: Int
    
    let onStartBreak: () -> Void
    let onPostpone: () -> Void
    let onSkip: (String) -> Void
    let onFinishBreak: (String) -> Void
    let onDisableToday: () -> Void
    
    var body: some View {
        ZStack {
            // Background Layer
            if let path = config.backgroundImagePath,
               let nsImg = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.4)) // Subtle dimming for text readability
            } else {
                Color(hex: config.backgroundColorHex).opacity(0.95)
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 40) {
                if state == .summary {
                    summaryContent
                } else {
                    countdownContent
                }
            }
            .frame(maxWidth: 600)
            .padding(60)
            .foregroundStyle(.white)
        }
        .onAppear {
            let loaded = BreakConfig.load()
            self.config = loaded
            // Use the duration passed via notification (Short vs Long)
            self.breakTimeLeft = durationMins * 60
            loadTopApps()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Summary Phase
    
    private var summaryContent: some View {
        VStack(spacing: 24) {
            Image(systemName: isLongBreak ? "cup.and.saucer.fill" : "timer")
                .font(.system(size: 80))
                .foregroundStyle(isLongBreak ? .orange : .green)
            
            VStack(spacing: 8) {
                Text(isLongBreak ? "长休息时间" : "短休息时间")
                    .font(.system(size: 48, weight: .bold))
                
                Text("第 \(sessionIndex)/\(totalSessions) 轮专注已完成")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Text("你已经工作了 \(Int(durationSecs / 60)) 分钟，现在该放松一下了。")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            if !topApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近 1 小时主要在使用：").font(.headline)
                    ForEach(topApps.prefix(3)) { app in
                        HStack {
                            Text(app.appOrDomain)
                            Spacer()
                            Text("\(Int(app.totalSecs / 60)) 分钟").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("刚刚在做什么？").font(.headline)
                TextEditor(text: $summary)
                    .font(.body)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3)))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
            }
            
            HStack(spacing: 20) {
                if canPostpone {
                    Button("稍后 5 分钟 (Esc)") { onPostpone() }
                        .buttonStyle(.bordered)
                        .scaleEffect(1.1)
                }
                
                Button("跳过本轮 (需填小结)") {
                    onSkip(summary)
                }
                .buttonStyle(.bordered)
                .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
                
                Button("开始休息") {
                    state = .countdown
                    startCountdown()
                    onStartBreak()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .scaleEffect(1.2)
            }
            
            Button("今日禁用休息提醒") {
                onDisableToday()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Countdown Phase
    
    private var countdownContent: some View {
        VStack(spacing: 40) {
            Text("离开座位，远眺一下吧")
                .font(.system(size: 40, weight: .bold))
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(breakTimeLeft) / CGFloat(durationMins * 60))
                    .stroke(isLongBreak ? Color.orange : Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: breakTimeLeft)
                
                Text("\(breakTimeLeft / 60):\(String(format: "%02d", breakTimeLeft % 60))")
                    .font(.system(size: 80, weight: .bold, design: .monospaced))
            }
            .frame(width: 300, height: 300)
            .onChange(of: breakTimeLeft) { val in
                if val == 0 {
                    NSSound(named: "Glass")?.play()
                }
            }
            
            Button("我已休息好 (完成并记录)") {
                NSSound(named: "Glass")?.play()
                onFinishBreak(summary)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .scaleEffect(1.2)
        }
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
}
