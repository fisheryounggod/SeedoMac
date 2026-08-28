import SwiftUI

struct AFKReturnView: View {
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
    @FocusState private var isFocused: Bool
    
    private var durationMins: Int {
        Int((endTs - startTs) / 60000)
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("检测到一段离席/工作时间")
                    .font(.system(size: 32, weight: .bold))
                
                Text("\(durationMins) 分钟 (\(formatTime(startTs)) - \(formatTime(endTs)))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
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
                    .foregroundStyle(.blue)
                    .disabled(isGenerating)
                }
                
                // Category Picker (Horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { cat in
                            Button(action: { selectedCategoryId = cat.id }) {
                                Text(cat.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedCategoryId == cat.id ? cat.color : Color.secondary.opacity(0.1))
                                    .foregroundStyle(selectedCategoryId == cat.id ? .white : Color.primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                TextField("这次活动的主要总结...", text: $summary)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .focused($isFocused)
                
                Text("备注 (Notes)").font(.headline)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 100)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.05))
            }
            
            HStack(spacing: 20) {
                Button("忽略 (Esc)") { onDismiss() }
                    .buttonStyle(.bordered)
                    .scaleEffect(1.1)
                
                Button("记录并关闭") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .scaleEffect(1.2)
                .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)
        }
        .frame(minWidth: 500, idealWidth: 720, maxWidth: .infinity, minHeight: 600, idealHeight: 720, maxHeight: .infinity)
        .padding(40)
        .onAppear {
            isFocused = true
            loadTopApps()
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
