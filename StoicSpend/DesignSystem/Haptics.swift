import UIKit

/// FR-15 触感 — 快记全链路统一反馈：
/// 键盘按键 light / chip 选中 selection / 保存成功 success
enum Haptics {
    private static let keyImpact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func keyLight() {
        keyImpact.impactOccurred()
    }

    static func selectionChanged() {
        selection.selectionChanged()
    }

    static func saveSuccess() {
        notification.notificationOccurred(.success)
    }
}
