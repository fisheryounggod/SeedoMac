// SeedoMac/Views/Dashboard/AddActivitySheet.swift
import SwiftUI

struct AddActivitySheet: View {
    @State private var summary: String = ""
    @State private var label: String = ""
    @State private var selectedDate: Date = Date()
    @State private var startTime: Date = Date()
    @State private var durationMins: Int = 30
    @State private var selectedCategoryId: String = "focus"
    let onSave: (WorkSession) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手动记录活动").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("标题").font(.caption).foregroundStyle(.secondary)
                TextField("这次活动的主要总结...", text: $summary)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("备注").font(.caption).foregroundStyle(.secondary)
                TextField("具体背景、原因或其他说明", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("日期")
                DatePicker("", selection: $selectedDate,
                           displayedComponents: .date)
                    .labelsHidden()
            }

            HStack(spacing: 12) {
                Text("开始时间")
                DatePicker("", selection: $startTime,
                           displayedComponents: [.hourAndMinute])
                    .labelsHidden()

                Spacer().frame(width: 12)

                Text("时长")
                TextField("", value: $durationMins, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                Text("分钟")
                Stepper("", value: $durationMins, in: 1...1440, step: 5)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("类别").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(SessionCategory.all) { cat in
                        Button {
                            selectedCategoryId = cat.id
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(cat.color).frame(width: 8, height: 8)
                                Text(cat.name).font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedCategoryId == cat.id ? cat.color.opacity(0.15) : Color.primary.opacity(0.05))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedCategoryId == cat.id ? cat.color.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty && label.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PrefillAddActivity"))) { note in
            if let durationSecs = note.object as? Double {
                let mins = Int(round(durationSecs / 60.0))
                self.durationMins = max(1, mins)
                self.startTime = Date().addingTimeInterval(-durationSecs)
            }
        }
    }

    private func save() {
        let cal = Calendar.current
        var dayComps = cal.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComps = cal.dateComponents([.hour, .minute], from: startTime)
        dayComps.hour = timeComps.hour
        dayComps.minute = timeComps.minute
        let finalStart = cal.date(from: dayComps) ?? Date()

        let session = WorkSession(
            startTs: Int64(finalStart.timeIntervalSince1970 * 1000),
            endTs: Int64(finalStart.addingTimeInterval(TimeInterval(durationMins * 60)).timeIntervalSince1970 * 1000),
            topAppsJson: "[]",
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: "completed",
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            isManual: true,
            title: label.trimmingCharacters(in: .whitespaces),
            categoryId: selectedCategoryId
        )
        onSave(session)
    }
}
