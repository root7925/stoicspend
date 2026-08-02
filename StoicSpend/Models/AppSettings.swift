import Foundation
import SwiftData

/// 订阅状态
enum SubscriptionStatus: String, Codable {
    case free
    case monthly
    case yearly
    case intro  // 首月体验价

    var isPremium: Bool {
        self != .free
    }
}

/// 应用设置 — 单例模型，跟踪 Onboarding 和订阅状态
@Model
final class AppSettings {
    var id: UUID
    var hasCompletedOnboarding: Bool
    var subscriptionStatus: SubscriptionStatus
    var subscriptionExpiry: Date?
    var installDate: Date

    // 冷静期设置（付费功能）
    var cooldownEnabled: Bool
    var cooldownHours: Int  // 24 或 72

    // 币种设置（Phase 5 新增）
    var currentCurrency: String       // ISO 4217，如 "USD"；空字符串表示按 locale 推断
    var customRates: [String: Double] // 用户覆盖的汇率（key=币种，value=对USD汇率）

    init() {
        self.id = UUID()
        self.hasCompletedOnboarding = false
        self.subscriptionStatus = .free
        self.subscriptionExpiry = nil
        self.installDate = .now
        self.cooldownEnabled = false
        self.cooldownHours = 24
        self.currentCurrency = ""
        self.customRates = [:]
    }
}
