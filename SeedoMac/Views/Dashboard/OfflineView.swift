// SeedoMac/Views/Dashboard/OfflineView.swift
import SwiftUI

struct OfflineView: View {
    @State private var selectedDate = Date()
    @State private var activities: [OfflineActivity] = []
    @State private var showAdd = false
    // Add-form state
    @State private var newLabel = ""
    @State private var newDurationMins: Int = 30
    @State private var newStartTime = Date()

    private let store = OfflineStore()

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
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if showAdd {
                addForm
                Divider()
            }
            activityList
        }
        .onAppear { loadActivities() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .onChange(of: selectedDate) { _ in loadActivities() }
            Spacer()
            Group {
                if showAdd {
                    Button("Cancel") {
                        showAdd.toggle()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("+ Add") {
                        showAdd.toggle()
                        newLabel = ""; newDurationMins = 30; newStartTime = Date()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    // MARK: - Add Form

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

    // MARK: - Activity List

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
                                Text(Self.timeFormatter.string(
                                    from: Date(timeIntervalSince1970: Double(act.startTs) / 1000)
                                ))
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

    // MARK: - Actions

    private func loadActivities() {
        let dateStr = Self.dayFormatter.string(from: selectedDate)
        activities = (try? store.activities(for: dateStr)) ?? []
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

}
