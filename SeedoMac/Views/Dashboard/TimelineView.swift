// SeedoMac/Views/Dashboard/TimelineView.swift
import SwiftUI

struct TimelineView: View {
    @ObservedObject var appState: AppState

    private let barHeight: CGFloat = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text("Today's Timeline")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Hour label strip + timeline bar
                GeometryReader { geo in
                    let w = geo.size.width
                    VStack(spacing: 4) {
                        // Hour labels
                        HStack(spacing: 0) {
                            ForEach(0..<25, id: \.self) { h in
                                if h < 24 {
                                    Text(hourLabel(h))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .frame(width: w / 24, alignment: .leading)
                                }
                            }
                        }

                        // Canvas bar
                        ZStack {
                            // Background track
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: barHeight)

                            // Events canvas
                            Canvas { ctx, size in
                                let dayStart = dayStartMs()
                                for ev in allEvents() {
                                    let x1 = max(0, size.width * CGFloat(ev.startTs - dayStart) / CGFloat(86_400_000))
                                    let x2 = min(size.width, size.width * CGFloat(ev.endTs - dayStart) / CGFloat(86_400_000))
                                    guard x2 > x1 else { continue }
                                    let rect = CGRect(x: x1, y: 2, width: max(2, x2 - x1), height: size.height - 4)
                                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                                             with: .color(Color(hex: ev.categoryColor).opacity(0.85)))
                                }
                                // Current time cursor
                                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                                let frac = CGFloat(nowMs - dayStartMs()) / CGFloat(86_400_000)
                                let cx = max(0, min(size.width, size.width * frac))
                                ctx.fill(Path(CGRect(x: cx - 1, y: 0, width: 2, height: size.height)),
                                         with: .color(.red.opacity(0.8)))
                            }
                            .frame(height: barHeight)
                        }

                        // Hour tick marks (major: 0, 6, 12, 18, 24)
                        HStack(spacing: 0) {
                            ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                                Text(h < 12 ? (h == 0 ? "12am" : "\(h)am") : (h == 12 ? "12pm" : "\(h-12)pm"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: h == 24 ? .trailing : (h == 0 ? .leading : .center))
                            }
                        }
                    }
                }
                .frame(height: barHeight + 36)

                // Legend
                let cats = distinctCategories()
                if !cats.isEmpty {
                    GroupBox("Categories") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                            ForEach(cats, id: \.name) { entry in
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: entry.color))
                                        .frame(width: 12, height: 12)
                                    Text(entry.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                // Recent events list
                GroupBox("Events") {
                    if allEvents().isEmpty {
                        Text("No activity recorded today yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(allEvents().reversed()) { ev in
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: ev.categoryColor))
                                    .frame(width: 4, height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ev.appOrDomain).font(.caption).fontWeight(.medium)
                                    if let cat = ev.categoryName {
                                        Text(cat).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(formatDuration(Double(ev.endTs - ev.startTs) / 1000))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 2)
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func dayStartMs() -> Int64 {
        let start = Calendar.current.startOfDay(for: Date())
        return Int64(start.timeIntervalSince1970 * 1000)
    }

    private func allEvents() -> [TimelineEvent] {
        var events = appState.todayTimelineEvents
        // Append live in-progress session if not yet flushed
        if appState.currentSessionStartMs > 0, !appState.currentApp.isEmpty {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            events.append(TimelineEvent(
                id: -1,
                appOrDomain: appState.currentApp,
                startTs: appState.currentSessionStartMs,
                endTs: nowMs,
                categoryColor: "#4A90D9",
                categoryName: nil
            ))
        }
        return events
    }

    private struct CatEntry: Identifiable {
        var name: String; var color: String
        var id: String { name }
    }

    private func distinctCategories() -> [CatEntry] {
        var seen = Set<String>()
        var result: [CatEntry] = []
        for ev in appState.todayTimelineEvents {
            if let name = ev.categoryName, !seen.contains(name) {
                seen.insert(name)
                result.append(CatEntry(name: name, color: ev.categoryColor))
            }
        }
        return result
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0 { return "12a" }
        if h < 12  { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }
}
