// SeedoMac/Views/Dashboard/StatsView.swift
import SwiftUI
import Charts

enum StatsPeriod: String, CaseIterable, Identifiable {
    case today  = "Today"
    case week   = "Week"
    case month  = "Month"
    case year   = "Year"
    case custom = "Custom"

    var id: String { rawValue }
}

/// Plan horizon for the 计划 section at the top of Stats. Each scope maps to
/// a distinct settings KV key (e.g. `plan_daily:2026-04-15`) so plans carry
/// over day-to-day, month-to-month, and year-to-year without colliding.
enum PlanScope: String, CaseIterable, Identifiable {
    case daily   = "日度"
    case monthly = "月度"
    case yearly  = "年度"

    var id: String { rawValue }
}

struct StatsView: View {
    @ObservedObject var appState: AppState
    @State private var period: StatsPeriod = .today
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var heatmapDays: [HeatmapDay] = []
    @State private var periodApps: [AppStat] = []
    @State private var sessions: [WorkSession] = []
    @State private var isLoadingAI = false
    @State private var summary: DailySummary?
    @State private var pendingSummary: DailySummary? = nil
    @State private var showSavePrompt: Bool = false
    @State private var aiError: String? = nil

    // Editing & Deletion
    @State private var editingSession: WorkSession? = nil
    @State private var sessionToDelete: WorkSession? = nil
    @State private var showingAddActivity = false
    @State private var showingSettings = false
    
    // Folding & Sorting
    @State private var expandedDays: Set<String> = []
    
    enum SortOrder: String, CaseIterable {
        case newestFirst = "最新优先"
        case oldestFirst = "最早优先"
    }
    @State private var historySortOrder: SortOrder = .newestFirst

    // Plan section
    @State private var planScope: PlanScope = .daily
    @State private var planContent: String = ""
    @State private var planStatus: String? = nil
    @State private var previousPlanScope: PlanScope = .daily

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                heatmapSection
                
                VStack(alignment: .leading, spacing: 15) {
                    periodSelector
                    if period == .custom { customRangePicker }
                    
                    HStack(alignment: .top, spacing: 20) {
                        topAppsSection
                        
                        VStack(alignment: .leading, spacing: 20) {
                            aiSummaryFocalSection
                            compactPlanSection
                        }
                        .frame(width: 260)
                    }
                }
                
                historySection
            }
            .padding(20)
        }
        .sheet(item: $editingSession) { session in
            WorkSessionEditorSheet(
                session: session,
                onSave: { updated in
                    saveEditedSession(updated)
                    editingSession = nil
                },
                onCancel: { editingSession = nil }
            )
        }
        .sheet(isPresented: $showingAddActivity) {
            AddActivitySheet(
                onSave: { session in
                    saveManualSession(session)
                    showingAddActivity = false
                },
                onCancel: { showingAddActivity = false }
            )
        }
        .sheet(isPresented: $showingSettings) {
            VStack {
                HStack {
                    Text("设置").font(.headline)
                    Spacer()
                    Button("关闭") { showingSettings = false }
                }
                .padding()
                SettingsView(appState: appState)
            }
            .frame(width: 450, height: 600)
        }
        .confirmationDialog(
            "确定要删除这条记录吗？",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let s = sessionToDelete { deleteSession(s) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let s = sessionToDelete {
                Text("\(formatDuration(s.durationSecs)) 的 \(s.isManual ? "手动记录" : "专注段")")
            }
        }
        .onAppear {
            loadData()
            loadPlan(scope: planScope)
        }
        .onChange(of: period) { _ in loadPeriodData() }
        .onChange(of: customStart) { _ in if period == .custom { loadPeriodData() } }
        .onChange(of: customEnd)   { _ in if period == .custom { loadPeriodData() } }
        .onChange(of: planScope) { newScope in
            savePlan(scope: previousPlanScope, content: planContent, silent: true)
            previousPlanScope = newScope
            loadPlan(scope: newScope)
        }
        .onDisappear {
            savePlan(scope: planScope, content: planContent, silent: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldShowSettings)) { _ in
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldShowAddActivity)) { _ in
            showingAddActivity = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldRunAISummary)) { _ in
            generateAISummary()
        }
    }

    // MARK: - Sections

    private var compactPlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(planScope.rawValue)计划")
                    .font(.headline)
                    .foregroundStyle(.blue)
                
                Spacer()
                
                Menu {
                    ForEach(PlanScope.allCases) { scope in
                        Button(scope.rawValue) { planScope = scope }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
            
            ZStack(alignment: .topLeading) {
                if planContent.isEmpty {
                    Text("写下计画...")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $planContent)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .frame(height: 100)
                    .padding(4)
            }
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.1), lineWidth: 1)
            )
            
            HStack {
                if let status = planStatus {
                    Text(status)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
                
                Spacer()
                
                Button("保存") {
                    savePlan(scope: planScope, content: planContent, silent: false)
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(12)
    }

    private var heatmapSection: some View {
        GroupBox("活动热力图") {
            HeatmapView(days: heatmapDays)
                .frame(height: 100)
        }
    }

    private var periodSelector: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 400)
    }

    private var customRangePicker: some View {
        HStack(spacing: 12) {
            DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden()
            Text("→").foregroundStyle(.secondary)
            DatePicker("To", selection: $customEnd, in: customStart...Date(), displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden()
            Spacer()
        }
        .font(.caption)
    }

    private var topAppsSection: some View {
        GroupBox(label: Label("热门应用", systemImage: "app.badge")) {
            if periodApps.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(periodApps.prefix(8)) { app in
                        HStack {
                            Text(app.appOrDomain)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(formatDuration(app.totalSecs))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var aiSummaryFocalSection: some View {
        GroupBox(label: Label("AI 深度复盘", systemImage: "sparkles")) {
            VStack(alignment: .leading, spacing: 10) {
                if let s = summary, !s.content.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        MarkdownView(text: s.content, lineLimit: 5)
                            .font(.caption)
                        
                        HStack {
                            HStack(spacing: 2) {
                                ForEach(0..<5) { idx in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(idx < s.score ? .orange : .secondary.opacity(0.3))
                                }
                            }
                            Spacer()
                            Button("查看完整") { /* TODO: Show full dialog */ }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } else {
                    Text("生成当前阶段的 AI 总结以获得深度洞察。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }

                Button(action: generateAISummary) {
                    if isLoadingAI {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("立即生成", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .disabled(isLoadingAI)
            }
            .padding(.vertical, 5)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("活动历史", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                
                Spacer()
                
                Picker("排序", selection: $historySortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                
                Button(action: { showingAddActivity = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            
            let grouped = groupedSessions
            let sortedDates = grouped.keys.sorted(by: {
                historySortOrder == .newestFirst ? ($0 > $1) : ($0 < $1)
            })
            
            if sessions.isEmpty {
                Text("所选时段内无记录")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedDates, id: \.self) { date in
                        let isExpanded = expandedDays.contains(date)
                        
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                withAnimation {
                                    toggleDayExpanded(date)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                        .foregroundStyle(.secondary)
                                    
                                    Text(formatDateHeader(date))
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    if !isExpanded {
                                        let count = groupedSessions[date]?.count ?? 0
                                        Text("\(count) 条记录")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            if isExpanded {
                                VStack(alignment: .leading, spacing: 10) {
                                    let daySessions = groupedSessions[date] ?? []
                                    let sortedSessions = daySessions.sorted(by: {
                                        historySortOrder == .newestFirst ? ($0.startTs > $1.startTs) : ($0.startTs < $1.startTs)
                                    })
                                    
                                    ForEach(sortedSessions) { session in
                                        sessionRow(session)
                                    }
                                }
                                .padding(.top, 10)
                                .padding(.leading, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.bottom, 5)
                    }
                }
            }
        }
    }
    
    private func toggleDayExpanded(_ date: String) {
        if expandedDays.contains(date) {
            expandedDays.remove(date)
        } else {
            expandedDays.insert(date)
        }
    }
    
    private var groupedSessions: [String: [WorkSession]] {
        Dictionary(grouping: sessions) { session in
            let date = Date(timeIntervalSince1970: Double(session.startTs) / 1000)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }
    }
    
    private func formatDateHeader(_ dateStr: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateStr) else { return dateStr }
        
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天 " + dateStr }
        if cal.isDateInYesterday(date) { return "昨天 " + dateStr }
        return dateStr
    }

    private func sessionRow(_ session: WorkSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack {
                Circle()
                    .fill(session.isManual ? Color.orange : Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    let cat = SessionCategory.find(session.categoryId)
                    let displayTitle = session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cat.name : session.summary
                    
                    Text(displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if session.categoryId != nil {
                        Text(cat.name)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(cat.color.opacity(0.2))
                            .foregroundStyle(cat.color)
                            .cornerRadius(3)
                    }
                    
                    Spacer()
                    Text(formatDuration(session.durationSecs))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                if !session.title.isEmpty {
                    Text("备注: " + session.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.6))
                        .padding(.vertical, 2)
                        .lineLimit(nil)
                }
                
                if !session.isManual {
                    let apps = session.topApps
                    if !apps.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(apps.prefix(3)) { app in
                                    Text(app.appOrDomain)
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                
                Text(formatTimestamp(session.startTs))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(10)
            .onTapGesture(count: 2) {
                editingSession = session
            }
            .contextMenu {
                Button {
                    editingSession = session
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    sessionToDelete = session
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Data Loading
    
    private func saveManualSession(_ session: WorkSession) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var s = session
                try WorkSessionStore().insert(&s)
                // Also sync to calendar if enabled
                CalendarSyncService.shared.sync(session: s)
                
                DispatchQueue.main.async {
                    loadData()
                }
            } catch {
                print("[StatsView] Save manual failed: \(error)")
            }
        }
    }

    private func deleteSession(_ session: WorkSession) {
        guard let id = session.id else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try WorkSessionStore().delete(id: id)
                DispatchQueue.main.async {
                    loadData()
                }
            } catch {
                print("[StatsView] Delete failed: \(error)")
            }
        }
    }

    private func saveEditedSession(_ session: WorkSession) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try WorkSessionStore().update(session)
                DispatchQueue.main.async {
                    loadData()
                }
            } catch {
                print("[StatsView] Update failed: \(error)")
            }
        }
    }

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
            // Raw apps
            let apps = (try? EventStore().topApps(startMs: startMs, endMs: endMs, limit: 15)) ?? []
            // Sessions
            let sessions = (try? WorkSessionStore().sessions(from: startMs, to: endMs)) ?? []

            DispatchQueue.main.async {
                self.periodApps = apps
                self.sessions = sessions
                
                // Auto-fold logic: if spanning > 1 day, start collapsed
                let cal = Calendar.current
                let isMultiDay = self.period != .today
                if isMultiDay {
                    self.expandedDays = []
                } else {
                    // Always expand today if viewing today
                    self.expandedDays = [Self.dateFormatter.string(from: Date())]
                }
            }
        }
    }

    private func loadSummary() {
        let date = Self.dateFormatter.string(from: Date())
        DispatchQueue.global(qos: .userInitiated).async {
            let s = try? WorkSessionStore().summary(for: date)
            DispatchQueue.main.async { self.summary = s }
        }
    }

    private func generateAISummary() {
        isLoadingAI = true
        aiError = nil
        let key = periodKey()
        let label = periodLabel()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let context = try SummaryContextBuilder().build(for: key)
                AIService.shared.generateSummary(context: context, periodLabel: label) { result in
                    DispatchQueue.main.async {
                        self.isLoadingAI = false
                        switch result {
                        case .success(let s):
                            self.pendingSummary = s
                            self.showSavePrompt = true
                        case .failure(let e): self.aiError = e.localizedDescription
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingAI = false
                    self.aiError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ts) / 1000)
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func planKey(for scope: PlanScope, on date: Date = Date()) -> String {
        let f = DateFormatter()
        switch scope {
        case .daily: f.dateFormat = "yyyy-MM-dd"
        case .monthly: f.dateFormat = "yyyy-MM"
        case .yearly: f.dateFormat = "yyyy"
        }
        return "plan_\(scope.id):\(f.string(from: date))"
    }

    private func planScopeLabel(_ scope: PlanScope) -> String {
        let f = DateFormatter()
        switch scope {
        case .daily: f.dateFormat = "yyyy-MM-dd"
        case .monthly: f.dateFormat = "yyyy-MM"
        case .yearly: f.dateFormat = "yyyy"
        }
        return f.string(from: Date())
    }

    private func loadPlan(scope: PlanScope) {
        let key = planKey(for: scope)
        DispatchQueue.global(qos: .userInitiated).async {
            let content = AppDatabase.shared.setting(for: key) ?? ""
            DispatchQueue.main.async { self.planContent = content }
        }
    }

    private func savePlan(scope: PlanScope, content: String, silent: Bool) {
        let key = planKey(for: scope)
        DispatchQueue.global(qos: .userInitiated).async {
            AppDatabase.shared.saveSetting(key: key, value: content)
            if !silent {
                DispatchQueue.main.async {
                    self.planStatus = "已保存 ✓"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.planStatus = nil }
                }
            }
        }
    }

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
        case .year:
            let start = cal.date(byAdding: .year, value: -1, to: now)!
            return (Int64(start.timeIntervalSince1970 * 1000), endMs)
        case .custom:
            let startOfDay = cal.startOfDay(for: customStart)
            let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd)) ?? customEnd
            return (Int64(startOfDay.timeIntervalSince1970 * 1000), Int64(min(endOfDay, now).timeIntervalSince1970 * 1000))
        }
    }

    private func periodKey() -> String {
        let (startMs, _) = periodRange()
        let startDate = Date(timeIntervalSince1970: Double(startMs) / 1000)
        return Self.dateFormatter.string(from: startDate)
    }

    private func periodLabel() -> String {
        switch period {
        case .today: return "Today"
        case .week: return "Past 7 days"
        case .month: return "Past month"
        case .year: return "Past year"
        case .custom: return "\(Self.dateFormatter.string(from: customStart)) — \(Self.dateFormatter.string(from: customEnd))"
        }
    }
}
