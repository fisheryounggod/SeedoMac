// SeedoMac/Views/Popover/TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var appState: AppState
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.hasAccessibilityPermission {
                accessibilityBanner
            }
            header
            Divider()
            categoryBars
            Divider()
            currentActivity
            Divider()
            footer
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }

    // MARK: - Accessibility Banner

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Grant Accessibility to track window titles")
                .font(.caption)
            Spacer()
            Button("Grant") { WindowInfoProvider.requestPermission() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("🌱 Seedo")
                .font(.headline)
            Spacer()
            Text(formatDuration(appState.todayTotalSecs))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Category Bars

    private var categoryBars: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.todayCategoryStats.isEmpty {
                Text("No activity yet today")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.todayCategoryStats.prefix(5)) { cat in
                    CategoryBarRow(stat: cat, total: appState.todayTotalSecs)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Current Activity

    private var currentActivity: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isTracking ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            if appState.isTracking && !appState.currentApp.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.currentApp)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !appState.currentTitle.isEmpty {
                        Text(appState.currentTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(formatDuration(appState.currentDurationSecs))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.isTracking ? "Waiting for activity…" : "Tracking paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(appState.isTracking ? "⏸ Pause" : "▶ Resume") {
                appState.isTracking.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button("📊 Details") { openDashboard() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

}

// MARK: - Category Bar Row

struct CategoryBarRow: View {
    let stat: CategoryStat
    let total: Double

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, stat.totalSecs / total)
    }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: stat.color).opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: stat.color))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text(stat.name)
                .font(.caption)
                .frame(width: 70, alignment: .leading)
                .lineLimit(1)

            Text(formatDuration(stat.totalSecs))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
    }

}

// MARK: - Color(hex:) extension (defined once here, used across all views)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Shared Helpers

fileprivate func formatDuration(_ secs: Double) -> String {
    let h = Int(secs) / 3600
    let m = (Int(secs) % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}
