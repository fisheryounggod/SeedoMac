import SwiftUI

struct TodayTasksView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var store = TodayTaskStore.shared
    @ObservedObject private var scheduler = BreakScheduler.shared
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("今日任务", systemImage: "checklist").font(.headline)
                Spacer()
                Text("\(store.tasks.filter { !$0.isCompleted }.count) 项未完成")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("添加今日任务…", text: $draft)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { addTask() }
                Button("添加", action: addTask)
                    .buttonStyle(.borderless)
                    .foregroundStyle(SeedoStyle.accent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if store.tasks.isEmpty {
                Text("还没有任务。可以从执行力教练的建议一键添加。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.tasks) { task in
                    HStack(spacing: 8) {
                        Button { store.toggle(task.id) } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isCompleted ? SeedoStyle.accent : .secondary)
                        }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).strikethrough(task.isCompleted)
                                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                .lineLimit(2)
                            if isActive(task) {
                                Text("进行中 · \(scheduler.timerMode == .countdown ? "番茄钟" : "正计时")")
                                    .font(.caption2)
                                    .foregroundStyle(SeedoStyle.accent)
                            }
                        }
                        Spacer(minLength: 4)
                        if !task.isCompleted {
                            Button("番茄") { begin(task, mode: .countdown) }
                                .buttonStyle(SeedoButtonStyle(prominent: isSelected(task, mode: .countdown)))
                                .controlSize(.small)
                                .help(isActive(task) ? "切换为番茄钟，保留当前进度" : "用番茄钟开始任务")
                            Button("正计时") { begin(task, mode: .stopwatch) }
                                .buttonStyle(SeedoButtonStyle(prominent: isSelected(task, mode: .stopwatch)))
                                .controlSize(.small)
                                .help(isActive(task) ? "切换为正计时，保留当前进度" : "用正计时开始任务")
                        }
                        Button { store.remove(task.id) } label: {
                            Image(systemName: "xmark").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                        .accessibilityLabel("删除任务")
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .onAppear { store.refresh() }
    }

    private func addTask() {
        guard store.add(draft) else { return }
        draft = ""
    }

    private func begin(_ task: TodayTask, mode: BreakScheduler.TimerMode) {
        scheduler.startTask(task.title, mode: mode)
        appState.isTracking = true
    }

    private func isActive(_ task: TodayTask) -> Bool {
        scheduler.boundTaskTitle == task.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSelected(_ task: TodayTask, mode: BreakScheduler.TimerMode) -> Bool {
        isActive(task) && scheduler.timerMode == mode
    }
}
