import SwiftUI
import AppKit

struct AFKReturnView: View {
    private enum FocusedField: Hashable {
        case summary
        case notes
    }

    let startTs: Int64
    let endTs: Int64
    let onSave: (WorkSession) -> Void
    let onDismiss: () -> Void
    
    @State private var summary: String = ""
    @State private var notes: String = ""
    @State private var selectedCategoryId: String = "focus"
    @State private var topApps: [AppStat] = []
    @State private var categories: [SessionCategory] = SessionCategory.all
    @State private var isGenerating = false
    @FocusState private var focusedField: FocusedField?
    
    private var durationMins: Int {
        Int((endTs - startTs) / 60000)
    }
    
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            SeedoPageHeading(title: "欢迎回来", subtitle: "这段时间，做了些什么？", symbol: "person.crop.circle.badge.clock")
            Text("\(durationMins) 分钟 · \(formatTime(startTs)) — \(formatTime(endTs))")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(SeedoStyle.accent)
            if !topApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("离席前主要在使用：").font(.headline)
                    ForEach(topApps.prefix(3)) { app in
                        HStack {
                            Text(app.appOrDomain)
                            Spacer()
                            Text("\(Int(app.totalSecs / 60)) 分钟").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("这段时间在做什么？").font(.headline)
                    Spacer()
                    Button(action: generateAISummary) {
                        Label(isGenerating ? "生成中..." : "AI 一键生成", systemImage: "sparkles")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SeedoStyle.accent)
                    .disabled(isGenerating)
                }
                
                SeedoCategoryPicker(categories: categories, selection: $selectedCategoryId)

                TextField("这次活动的主要总结...", text: $summary)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .focused($focusedField, equals: .summary)
                
                Text("备注 (Notes)").font(.headline)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 100)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.05))
                    .focused($focusedField, equals: .notes)
                    .simultaneousGesture(TapGesture().onEnded {
                        focusedField = .notes
                    })
            }
            
            HStack(spacing: 20) {
                Button("忽略 (Esc)") { onDismiss() }
                    .buttonStyle(SeedoButtonStyle())
                    .keyboardShortcut(.cancelAction)
                
                Button("记录并关闭") {
                    save()
                }
                .buttonStyle(SeedoButtonStyle(prominent: true))
                .tint(.blue)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(28)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 480, minHeight: 400)
        .background(SeedoStyle.canvas)
        .tint(SeedoStyle.accent)
        .onAppear {
            requestInitialFocus()
            loadTopApps()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Menu-bar apps can render SwiftUI before their window becomes key.
            // Re-requesting a field only when none is active preserves a user's
            // click into Notes and lets the Chinese IME keep first responder.
            if focusedField == nil {
                requestInitialFocus()
            }
        }
    }

    private func requestInitialFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard focusedField == nil else { return }
            focusedField = .summary
        }
    }
    
    private func save() {
        let session = WorkSession(
            startTs: startTs,
            endTs: endTs,
            topAppsJson: "[]",
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: "completed",
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            isManual: true,
            title: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryId: selectedCategoryId
        )
        onSave(session)
    }
    
    private func formatTime(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ts) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func loadTopApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = (try? EventStore().topApps(startMs: startTs, endMs: endTs, limit: 5)) ?? []
            DispatchQueue.main.async {
                self.topApps = apps
            }
        }
    }
    
    private func generateAISummary() {
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
                    print("AI Generate error: \\(error)")
                }
            }
        }
    }
}
