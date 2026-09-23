import SwiftUI

struct CoachTasksView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var tasks = TodayTaskStore.shared
    @State private var isRefreshingCoach = false
    @State private var coachError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("执行力教练", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isRefreshingCoach {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        refreshCoachTasks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("刷新今日建议")
                }
            }
            
            if let error = coachError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else if appState.aiCoachTasks.isEmpty {
                Text("点击刷新由 AI 生成今日优先建议")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(appState.aiCoachTasks.enumerated()), id: \.offset) { _, task in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .padding(.top, 5)
                                .foregroundStyle(SeedoStyle.accent)
                            Text(task)
                                .font(.system(size: 12))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Button(tasks.contains(task) ? "已添加" : "添加任务") {
                                tasks.add(task)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .disabled(tasks.contains(task))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func refreshCoachTasks() {
        isRefreshingCoach = true
        coachError = nil
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let todayStr = df.string(from: Date())
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let context = try SummaryContextBuilder().build(for: todayStr)

                AIService.shared.generateCoachTasks(context: context) { result in
                    DispatchQueue.main.async {
                        isRefreshingCoach = false
                        switch result {
                        case .success(let tasks):
                            if AppState.todayKey() == todayStr { self.appState.aiCoachTasks = tasks }
                            if let data = try? JSONEncoder().encode(tasks),
                               let json = String(data: data, encoding: .utf8) {
                                AppDatabase.shared.saveSetting(key: "ai_coach_tasks:\(todayStr)", value: json)
                            }
                        case .failure(let error):
                            self.coachError = error.localizedDescription
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isRefreshingCoach = false
                    self.coachError = "构建上下文失败"
                }
            }
        }
    }
    
}
