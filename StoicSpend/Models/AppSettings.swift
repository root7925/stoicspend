import Foundation
import SwiftData

/// 应用设置 — 单例模型，跟踪 Onboarding、冷静期、币种
///
/// 去付费化（2026-11-10）：App 全功能免费、无内购，StoreKit 服务已移除。
@Model
final class AppSettings {
    var id: UUID
    var hasCompletedOnboarding: Bool
    var installDate: Date

    // 冷静期设置（免费功能）
    var cooldownEnabled: Bool
    var cooldownHours: Int  // 24 或 72

    // 币种设置
    var currentCurrency: String       // ISO 4217，如 "USD"；空字符串表示按 locale 推断
    var customRates: [String: Double] // 用户覆盖的汇率（key=币种，value=对USD汇率）

    init() {
        self.id = UUID()
        self.hasCompletedOnboarding = false
        self.installDate = .now
        self.cooldownEnabled = false
        self.cooldownHours = 24
        self.currentCurrency = ""
        self.customRates = [:]
    }
}
