// Seedo/Views/Dashboard/AddActivitySheet.swift
import SwiftUI
import AppKit

struct AddActivitySheet: View {
    @State private var summary: String = ""
    @State private var label: String = ""
    @State private var selectedDate: Date = Date()
    @State private var startTime: Date = Date()
    @State private var durationMins: Int = 30
    @State private var selectedCategoryId: String = "focus"
    @State private var isGenerating = false
    @State private var saveError: String?
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool
    let onSave: (WorkSession, @escaping (Result<Void, Error>) -> Void) -> Void
    let onCancel: () -> Void

    init(initialDuration: Double? = nil, now: Date = Date(), onSave: @escaping (WorkSession, @escaping (Result<Void, Error>) -> Void) -> Void, onCancel: @escaping () -> Void) {
        let prefill = Self.prefill(duration: initialDuration, now: now)
        _selectedDate = State(initialValue: prefill.start)
        _startTime = State(initialValue: prefill.start)
        _durationMins = State(initialValue: prefill.minutes)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    static func prefill(duration: Double?, now: Date) -> (start: Date, minutes: Int) {
        guard let duration, duration.isFinite, duration > 0 else { return (now, 30) }
        let seconds = min(duration, 86_400)
        return (now.addingTimeInterval(-seconds), max(1, Int((seconds / 60).rounded())))
    }

    private var isValid: Bool {
        (1...1440).contains(durationMins) &&
        (!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
         !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SeedoPageHeading(title: "记录一段投入", subtitle: "让每一次专注都有迹可循。", symbol: "square.and.pencil")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("标题").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: generateAISummary) {
                        Label(isGenerating ? "生成中..." : "AI 一键生成", systemImage: "sparkles")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SeedoStyle.accent)
                    .disabled(isGenerating)
                }
                TextField("这次活动的主要总结...", text: $summary)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("备注").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $label)
                    .font(.body)
                    .frame(height: 100)
                    .scrollContentBackground(.hidden)
                    .seedoInput()
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
                SeedoCategoryPicker(categories: SessionCategory.all, selection: $selectedCategoryId)
            }
            TodayGoalEditor()
        }
        .padding(24)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { formContent.disabled(isSaving) }
            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.red).padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .buttonStyle(SeedoButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .buttonStyle(SeedoButtonStyle(prominent: true))
                    .disabled(!isValid || isGenerating || isSaving)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(20)
        }
        .frame(minWidth: 460)
        .background(SeedoStyle.canvas)
        .tint(SeedoStyle.accent)
        .onAppear { focusTitleField() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow,
                  window.title == "手动记录活动" else { return }
            focusTitleField()
        }
    }

    private func focusTitleField() {
        // A menu-bar app may render the hosting view before its window becomes
        // key. Deferring the focus request until the next main-run-loop turn
        // makes the NSTextField a real first responder, including IME input
        // and text selection.
        DispatchQueue.main.async {
            titleFocused = true
        }
    }

    private func save() {
        guard isValid, !isSaving else { return }
        isSaving = true
        saveError = nil
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
        onSave(session) { result in
            isSaving = false
            if case .failure(let error) = result {
                saveError = "保存失败，请重试：\(error.localizedDescription)"
            }
        }
    }

    private func generateAISummary() {
        guard (1...1440).contains(durationMins) else { return }
        let cal = Calendar.current
        var dayComps = cal.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComps = cal.dateComponents([.hour, .minute], from: startTime)
        dayComps.hour = timeComps.hour
        dayComps.minute = timeComps.minute
        let finalStart = cal.date(from: dayComps) ?? Date()
        let startTs = Int64(finalStart.timeIntervalSince1970 * 1000)
        let endTs = Int64(finalStart.addingTimeInterval(TimeInterval(durationMins * 60)).timeIntervalSince1970 * 1000)
        
        isGenerating = true
        AIService.shared.generateSessionSummary(startTs: startTs, endTs: endTs) { result in
            DispatchQueue.main.async {
                isGenerating = false
                switch result {
                case .success(let text):
                    if !text.isEmpty {
                        self.summary = text
                    }
                case .failure(let error):
                    print("AI Generate error: \(error)")
                }
            }
        }
    }
}
