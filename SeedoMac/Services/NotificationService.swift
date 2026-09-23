import Foundation
import UserNotifications
import AppKit

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private var dayObserver: NSObjectProtocol?
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            let state = AppState.shared
            state.refreshTodayGoal()
            if state.isDailyRemindersEnabled {
                self?.scheduleDailyReminders(times: state.dailyReminderTimes)
            }
        }
    }
    
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("[NotificationService] Permission granted")
            }
            completion?(granted)
        }
    }
    
    func scheduleDailyReminders(times: [Date]) {
        // Date-specific requests prevent today's task from repeating tomorrow.
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers:
            (0..<64).map { "daily_focus_reminder_\($0)" })
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var index = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            for time in times.sorted() {
                let clock = calendar.dateComponents([.hour, .minute], from: time)
                guard let date = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day), date > now, index < 63 else { continue }
                let content = UNMutableNotificationContent()
                content.title = "该开启专注了"
                content.body = goalReminder(for: formatter.string(from: date))
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(UNNotificationRequest(identifier: "daily_focus_reminder_\(index)", content: content, trigger: trigger))
                index += 1
            }
        }
        print("[NotificationService] Scheduled \(times.count) daily reminders")
    }
    
    func showUsageReminder() {
        let content = UNMutableNotificationContent()
        content.title = "使用电脑太久啦"
        content.body = goalReminder(for: AppState.todayKey())
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "usage_reminder_\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func goalReminder(for date: String) -> String {
        let goal = AppDatabase.shared.exactDailyPlan(for: date).trimmingCharacters(in: .whitespacesAndNewlines)
        return goal.isEmpty ? "今天还没有设定目标，点击添加今天要完成的任务。" : "今日任务：\(goal)"
    }
    
    func cancelAllDailyReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map { $0.identifier }.filter { $0.contains("daily_focus_reminder") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
    
    // MARK: - Delegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // If user clicks the notification, open the app/dashboard
        if response.notification.request.identifier.contains("reminder") {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .shouldShowAddActivity, object: nil)
            }
        }
        completionHandler()
    }
}
