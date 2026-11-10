import Foundation

/// P2-7 分享增长闭环 — 引荐码
///
/// 设计约束（与隐私承诺一致）：
/// - 引荐码在本机随机生成并持久化，**不含任何设备/账号标识**，不上传服务器；
/// - 引荐码只作为分享文案与卡片上的可传播标记，归因在落地页侧统计；
/// - 用户重装后会得到新码，属可接受损耗（不做设备指纹）。
@MainActor
final class ReferralService {
    static let shared = ReferralService()

    private let storageKey = "referralCode"

    /// 去除易混淆字符（0/O、1/I）的字母表
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    private init() {}

    /// 本机稳定引荐码，形如 `STOIC-7KQ4M2`
    var code: String {
        if let saved = UserDefaults.standard.string(forKey: storageKey), !saved.isEmpty {
            return saved
        }
        let generated = Self.generateCode()
        UserDefaults.standard.set(generated, forKey: storageKey)
        return generated
    }

    /// 带引荐参数的下载链接
    var inviteLink: URL {
        guard var components = URLComponents(url: LegalLinks.appStore, resolvingAgainstBaseURL: false) else {
            return LegalLinks.appStore
        }
        components.queryItems = [URLQueryItem(name: "ref", value: code)]
        return components.url ?? LegalLinks.appStore
    }

    /// 分享文案：金句 + 引荐码 + 下载链接
    func shareText(quote: String) -> String {
        let format = String(
            localized: "\"%1$@\"\n\nStoic Spend — spend on what you chose, not on what chose you.\nInvite code: %2$@\n%3$@"
        )
        return String(format: format, quote, code, inviteLink.absoluteString)
    }

    /// 复制邀请链接到剪贴板所用的纯文本
    var inviteMessage: String {
        let format = String(
            localized: "Join me on Stoic Spend with invite code %1$@\n%2$@"
        )
        return String(format: format, code, inviteLink.absoluteString)
    }

    private static func generateCode() -> String {
        let suffix = (0..<6).map { _ in String(alphabet.randomElement() ?? "X") }.joined()
        return "STOIC-\(suffix)"
    }
}
