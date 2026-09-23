import SwiftUI

struct TodayGoalEditor: View {
    @ObservedObject private var appState = AppState.shared
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今日目标", systemImage: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedoStyle.accent)
                Spacer()
                if !editing {
                    Button(appState.todayGoal.isEmpty ? "添加" : "修改") {
                        beginEditing()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
            if editing {
                TextField("输入今天要完成的具体任务…", text: $draft, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)
                    .seedoInput()
                    .focused($focused)
                HStack {
                    Button("取消") { editing = false }.buttonStyle(SeedoButtonStyle())
                    Button("保存目标") {
                        appState.saveTodayGoal(draft)
                        editing = false
                    }
                    .buttonStyle(SeedoButtonStyle(prominent: true))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text(appState.todayGoal.isEmpty ? "为今天留一个清晰的方向。" : appState.todayGoal)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEditing() }
                    .help("双击修改今日目标")
            }
        }
        .seedoCard(padding: 18)
        .onAppear { appState.refreshTodayGoal() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            appState.refreshTodayGoal()
            editing = false
        }
    }

    private func beginEditing() {
        appState.refreshTodayGoal()
        draft = appState.todayGoal
        editing = true
        focused = true
    }
}
