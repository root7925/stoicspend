import Foundation
import SwiftUI

/// 集中管理法务链接与订阅管理 URL
/// 发布前将 Privacy Policy / Terms of Use 发布到 spiritual-toolkit-web，填入真实 URL
enum LegalLinks {
    /// 隐私政策（待发布到 spiritual-toolkit-web 后填入）
    static let privacyPolicy = URL(string: "https://spiritual-toolkit.example.com/stoicspend/privacy")!

    /// 使用条款（待发布到 spiritual-toolkit-web 后填入）
    static let termsOfUse = URL(string: "https://spiritual-toolkit.example.com/stoicspend/terms")!

    /// Apple 订阅管理页（系统标准 URL，跳转到"设置 → Apple ID → 订阅"）
    static let manageSubscription = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// 应用 App Store 页面（用于评分/管理）
    static let appStore = URL(string: "https://apps.apple.com/app/idStoicSpend")!
}
