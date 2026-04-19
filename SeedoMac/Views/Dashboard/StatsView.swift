// SeedoMac/Views/Dashboard/StatsView.swift
import SwiftUI
import Charts

enum StatsPeriod: String, CaseIterable, Identifiable {
    case today  = "今日"
    case week   = "周"
    case month  = "月"
    case quarter = "季"
    case halfYear = "半年"
    case year   = "年"
    case custom = "自定义"

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
    
    enum LogItem: Identifiable {
        case session(WorkSession)
        case summary(DailySummary)
        
        var id: String {
            switch self {
            case .session(let s):
                return "s-\(s.id ?? 0)-\(s.summary.hashValue)-\(s.startTs)"
            case .summary(let sum):
                return "sum-\(sum.date)"
            }
        }
        
        var timestamp: Int64 {
            switch self {
            case .session(let s): return s.startTs
            case .summary(let sum):
                // Put summary towards the end of its day (23:59:59)
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                if let date = f.date(from: sum.date) {
                    return Int64(date.timeIntervalSince1970 * 1000) + 86_399_999
                }
                return sum.createdAt
            }
        }
    }
    
    @State private var historyItems: [LogItem] = []
    @State private var isLoadingAI = false
    @State private var summary: DailySummary?
    @State private var pendingSummary: DailySummary? = nil
    @State private var showSavePrompt: Bool = false
    @State private var aiError: String? = nil
    
    struct TrendPoint: Identifiable {
        let id = UUID()
        let timeLabel: String
        let category: SessionCategory
        let durationSecs: Double
    }
    @State private var trendPoints: [TrendPoint] = []

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
    
    // Visualization State
    @State private var isHoveringTagChart: Bool = false
    @State private var hoveredAngle: Double? = nil
    @State private var hoveredTrendPoint: TrendPoint? = nil
    @State private var hoveredX: String? = nil

    // Plan section (Unified)
    @State private var dailyPlan: String = ""
    @State private var monthlyPlan: String = ""
    @State private var yearlyPlan: String = ""
    @State private var editingScope: PlanScope? = nil
    @State private var isEditingPlans: Bool = false
    @State private var planStatus: String? = nil
    
    // AI Analysis & Draft
    @State private var aiDraftContent: String = ""
    @State private var isSavingDraft: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Bar: Period Selection & AI Review Button (Fixed)
            HStack(spacing: 12) {
                periodSelector
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .bold))
                            .padding(6)
                            .background(Circle().fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Button(action: generateAISummary) {
                        HStack(spacing: 6) {
                            if isLoadingAI {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("AI 复盘")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                Color.purple.opacity(0.1)
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            }
                        )
                        .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .zIndex(10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 2. Unified Plan Board (Goal Banner)
                    unifiedPlanBoard
                        .padding(.bottom, 5)
                
                // 3. Main Data Area: 2 Columns
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Top Apps
                    topAppsSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Right Column: Charts Stack
                    VStack(alignment: .trailing, spacing: 20) {
                        trendChartSection
                        tagStatsSection
                    }
                    .frame(width: 380)
                }
                .fixedSize(horizontal: false, vertical: true)
                
                if period == .custom { customRangePicker }
                
                historySection
            }
            .padding(25)
        }
    }
    .sheet(isPresented: $isEditingPlans) {
            PlanBoardEditorSheet(
                dailyPlan: $dailyPlan,
                monthlyPlan: $monthlyPlan,
                yearlyPlan: $yearlyPlan,
                onSave: { d, m, y in
                    // 1. Update database
                    savePlan(scope: .daily, content: d, silent: false)
                    savePlan(scope: .monthly, content: m, silent: false)
                    savePlan(scope: .yearly, content: y, silent: false)
                    
                    // 2. Sync to local state so UI updates immediately
                    self.dailyPlan = d
                    self.monthlyPlan = m
                    self.yearlyPlan = y
                    
                    self.isEditingPlans = false
                },
                onCancel: { isEditingPlans = false }
            )
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
        .sheet(isPresented: $showingSettings, onDismiss: {
            appState.shouldShowSettingsSheet = false
        }) {
            VStack {
                HStack {
                    Text("设置").font(.headline)
                    Spacer()
                    Button("关闭") { 
                        showingSettings = false 
                        appState.shouldShowSettingsSheet = false
                    }
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
            loadAllPlans()
        }
        .onChange(of: period) { _ in loadPeriodData() }
        .onChange(of: customStart) { _ in if period == .custom { loadPeriodData() } }
        .onChange(of: customEnd)   { _ in if period == .custom { loadPeriodData() } }
        .onChange(of: appState.shouldShowSettingsSheet) { newValue in
            if newValue {
                showingSettings = true
                appState.shouldShowSettingsSheet = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldShowAddActivity)) { note in
            if let durationSecs = note.object as? Double {
                // Pre-fill duration if passed in notification (from Stop & Record)
                // We'll pass this through a specialized state if needed, or just trigger the sheet
                // For now, let's use a simpler approach: the sheet will check appState if prefilled
                NotificationCenter.default.post(name: NSNotification.Name("PrefillAddActivity"), object: durationSecs)
            }
            showingAddActivity = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldRunAISummary)) { _ in
            generateAISummary()
        }
    }

    // MARK: - Sections

    // MARK: - Unified Plan Board
    
    private var unifiedPlanBoard: some View {
        HStack(spacing: 20) {
            planItemCompact(title: "日度", content: dailyPlan, color: .blue)
            Divider().frame(height: 16).opacity(0.3)
            planItemCompact(title: "月度", content: monthlyPlan, color: .purple)
            Divider().frame(height: 16).opacity(0.3)
            planItemCompact(title: "年度", content: yearlyPlan, color: .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(12)
        .onTapGesture(count: 2) {
            isEditingPlans = true
        }
    }
    
    private func planItemCompact(title: String, content: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color.opacity(0.1))
                .cornerRadius(4)
            
            Text(content?.isEmpty == false ? content!.replacingOccurrences(of: "\n", with: " ") : "未设定")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(content?.isEmpty == false ? Color.primary : Color.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func binding(for scope: PlanScope) -> Binding<String> {
        switch scope {
        case .daily: return $dailyPlan
        case .monthly: return $monthlyPlan
        case .yearly: return $yearlyPlan
        }
    }

    private var trendChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("专注趋势", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text(periodLabel())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if trendPoints.isEmpty {
                VStack {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("暂无阶段性趋势数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            } else {
                let names = TrendCategoryNames()
                let colors = TrendCategoryColors()
                Chart(trendPoints) { pt in
                    if period == .today {
                        BarMark(
                            x: .value("Time", pt.timeLabel),
                            y: .value("Duration", pt.durationSecs / 60.0)
                        )
                        .foregroundStyle(by: .value("Category", pt.category.name))
                        .cornerRadius(4)
                    } else {
                        LineMark(
                            x: .value("Time", pt.timeLabel),
                            y: .value("Duration", pt.durationSecs / 60.0)
                        )
                        .foregroundStyle(by: .value("Category", pt.category.name))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("Time", pt.timeLabel),
                            y: .value("Duration", pt.durationSecs / 60.0)
                        )
                        .foregroundStyle(by: .value("Category", pt.category.name))
                        .symbolSize(hoveredX == pt.timeLabel ? 100 : 40)
                    }
                    
                    if let hoveredX = hoveredX, hoveredX == pt.timeLabel {
                        RuleMark(x: .value("Time", hoveredX))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("\(Int(val)) min")
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let xLabel: String = proxy.value(atX: location.x) {
                                        hoveredX = xLabel
                                    }
                                case .ended:
                                    hoveredX = nil
                                }
                            }
                    }
                }
                .frame(height: 180)
                .padding(.top, 10)
                .overlay(alignment: .topTrailing) {
                    if let hoverX = hoveredX {
                        let points = trendPoints.filter { $0.timeLabel == hoverX }
                        if !points.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hoverX).font(.system(size: 10, weight: .bold))
                                ForEach(points) { p in
                                    HStack(spacing: 4) {
                                        Circle().fill(p.category.color).frame(width: 6, height: 6)
                                        Text(p.category.name).font(.system(size: 9))
                                        Spacer()
                                        Text(formatDuration(p.durationSecs)).font(.system(size: 9, design: .monospaced))
                                    }
                                }
                            }
                            .padding(8)
                            .background(.regularMaterial)
                            .cornerRadius(8)
                            .shadow(radius: 2)
                            .padding(10)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(16)
    }
    
    // Removed TrendChartConfiguration helper
    
    private func TrendCategoryNames() -> [String] {
        // Show all categories that have at least one trend point
        let names = Set(trendPoints.map { $0.category.name }).sorted()
        return names
    }
    
    private func TrendCategoryColors() -> [Color] {
        let names = TrendCategoryNames()
        return names.map { name in
            trendPoints.first { $0.category.name == name }?.category.color ?? .blue
        }
    }

    private var periodSelector: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private var customRangePicker: some View {
        HStack(spacing: 12) {
            DatePicker("起始", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden()
            Text("→").foregroundStyle(.secondary)
            DatePicker("结束", selection: $customEnd, in: customStart...Date(), displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden()
            Spacer()
        }
        .font(.caption)
    }

    @ViewBuilder
    private var statsCardsRow: some View {
        HStack(alignment: .top, spacing: 20) {
            topAppsSection
                .frame(maxHeight: .infinity)
            tagStatsSection
                .frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("热门应用", systemImage: "app.badge")
                .font(.headline)
            
            if periodApps.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                let limit = BreakConfig.load().topAppsLimit
                VStack(spacing: 0) {
                    ForEach(Array(periodApps.prefix(limit).enumerated()), id: \.offset) { index, app in
                        HStack {
                            Text(app.appOrDomain)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(formatDuration(app.totalSecs))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        
                        if index < min(periodApps.count, limit) - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(16)
    }

    private var tagStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("标签分布", systemImage: "chart.pie.fill")
                .font(.headline)
            
            let stats = tagStats()
            if stats.isEmpty {
                Text("暂无专注记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(stats) { item in
                    SectorMark(
                        angle: .value("Time", item.totalSecs),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(4)
                    .opacity(hoveredTag(in: stats)?.id == item.id ? 1.0 : (hoveredAngle == nil ? 1.0 : 0.6))
                }
                .chartAngleSelection(value: $hoveredAngle)
                .frame(height: 140)
                .padding(.vertical, 8)
                
                if let selected = hoveredTag(in: stats) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(selected.color).frame(width: 8, height: 8)
                            Text(selected.name).font(.system(size: 14, weight: .bold))
                            Spacer()
                            Text(formatDuration(selected.totalSecs))
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(selected.color.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .transition(.opacity)
                } else if isHoveringTagChart {
                    // Default view: Total
                    let total = stats.reduce(0) { $0 + $1.totalSecs }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总专注时长")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatDuration(total))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(16)
        .frame(maxWidth: .infinity, alignment: .top)
        .onHover { over in
            withAnimation(.spring()) {
                isHoveringTagChart = over
                if !over { hoveredAngle = nil }
            }
        }
    }

    private func hoveredTag(in stats: [TagStat]) -> TagStat? {
        guard let angle = hoveredAngle else { return nil }
        var current: Double = 0
        for s in stats {
            current += s.totalSecs
            if angle <= current { return s }
        }
        return nil
    }

    private func tagStats() -> [TagStat] {
        var dict: [String: Double] = [:]
        let sessions: [WorkSession] = historyItems.compactMap {
            if case .session(let s) = $0 { return s }
            return nil
        }
        
        var totalRecorded: Double = 0
        for s in sessions {
            let catId = s.categoryId ?? "none"
            let duration = Double(s.durationSecs)
            dict[catId, default: 0] += duration
            totalRecorded += duration
        }
        
        var result = dict.map { (id, secs) -> TagStat in
            let cat = SessionCategory.find(id)
            return TagStat(id: id, name: cat.name, color: cat.color, totalSecs: secs)
        }.sorted { $0.totalSecs > $1.totalSecs }
        
        // Add "Unrecorded" slice for visual context
        let capacity = periodCapacityInSeconds()
        if totalRecorded < capacity {
            result.append(TagStat(
                id: "unrecorded",
                name: "未记录",
                color: Color.secondary.opacity(0.15),
                totalSecs: capacity - totalRecorded
            ))
        }
        
        return result
    }

    private func periodCapacityInSeconds() -> Double {
        switch period {
        case .today:
            return 86400 // Fixed 24h as requested
        case .week:
            return 7 * 86400
        case .month:
            return 30 * 86400
        case .quarter:
            return 90 * 86400
        case .halfYear:
            return 180 * 86400
        case .year:
            return 365 * 86400
        case .custom:
            let (startMs, endMs) = periodRange()
            let diffSecs = Double(endMs - startMs) / 1000
            let days = max(1.0, ceil(diffSecs / 86400))
            return days * 86400
        }
    }

    struct TagStat: Identifiable {
        let id: String
        let name: String
        let color: Color
        let totalSecs: Double
    }

    private var aiSummaryFocalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 深度复盘", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if isLoadingAI {
                    ProgressView().controlSize(.small)
                }
            }
            
            if let s = summary, !s.content.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView {
                        MarkdownView(text: s.content)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 150, maxHeight: 400)
                    
                    HStack {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { idx in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(idx < s.score ? .orange : .secondary.opacity(0.3))
                            }
                        }
                        Spacer()
                        Text(s.keywords)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                VStack(spacing: 8) {
                    Text("生成当前阶段的 AI 总结以获得深度洞察。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("包含自动统计、手动记录与计划达成校准。")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            }
            
            Button(action: generateAISummary) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text(summary == nil ? "立即生成" : "重新复盘")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("活动历史", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    if expandedDays.count == groupedHistoryDates().count {
                        expandedDays = []
                    } else {
                        expandedDays = Set(groupedHistoryDates())
                    }
                }) {
                    Text(expandedDays.count == groupedHistoryDates().count ? "全部折叠" : "全部展开")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: {
                    historySortOrder = (historySortOrder == .newestFirst ? .oldestFirst : .newestFirst)
                }) {
                    HStack(spacing: 4) {
                        Text(historySortOrder.rawValue)
                        Image(systemName: historySortOrder == .newestFirst ? "arrow.down" : "arrow.up")
                            .font(.system(size: 8))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                Button(action: { showingAddActivity = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            
            if historyItems.isEmpty {
                Text("所选时段内无记录")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                let sortedItems = historyItems.sorted(by: {
                    historySortOrder == .newestFirst ? ($0.timestamp > $1.timestamp) : ($0.timestamp < $1.timestamp)
                })
                
                let grouped = Dictionary(grouping: sortedItems) { item in
                    let date = Date(timeIntervalSince1970: Double(item.timestamp) / 1000)
                    return Self.dateFormatter.string(from: date)
                }
                let sortedDates = grouped.keys.sorted(by: historySortOrder == .newestFirst ? (>) : (<))
                
                ForEach(sortedDates, id: \.self) { date in
                    let dayItems = grouped[date] ?? []
                    let isExpanded = expandedDays.contains(date)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation { toggleDayExpanded(date) }
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
                                    Text("\(dayItems.count) 项")
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
                                let mergedSessions = mergeHistoryItems(dayItems)
                                ForEach(mergedSessions) { item in
                                    switch item {
                                    case .session(let s):
                                        sessionRow(s)
                                    case .summary(let sum):
                                        SummaryHistoryRow(summary: sum)
                                    }
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
            
            // 4. AI Analysis & Manual Reflection Box
            aiAnalysisRecordingSection
                .padding(.top, 24)
        }
    }

    private var aiAnalysisRecordingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.vertical, 8)
                
            HStack {
                Label("深度复盘与心得", systemImage: "sparkles")
                    .font(.headline)
                
                Spacer()
                
                if isLoadingAI {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: generateAISummaryToDraft) {
                        Label("AI 协助复盘", systemImage: "wand.and.stars")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $aiDraftContent)
                    .font(.system(size: 14))
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                
                HStack {
                    Text("提示：保存后将作为当天的总复盘显示在历史列表中。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button(action: saveAIDraft) {
                        if isSavingDraft {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("保存到复盘记录")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(8)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(aiDraftContent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func generateAISummaryToDraft() {
        isLoadingAI = true
        let (startMs, endMs) = periodRange()
        
        let context = SummaryContext(
            dateRange: periodKey(),
            topApps: periodApps,
            workSessions: historyItems.compactMap { item -> WorkSession? in
                if case .session(let s) = item { return s }
                return nil
            },
            planDaily: dailyPlan,
            planMonthly: monthlyPlan,
            planYearly: yearlyPlan
        )
        
        AIService.shared.generateSummary(context: context, periodLabel: periodLabel()) { result in
            DispatchQueue.main.async {
                self.isLoadingAI = false
                switch result {
                case .success(let sum):
                    withAnimation {
                        self.aiDraftContent = sum.content
                    }
                case .failure(let error):
                    print("AI generation failed: \(error)")
                }
            }
        }
    }
    
    private func saveAIDraft() {
        guard !aiDraftContent.isEmpty else { return }
        isSavingDraft = true
        
        let dateKey = periodKey()
        let sum = DailySummary(
            date: dateKey,
            content: aiDraftContent,
            score: 0,
            keywords: "",
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AIService.shared.persistSummary(sum)
                DispatchQueue.main.async {
                    self.isSavingDraft = false
                    self.aiDraftContent = ""
                    self.loadData()
                }
            } catch {
                print("Failed to save AI summary: \(error)")
                DispatchQueue.main.async { self.isSavingDraft = false }
            }
        }
    }
    
    private func groupedHistoryDates() -> [String] {
        let sortedItems = historyItems.sorted(by: {
            historySortOrder == .newestFirst ? ($0.timestamp > $1.timestamp) : ($0.timestamp < $1.timestamp)
        })
        let grouped = Dictionary(grouping: sortedItems) { item in
            let date = Date(timeIntervalSince1970: Double(item.timestamp) / 1000)
            return Self.dateFormatter.string(from: date)
        }
        return grouped.keys.sorted(by: historySortOrder == .newestFirst ? (>) : (<))
    }
    
    // Wrapper for session display including multiple intervals
    struct MergedSession: Identifiable {
        let id = UUID()
        var session: WorkSession
        var intervals: [String] = []
    }
    
    enum MergedLogItem: Identifiable {
        case session(MergedSession)
        case summary(DailySummary)
        
        var id: String {
            switch self {
            case .session(let s): return "ms-\(s.session.id ?? 0)-\(s.id)"
            case .summary(let sum): return "sum-\(sum.date)"
            }
        }
    }
    
    private func mergeHistoryItems(_ items: [LogItem]) -> [MergedLogItem] {
        var result: [MergedLogItem] = []
        var sessionGroups: [String: MergedSession] = [:]
        
        for item in items {
            switch item {
            case .summary(let sum):
                result.append(.summary(sum))
            case .session(let s):
                let key = "\(s.categoryId ?? "none")-\(s.summary)"
                let interval = formatTimestampRange(start: s.startTs, end: s.endTs)
                
                if var existing = sessionGroups[key] {
                    let addedMs = s.endTs - s.startTs
                    existing.session.endTs += addedMs
                    existing.session.startTs = max(existing.session.startTs, s.startTs)
                    if !existing.intervals.contains(interval) {
                        existing.intervals.append(interval)
                    }
                    sessionGroups[key] = existing
                } else {
                    sessionGroups[key] = MergedSession(session: s, intervals: [interval])
                }
            }
        }
        
        let mergedSessions = sessionGroups.values.sorted { $0.session.startTs > $1.session.startTs }.map { MergedLogItem.session($0) }
        result.append(contentsOf: mergedSessions)
        
        return result.sorted {
            let ts1 = timestamp(for: $0)
            let ts2 = timestamp(for: $1)
            return historySortOrder == .newestFirst ? (ts1 > ts2) : (ts1 < ts2)
        }
    }

    private func timestamp(for item: MergedLogItem) -> Int64 {
        switch item {
        case .session(let ms): return ms.session.startTs
        case .summary(let sum):
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let date = f.date(from: sum.date) {
                return Int64(date.timeIntervalSince1970 * 1000) + 86_399_999
            }
            return sum.createdAt
        }
    }

    private func formatTimestampRange(start: Int64, end: Int64) -> String {
        let s = Date(timeIntervalSince1970: Double(start) / 1000)
        let e = Date(timeIntervalSince1970: Double(end) / 1000)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: s)) - \(f.string(from: e))"
    }
    
    struct SummaryHistoryRow: View {
        let summary: DailySummary
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .font(.system(size: 14))
                    .frame(width: 32, height: 32)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 深度复盘报告")
                        .font(.system(size: 13, weight: .medium))
                    Text(summary.keywords)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                    Text("\(summary.score)")
                }
                .font(.system(size: 10, weight: .bold))
            }
            .padding(12)
            .background(Color.purple.opacity(0.04))
            .cornerRadius(10)
            .onTapGesture {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.showTransientAISummary(context: summary.content, label: summary.date)
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
    
    private func formatDateHeader(_ dateStr: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateStr) else { return dateStr }
        
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天 " + dateStr }
        if cal.isDateInYesterday(date) { return "昨天 " + dateStr }
        return dateStr
    }

    private func sessionRow(_ merged: MergedSession) -> some View {
        let session = merged.session
        return HStack(alignment: .top, spacing: 12) {
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
                
                if !merged.intervals.isEmpty {
                    Text(merged.intervals.joined(separator: " · "))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary.opacity(0.8))
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
                
                Button {
                    duplicateSession(session)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
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

    private func duplicateSession(_ session: WorkSession) {
        var copy = session
        copy.id = nil
        // Original startTs and endTs are preserved as requested.
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try WorkSessionStore().insert(&copy)
                

                DispatchQueue.main.async {
                    loadData()
                    // Delay slightly to ensure sheet animation doesn't glitch if loadData takes time
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.editingSession = copy
                    }
                }
            } catch {
                print("[StatsView] Duplicate failed: \(error)")
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
            // Summaries for the range
            let summaries = (try? WorkSessionStore().summaries(from: startMs, to: endMs)) ?? []

            DispatchQueue.main.async {
                self.periodApps = apps
                
                // Unified history
                var items: [LogItem] = sessions.map { .session($0) }
                items += summaries.map { .summary($0) }
                self.historyItems = items
                
                self.computeTrendPoints(sessions: sessions)
                
                // Auto-fold logic: if spanning > 1 day, start collapsed
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
        let key = periodKey()
        DispatchQueue.global(qos: .userInitiated).async {
            let s = try? WorkSessionStore().summary(for: key)
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
                            // Manual trigger: Auto-persist (upsert) to keep only one entry for today/period.
                            // This replaces the old transient window flow.
                            self.aiDraftContent = s.content
                            self.saveAIDraft()
                        case .failure(let e): 
                            self.aiError = e.localizedDescription
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

    private func loadAllPlans() {
        for scope in PlanScope.allCases {
            let key = planKey(for: scope)
            DispatchQueue.global(qos: .userInitiated).async {
                let content = AppDatabase.shared.setting(for: key) ?? ""
                DispatchQueue.main.async {
                    switch scope {
                    case .daily: self.dailyPlan = content
                    case .monthly: self.monthlyPlan = content
                    case .yearly: self.yearlyPlan = content
                    }
                }
            }
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
        case .quarter:
            let start = cal.date(byAdding: .month, value: -3, to: now)!
            return (Int64(start.timeIntervalSince1970 * 1000), endMs)
        case .halfYear:
            let start = cal.date(byAdding: .month, value: -6, to: now)!
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

    private func computeTrendPoints(sessions: [WorkSession]) {
        let cal = Calendar.current
        var dict: [String: [String: Double]] = [:] // timeLabel -> [categoryId -> totalSecs]
        
        for s in sessions {
            let start = Date(timeIntervalSince1970: Double(s.startTs) / 1000)
            let catId = s.categoryId ?? "none"
            let label: String
            
            if period == .today {
                // Hourly: "09:00", "10:00"
                let hour = cal.component(.hour, from: start)
                label = String(format: "%02d:00", hour)
            } else if period == .week || period == .month {
                // Daily: "04-15"
                let f = DateFormatter(); f.dateFormat = "MM-dd"
                label = f.string(from: start)
            } else {
                // Monthly for longer periods: "2024-04"
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                label = f.string(from: start)
            }
            
            if dict[label] == nil { dict[label] = [:] }
            dict[label]?[catId, default: 0] += s.durationSecs
        }
        
        let sortedLabels = dict.keys.sorted()
        var pts: [TrendPoint] = []
        for label in sortedLabels {
            if let catDict = dict[label] {
                for (catId, secs) in catDict {
                    let cat = SessionCategory.find(catId)
                    pts.append(TrendPoint(timeLabel: label, category: cat, durationSecs: secs))
                }
            }
        }
        self.trendPoints = pts
    }

    private func periodKey() -> String {
        let (startMs, endMs) = periodRange()
        let start = Date(timeIntervalSince1970: Double(startMs) / 1000)
        let end = Date(timeIntervalSince1970: Double(endMs) / 1000)
        
        if period == .today {
            return Self.dateFormatter.string(from: start)
        } else {
            return "\(Self.dateFormatter.string(from: start))..\(Self.dateFormatter.string(from: end))"
        }
    }

    private func periodLabel() -> String {
        switch period {
        case .today: return "Today"
        case .week: return "Past 7 days"
        case .month: return "Past month"
        case .quarter: return "Past quarter"
        case .halfYear: return "Past 6 months"
        case .year: return "Past year"
        case .custom: return "\(Self.dateFormatter.string(from: customStart)) — \(Self.dateFormatter.string(from: customEnd))"
        }
    }
}

// MARK: - Plan Board Editor Sheet
struct PlanBoardEditorSheet: View {
    @Binding var dailyPlan: String
    @Binding var monthlyPlan: String
    @Binding var yearlyPlan: String
    
    @State private var localDaily: String = ""
    @State private var localMonthly: String = ""
    @State private var localYearly: String = ""
    
    @FocusState private var focusField: Field?
    enum Field { case daily, monthly, yearly }
    
    var onSave: (String, String, String) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("日度目标") {
                    TextField("输入今日计划...", text: $localDaily, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focusField, equals: .daily)
                }
                Section("阶段计划 (月度)") {
                    TextField("输入本月计划...", text: $localMonthly, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focusField, equals: .monthly)
                }
                Section("长期愿景 (年度)") {
                    TextField("输入年度愿景...", text: $localYearly, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focusField, equals: .yearly)
                }
            }
            .navigationTitle("编辑计划 & 目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(localDaily, localMonthly, localYearly)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            localDaily = dailyPlan
            localMonthly = monthlyPlan
            localYearly = yearlyPlan
            
            // Auto focus the first field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusField = .daily
            }
        }
    }
}
