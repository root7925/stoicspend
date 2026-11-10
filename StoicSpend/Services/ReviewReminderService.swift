import Foundation
import UserNotifications

/// 晚间回顾提醒 — 每日固定时间本地通知（FR-06，默认 21:00，可关）
enum ReviewReminderService {

    static let notificationID = "review.reminder.daily"

    /// 应用当前提醒设置：关闭则移除待发通知，开启则（重）注册每日触发
    static func apply(enabled: Bool, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        guard enabled else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            schedule(center: center, hour: hour, minute: minute)
        }
    }

    private static func schedule(center: UNUserNotificationCenter, hour: Int, minute: Int) {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("晚间回顾", comment: "")
        content.body = NSLocalizedString("花 10 秒，看看今天的消费", comment: "")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        center.add(request)
    }
}
