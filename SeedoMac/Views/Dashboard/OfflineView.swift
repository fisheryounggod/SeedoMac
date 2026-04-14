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

    // Shared
    @State private var activeTab: LogTab = .activities

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
            NotificationCenter.default.addObserver(
                forName: .dailySummaryDidSave, object: nil, queue: .main
            ) { _ in loadJournal() }
        }
        .onChange(of: activeTab) { tab in
            if tab == .journal { loadJournal() }
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
                Text(s.date)
                    .font(.headline)
                Spacer()
                if s.score > 0 {
                    Text(String(repeating: "★", count: s.score) +
                         String(repeating: "☆", count: max(0, 5 - s.score)))
                        .foregroundStyle(.orange)
                }
            }
            if !s.content.isEmpty {
                Text(s.content)
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

    // MARK: - Actions

    private func loadActivities() {
        let dateStr = Self.dayFormatter.string(from: selectedDate)
        activities = (try? store.activities(for: dateStr)) ?? []
    }

    private func loadJournal() {
        DispatchQueue.global(qos: .userInitiated).async {
            let summaries = (try? store.allSummaries()) ?? []
            let actDates  = (try? store.allActivityDates()) ?? []

            // Build sorted date set
            var dateSet = Set<String>(summaries.map(\.date))
            actDates.forEach { dateSet.insert($0) }
            let sortedDates = dateSet.sorted(by: >)

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
}
