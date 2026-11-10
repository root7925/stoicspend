import UIKit
import os.log

/// FR-06 P1 图标动态替换 — App 图标跟随主题强调色
/// 6 个主题色 alternate icons（Assets.xcassets/AppIcon-<theme>.appiconset），
/// 经 project.yml CFBundleAlternateIcons 注册；默认图标为青铜色原图标。
enum AppIconService {
    static let followsThemeKey = "appIcon.followsTheme"
    private static let logger = Logger(subsystem: "com.zhenglin.stoicspend", category: "AppIcon")

    static var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    static var followsTheme: Bool {
        get { UserDefaults.standard.bool(forKey: followsThemeKey) }
        set { UserDefaults.standard.set(newValue, forKey: followsThemeKey) }
    }

    /// 主题对应的 alternate icon 名（AppIcon-jade 等）
    static func iconName(for theme: AppTheme) -> String {
        "AppIcon-\(theme.rawValue)"
    }

    /// 按设置同步图标；重复切换会弹系统确认提示，仅在目标不同时调用
    static func syncIcon(for theme: AppTheme) {
        guard supportsAlternateIcons else { return }
        let target: String? = followsTheme ? iconName(for: theme) : nil
        guard UIApplication.shared.alternateIconName != target else { return }
        UIApplication.shared.setAlternateIconName(target) { error in
            if let error {
                logger.error("图标切换失败: \(error.localizedDescription)")
            }
        }
    }
}
