// SeedoMac/Views/Dashboard/OfflineView.swift
import SwiftUI

// MARK: - Tab + Journal types

private enum LogTab: String, Hashable {
    case activities = "Activities"
    case journal    = "Journal"
}

private enum JournalEntry: Identifiable {
    case summary(DailySummary)
    case activities(date: String, items: [OfflineActivity])

    var id: String {
        switch self {
        case .summary(let s):       return "s-\(s.date)"
        case .activities(let d, _): return "a-\(d)"
        }
    }
    var date: String {
        switch self {
        case .summary(let s):       return s.date
        case .activities(let d, _): return d
        }
    }
}

// MARK: - OfflineView

struct OfflineView: View {
    private let store = OfflineStore()

    // Activities tab state
    @State private var selectedDate = Date()
    @State private var activities: [OfflineActivity] = []
    @State private var showAdd = false
    @State private var newLabel = ""
    @State private var newDurationMins: Int = 30
    @State private var newStartTime = Date()

    // Journal tab state
    @State private var journalEntries: [JournalEntry] = []
    @State private var editingSummary: DailySummary? = nil

    // Shared
    @State private var activeTab: LogTab = .activities
    @State private var summaryObserverToken: NSObjectProtocol? = nil

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("", selection: $activeTab) {
                    ForEach([LogTab.activities, .journal], id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                if activeTab == .activities {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: selectedDate) { _ in loadActivities() }

                    Spacer()

                    Group {
                        if showAdd {
                            Button("Cancel") { showAdd = false }
                                .buttonStyle(.bordered)
                        } else {
                            Button("+ Add") {
                                showAdd = true
                                newLabel = ""
                                newDurationMins = 30
                                newStartTime = Date()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .controlSize(.small)
                } else {
                    Spacer()
                }
            }
            .padding(16)

            Divider()

            if activeTab == .activities {
                activitiesContent
            } else {
                journalContent
            }
        }
        .onAppear {
            loadActivities()
            loadJournal()
            if summaryObserverToken == nil {
                summaryObserverToken = NotificationCenter.default.addObserver(
                    forName: .dailySummaryDidSave, object: nil, queue: .main
                ) { _ in loadJournal() }
            }
        }
        .onDisappear {
            if let token = summaryObserverToken {
                NotificationCenter.default.removeObserver(token)
                summaryObserverToken = nil
            }
        }
        .onChange(of: activeTab) { tab in
            if tab == .journal { loadJournal() }
        }
        .sheet(item: $editingSummary) { summary in
            SummaryEditorSheet(summary: summary) { updated in
                saveEditedSummary(updated)
                editingSummary = nil
            } onCancel: {
                editingSummary = nil
            }
        }
    }

    // MARK: - Activities Tab

    private var activitiesContent: some View {
        VStack(spacing: 0) {
            if showAdd {
                addForm
                Divider()
            }
            activityList
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Label (e.g. Reading, Meeting)", text: $newLabel)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                DatePicker("Start", selection: $newStartTime,
                           displayedComponents: [.hourAndMinute])
                    .labelsHidden()

                Stepper("Duration: \(newDurationMins) min",
                        value: $newDurationMins, in: 1...480)
            }

            HStack {
                Spacer()
                Button("Save Activity") { saveActivity() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05))
    }

    private var activityList: some View {
        Group {
            if activities.isEmpty {
                Text("No offline activities for this day.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(activities) { act in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(act.label).fontWeight(.medium)
                                Text(startTimeString(act))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatDuration(Double(act.durationSecs)))
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteActivity(act)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Journal Tab

    private var journalContent: some View {
        List {
            if journalEntries.isEmpty {
                Text("No journal entries yet. Generate an AI summary in the Stats tab.")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .padding()
            } else {
                ForEach(journalEntries) { entry in
                    journalEntryView(entry)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func journalEntryView(_ entry: JournalEntry) -> some View {
        switch entry {
        case .summary(let s):
            summaryRow(s)
        case .activities(let date, let items):
            Section(header: Text(date).font(.caption).foregroundStyle(.secondary)) {
                ForEach(items) { act in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(act.label).font(.subheadline)
                            Text(startTimeString(act))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatDuration(Double(act.durationSecs)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func summaryRow(_ s: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.formatSummaryDateKey(s.date))
                    .font(.headline)
                Spacer()
                if s.score > 0 {
                    Text(String(repeating: "★", count: s.score) +
                         String(repeating: "☆", count: max(0, 5 - s.score)))
                        .foregroundStyle(.orange)
                }
                Menu {
                    Button("编辑") { editingSummary = s }
                    Button("删除", role: .destructive) { deleteSummary(s) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if !s.content.isEmpty {
                Self.renderMarkdown(s.content)
                    .font(.callout)
                    .lineLimit(4)
                    .foregroundStyle(.primary)
            }
            if !s.keywords.isEmpty {
                Text(s.keywords)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Renders markdown content for the summary row. Falls back to plain text
    /// on parse failure so malformed AI output never blocks display.
    private static func renderMarkdown(_ raw: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attr = try? AttributedString(markdown: raw, options: options) {
            return Text(attr)
        }
        return Text(raw)
    }

    /// Formats a DailySummary.date primary key for display.
    /// - "YYYY-MM-DD" → returned as-is (today-style single date)
    /// - "YYYY-MM-DD..YYYY-MM-DD" → "MMM d – MMM d, YYYY" (period-style range)
    private static func formatSummaryDateKey(_ key: String) -> String {
        let parts = key.components(separatedBy: "..")
        guard parts.count == 2,
              let startDate = dayFormatter.date(from: parts[0]),
              let endDate   = dayFormatter.date(from: parts[1]) else {
            return key
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let startCal = Calendar.current.dateComponents([.year], from: startDate)
        let endCal   = Calendar.current.dateComponents([.year], from: endDate)
        if startCal.year == endCal.year {
            f.dateFormat = "MMM d"
            let s = f.string(from: startDate)
            f.dateFormat = "MMM d, yyyy"
            let e = f.string(from: endDate)
            return "\(s) – \(e)"
        } else {
            f.dateFormat = "MMM d, yyyy"
            return "\(f.string(from: startDate)) – \(f.string(from: endDate))"
        }
    }

    // MARK: - Actions

    private func loadActivities() {
        let dateStr = Self.dayFormatter.string(from: selectedDate)
        DispatchQueue.global(qos: .userInitiated).async {
            let items = (try? store.activities(for: dateStr)) ?? []
            DispatchQueue.main.async { activities = items }
        }
    }

    private func loadJournal() {
        DispatchQueue.global(qos: .userInitiated).async {
            let summaries = (try? store.allSummaries()) ?? []
            let actDates  = (try? store.allActivityDates()) ?? []

            // Build sorted date set — for range-key summaries, sort by end date
            var dateSet = Set<String>(summaries.map(\.date))
            actDates.forEach { dateSet.insert($0) }
            let sortedDates = dateSet.sorted { Self.endDateKey($0) > Self.endDateKey($1) }

            // Build JournalEntry list per date
            var entries: [JournalEntry] = []
            let summaryByDate = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date, $0) })
            for date in sortedDates {
                if let s = summaryByDate[date] {
                    entries.append(.summary(s))
                }
                if actDates.contains(date) {
                    let items = (try? store.activities(for: date)) ?? []
                    if !items.isEmpty {
                        entries.append(.activities(date: date, items: items))
                    }
                }
            }
            DispatchQueue.main.async { journalEntries = entries }
        }
    }

    /// For range keys "start..end" return "end"; otherwise return the key unchanged.
    /// Used as the secondary sort key so weekly/monthly summaries sort next to
    /// activities on their end-of-period date.
    private static func endDateKey(_ key: String) -> String {
        key.components(separatedBy: "..").last ?? key
    }

    private func saveActivity() {
        let trimmed = newLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let cal = Calendar.current
        var dayComps = cal.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComps = cal.dateComponents([.hour, .minute], from: newStartTime)
        dayComps.hour   = timeComps.hour
        dayComps.minute = timeComps.minute
        let startDate = cal.date(from: dayComps) ?? selectedDate

        var act = OfflineActivity(
            startTs: Int64(startDate.timeIntervalSince1970 * 1000),
            durationSecs: Int64(newDurationMins * 60),
            label: trimmed,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        try? store.insert(&act)
        showAdd = false
        loadActivities()
    }

    private func deleteActivity(_ act: OfflineActivity) {
        guard let id = act.id else { return }
        try? store.delete(id: id)
        loadActivities()
    }

    private func startTimeString(_ act: OfflineActivity) -> String {
        let date = Date(timeIntervalSince1970: Double(act.startTs) / 1000)
        return Self.timeFormatter.string(from: date)
    }

    // MARK: - Summary edit/delete actions

    private func saveEditedSummary(_ s: DailySummary) {
        DispatchQueue.global(qos: .userInitiated).async {
            try? OfflineStore().saveSummary(s)
            NotificationCenter.default.post(name: .dailySummaryDidSave, object: nil)
        }
    }

    private func deleteSummary(_ s: DailySummary) {
        DispatchQueue.global(qos: .userInitiated).async {
            try? OfflineStore().deleteSummary(date: s.date)
            NotificationCenter.default.post(name: .dailySummaryDidSave, object: nil)
        }
    }
}

// MARK: - Summary Editor Sheet

private struct SummaryEditorSheet: View {
    @State var summary: DailySummary
    let onSave: (DailySummary) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑摘要 · \(summary.date)")
                .font(.headline)

            Text("内容 (支持 Markdown)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $summary.content)
                .font(.body)
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )

            HStack {
                Stepper("评分: \(summary.score) / 5",
                        value: $summary.score, in: 0...5)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("关键词（逗号分隔）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $summary.keywords)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") { onSave(summary) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 380)
    }
}
