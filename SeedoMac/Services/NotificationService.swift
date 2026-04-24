import Foundation
import UserNotifications
import AppKit

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
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
        cancelAllDailyReminders()
        
        let content = UNMutableNotificationContent()
        content.title = "该开启专注了"
        content.body = "设定一个小目标，开始今天的深度工作吧！"
        content.sound = .default
        
        let calendar = Calendar.current
        for (index, time) in times.enumerated() {
            let components = calendar.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "daily_focus_reminder_\(index)", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request)
        }
        print("[NotificationService] Scheduled \(times.count) daily reminders")
    }
    
    func showUsageReminder() {
        let content = UNMutableNotificationContent()
        content.title = "使用电脑太久啦"
        content.body = "您已经连续使用电脑一段时间了，不如开启一轮专注来记录一下？"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "usage_reminder_\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
