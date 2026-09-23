import Foundation
import Combine
import GRDB

struct TodayTask: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var title: String
    var isCompleted = false
}

final class TodayTaskStore: ObservableObject {
    static let shared = TodayTaskStore(
        read: { AppDatabase.shared.setting(for: $0) },
        write: { key, value in
            try AppDatabase.shared.write { db in
                try AppSetting(key: key, value: value).save(db)
            }
        }
    )

    @Published private(set) var tasks: [TodayTask] = []
    @Published private(set) var day = ""
    @Published var error: String?
    private let read: (String) -> String?
    private let write: (String, String) throws -> Void
    private let currentDay: () -> String
    private var loadFailed = false

    init(read: @escaping (String) -> String?, write: @escaping (String, String) throws -> Void,
         currentDay: @escaping () -> String = { AppState.todayKey() }) {
        self.read = read
        self.write = write
        self.currentDay = currentDay
        refresh()
    }

    func refresh() {
        let nextDay = currentDay()
        guard nextDay != day else { return }
        day = nextDay
        tasks = []
        error = nil
        loadFailed = false
        guard let json = read("today_tasks:\(day)") else { return }
        do {
            tasks = try JSONDecoder().decode([TodayTask].self, from: Data(json.utf8))
        } catch {
            loadFailed = true
            self.error = "今日任务读取失败，原数据已保留。"
        }
    }

    func contains(_ title: String) -> Bool {
        tasks.contains { $0.title == title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @discardableResult func add(_ title: String) -> Bool {
        refresh()
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !contains(title) else { return false }
        return persist(tasks + [TodayTask(title: title)])
    }

    func toggle(_ id: String) {
        refresh()
        var updated = tasks
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isCompleted.toggle()
        persist(updated)
    }

    func remove(_ id: String) {
        refresh()
        persist(tasks.filter { $0.id != id })
    }

    @discardableResult private func persist(_ updated: [TodayTask]) -> Bool {
        guard !loadFailed else { return false }
        do {
            let data = try JSONEncoder().encode(updated)
            try write("today_tasks:\(day)", String(decoding: data, as: UTF8.self))
            tasks = updated
            error = nil
            return true
        } catch {
            self.error = "任务保存失败，请重试：\(error.localizedDescription)"
            return false
        }
    }
}
