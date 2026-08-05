import SwiftUI
import UIKit

/// 设计令牌 — 所有颜色、字体、尺寸的唯一来源
/// 详见 Agent.md 第 3 节
/// 支持深色/浅色模式自适应
enum DesignTokens {
    // MARK: - 颜色（自适应深色/浅色模式）
    
    /// 主文字/深色背景 — 浅色模式用深墨色文字，深色模式用石色文字
    static let ink = Color(light: 0x1C1B17, dark: 0xE6E0D2)
    
    /// 卡片浅色背景 — 浅色模式用暖白卡片，深色模式用深色卡片
    static let stone = Color(light: 0xE6E0D2, dark: 0x3A3830)
    
    /// 石色暗调
    static let stoneDim = Color(light: 0xD8D2C1, dark: 0x2E2C26)
    
    /// 卡片背景
    static let card = Color(light: 0xF2EFE6, dark: 0x252320)
    
    /// 主强调色 — 铜色
    static let bronze = Color(light: 0x8B6A42, dark: 0xC09356)
    
    /// 次强调色 — 铜绿
    static let verdigris = Color(light: 0x5E6E62, dark: 0x7A9080)
    
    /// 付费锁定标识 — 锈色
    static let rust = Color(light: 0x7C4A36, dark: 0xC4755A)
    
    /// 次要文字
    static let ash = Color(light: 0x6E6B60, dark: 0x9E9B8E)
    
    /// 页面主背景
    static let paper = Color(light: 0xFAF8F3, dark: 0x1C1B17)
    
    /// 深色卡片背景（Paywall/ShareCard 等深色场景，不随模式切换）
    static let darkCard = Color(hex: 0x252320)

    // MARK: - 常驻深色 token（Paywall 等固定深色 UI，不随系统外观切换）

    /// 深色页面背景 — 固定深墨色
    static let darkInk = Color(hex: 0x1C1B17)

    /// 深色卡片上的主文字 — 固定石色
    static let darkStone = Color(hex: 0xE6E0D2)

    /// 深色卡片上的次要文字 — 固定灰墨色
    static let darkAsh = Color(hex: 0x9E9B8E)
    
    /// 深色径向渐变起始色（启动图/Onboarding 背景）
    static let gradientStart = Color(hex: 0x242017)
    
    /// 深色径向渐变结束色
    static let gradientEnd = Color(hex: 0x181712)

    // MARK: - 尺寸
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 24
    }

    // MARK: - 控制环
    enum ControlRing {
        static let defaultSize: CGFloat = 120
        static let dashboardSize: CGFloat = 240
        static let lineWidth: CGFloat = 12
        static let tickWidth: CGFloat = 3
        static let tickHeight: CGFloat = 10
    }
}

// MARK: - Color Hex 扩展

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
    
    /// 自适应深色/浅色模式 — 使用 UIColor 动态 provider
    init(light: UInt, dark: UInt) {
        let uiColor = UIColor { traitCollection in
            let hex = traitCollection.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1.0
            )
        }
        self.init(uiColor)
    }
}
