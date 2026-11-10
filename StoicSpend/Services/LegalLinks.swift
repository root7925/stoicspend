import Foundation
import SwiftUI

/// 集中管理法务与联系链接
/// 法务页托管在 Vercel 静态站 stoicspend.vercel.app（源码在仓库 web/ 目录）
enum LegalLinks {
    /// 隐私政策
    static let privacyPolicy = URL(string: "https://stoicspend.vercel.app/privacy.html")!

    /// 使用条款
    static let termsOfUse = URL(string: "https://stoicspend.vercel.app/terms.html")!

    /// 应用 App Store 页面（用于评分/管理）
    static let appStore = URL(string: "https://apps.apple.com/app/idStoicSpend")!

    // MARK: 联系作者

    /// 联系作者邮箱（mailto 链接）
    static let supportEmail = URL(string: "mailto:guanerlin9527@gmail.com")!

    /// 官方微博主页
    static let weiboHome = URL(string: "https://weibo.com/u/1787492425")!

    /// 支持页（Vercel 静态站，部署方式：cd web && npx vercel --prod）
    static let supportHome = URL(string: "https://stoicspend.vercel.app/")!
}
