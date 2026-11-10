import Foundation
import UserNotifications

/// 本地通知服务 — P1-3 冲动冷却免费化配套
///
/// 冷却窗口结束后提醒用户："理性已追上欲望"，回看刚才差点下的单。
enum NotificationService {
    static let cooldownIdentifier = "stoic.cooldown.reminder"

    /// 请求通知授权（首次启用冷却时调用）
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 安排冷却结束提醒（cooldownHours 小时后触发一次）
    static func scheduleCooldownReminder(hours: Int) {
        requestAuthorization()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [cooldownIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Cooldown complete"
        content.body = "Reason has caught up with desire — revisit what you almost bought."
        content.sound = .default

        let seconds = TimeInterval(max(hours, 1) * 3600)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: cooldownIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// 取消待发的冷却提醒（关闭冷却时调用）
    static func cancelCooldownReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [cooldownIdentifier])
    }
}
