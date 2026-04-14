// SeedoMac/Views/Dashboard/StatsView.swift
import SwiftUI
import Charts

enum StatsPeriod: String, CaseIterable {
    case today = "Today"
    case week  = "Week"
    case month = "Month"
}

struct StatsView: View {
    @ObservedObject var appState: AppState
    @State private var period: StatsPeriod = .today
    @State private var heatmapDays: [HeatmapDay] = []
    @State private var periodApps: [AppStat] = []
    @State private var periodCats: [CategoryStat] = []
    @State private var isLoadingAI = false
    @State private var summary: DailySummary?
    @State private var aiError: String? = nil
    @State private var appCategories: [String: Category?] = [:]
    @State private var allCats: [Category] = []
    @State private var assigningApp: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heatmapSection
                periodSelector
                HStack(alignment: .top, spacing: 20) {
                    if !periodCats.isEmpty { pieSection }
                    topAppsSection
                }
                aiSummarySection
            }
            .padding(20)
        }
        .onAppear { loadData() }
        .onChange(of: period) { _ in loadPeriodData() }
    }

    // MARK: - Sections

    private var heatmapSection: some View {
        GroupBox("This Year") {
            HeatmapView(days: heatmapDays)
                .frame(height: 100)
        }
    }

    private var periodSelector: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }

    @ViewBuilder
    private var pieSection: some View {
        if #available(macOS 14.0, *) {
            GroupBox("By Category") {
                Chart(periodCats) { cat in
                    SectorMark(
                        angle: .value("Time", cat.totalSecs),
                        innerRadius: .ratio(0.5)
                    )
                    .foregroundStyle(Color(hex: cat.color))
                    .annotation(position: .overlay) {
                        if cat.totalSecs / max(1, periodCats.reduce(0) { $0 + $1.totalSecs }) > 0.08 {
                            Text(cat.name)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(height: 180)
            }
            .frame(maxWidth: 250)
        } else {
            GroupBox("By Category") {
                VStack(spacing: 4) {
                    ForEach(periodCats.prefix(5)) { cat in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: cat.color))
                                .frame(width: 8, height: 8)
                            Text(cat.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(formatDuration(cat.totalSecs))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 250)
        }
    }

    private var topAppsSection: some View {
        GroupBox("Top Apps") {
            if periodApps.isEmpty {
                Text("No data for this period")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(periodApps.prefix(10)) { app in
                        HStack {
                            Text(app.appOrDomain)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            // Category badge
                            let cat = appCategories[app.appOrDomain] ?? nil
                            Button {
                                assigningApp = app.appOrDomain
                            } label: {
                                Text(cat?.name ?? "Untagged")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: cat?.color ?? "#AAAAAA").opacity(0.2))
                                    .foregroundStyle(Color(hex: cat?.color ?? "#AAAAAA"))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: Binding(
                                get: { assigningApp == app.appOrDomain },
                                set: { if !$0 { assigningApp = nil } }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Assign Category")
                                        .font(.headline)
                                        .padding([.top, .horizontal])
                                    Divider()
                                    if allCats.isEmpty {
                                        Text("No categories defined")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding()
                                    } else {
                                        ForEach(allCats) { c in
                                            Button {
                                                let name = app.appOrDomain
                                                DispatchQueue.global(qos: .userInitiated).async {
                                                    try? CategoryStore().assignApp(name, toCategoryId: c.id)
                                                    DispatchQueue.main.async {
                                                        assigningApp = nil
                                                        loadPeriodData()
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(Color(hex: c.color))
                                                        .frame(width: 8, height: 8)
                                                    Text(c.name)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.horizontal)
                                            .padding(.vertical, 2)
                                        }
                                    }
                                    Divider()
                                    Button("Cancel") { assigningApp = nil }
                                        .padding([.bottom, .horizontal])
                                }
                                .frame(width: 200)
                            }
                            Text(formatDuration(app.totalSecs))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var aiSummarySection: some View {
        GroupBox("AI Daily Summary") {
            VStack(alignment: .leading, spacing: 8) {
                if let s = summary, !s.content.isEmpty {
                    Text(s.content)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(String(repeating: "⭐", count: min(5, s.score)))
                        Spacer()
                        Text(s.keywords
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Text("No summary yet for today.")
                        .foregroundStyle(.secondary)
                }
                if let err = aiError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                Button(isLoadingAI ? "Generating…" : "Generate Today's Summary") {
                    generateAISummary()
                }
                .disabled(isLoadingAI)
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        loadHeatmap()
        loadPeriodData()
        loadSummary()
    }

    private func loadHeatmap() {
        let year = Calendar.current.component(.year, from: Date())
        DispatchQueue.global(qos: .userInitiated).async {
            let days = (try? EventStore().heatmapData(year: year)) ?? []
            DispatchQueue.main.async { self.heatmapDays = days }
        }
    }

    private func loadPeriodData() {
        let (startMs, endMs) = periodRange()
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = (try? EventStore().topApps(startMs: startMs, endMs: endMs)) ?? []
            let cats = buildCategoryStats(apps: apps)
            let catStore2 = CategoryStore()
            let allCategories = (try? catStore2.allCategories()) ?? []
            var catMap: [String: Category?] = [:]
            for app in apps {
                catMap[app.appOrDomain] = try? catStore2.matchCategory(for: app.appOrDomain, title: "")
            }
            DispatchQueue.main.async {
                self.periodApps = apps
                self.periodCats = cats
                self.allCats = allCategories
                self.appCategories = catMap
            }
        }
    }

    private func buildCategoryStats(apps: [AppStat]) -> [CategoryStat] {
        let catStore = CategoryStore()
        var totals: [String: (name: String, color: String, secs: Double)] = [:]
        for app in apps {
            if let cat = try? catStore.matchCategory(for: app.appOrDomain, title: "") {
                var e = totals[cat.id] ?? (cat.name, cat.color, 0.0)
                e.secs += app.totalSecs
                totals[cat.id] = e
            }
        }
        return totals
            .map { CategoryStat(id: $0.key, name: $0.value.name,
                                color: $0.value.color, totalSecs: $0.value.secs) }
            .sorted { $0.totalSecs > $1.totalSecs }
    }

    private func loadSummary() {
        let date = Self.dateFormatter.string(from: Date())
        DispatchQueue.global(qos: .userInitiated).async {
            let s = try? OfflineStore().summary(for: date)
            DispatchQueue.main.async { self.summary = s }
        }
    }

    private func generateAISummary() {
        isLoadingAI = true
        aiError = nil
        let apps = periodApps
        let total = apps.reduce(0.0) { $0 + $1.totalSecs }
        let cats  = periodCats   // already computed on background queue in loadPeriodData()
        let date  = Self.dateFormatter.string(from: Date())

        AIService.shared.generateDailySummary(
            date: date, apps: apps, categories: cats, totalSecs: total
        ) { result in
            DispatchQueue.main.async {
                self.isLoadingAI = false
                switch result {
                case .success(let s): self.summary = s
                case .failure(let e): self.aiError = e.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func periodRange() -> (Int64, Int64) {
        let now = Date()
        let cal = Calendar.current
        let endMs = Int64(now.timeIntervalSince1970 * 1000)
        switch period {
        case .today:
            let start = cal.startOfDay(for: now)
            return (Int64(start.timeIntervalSince1970 * 1000), endMs)
        case .week:
            let start = cal.date(byAdding: .day, value: -7, to: now)!
            return (Int64(start.timeIntervalSince1970 * 1000), endMs)
        case .month:
            let start = cal.date(byAdding: .month, value: -1, to: now)!
            return (Int64(start.timeIntervalSince1970 * 1000), endMs)
        }
    }

}
