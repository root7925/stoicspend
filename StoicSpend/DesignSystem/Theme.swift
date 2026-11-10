import SwiftUI
import Combine

/// App 主题 — 6 个预设配色 + 🎲 随机色
/// 主强调色随主题切换，绿色=数据/肯定语义随主题衍生，金色=冲动/粉碎机语义固定不变
/// 选择持久化到 UserDefaults（@AppStorage），重启后记忆
enum AppTheme: String, CaseIterable, Identifiable {
    case jade       // 玉绿（默认）
    case gilded     // 鎏金
    case celadon    // 青瓷
    case dusk       // 暮紫
    case amber      // 暖橘
    case rose       // 玫瑰

    var id: String { rawValue }

    // 浅色/深色模式下的主强调色（dark 值即 PRD 定稿色）
    var accentLight: UInt {
        switch self {
        case .jade:    return 0x5F8A6F
        case .gilded:  return 0x9A7A33
        case .celadon: return 0x4F8880
        case .dusk:    return 0x7E6896
        case .amber:   return 0xB0764A
        case .rose:    return 0xA05F6D
        }
    }

    var accentDark: UInt {
        switch self {
        case .jade:    return 0x8FBF9F
        case .gilded:  return 0xC9A84C
        case .celadon: return 0x7FB8B0
        case .dusk:    return 0xA78FC4
        case .amber:   return 0xD9A06B
        case .rose:    return 0xC48793
        }
    }

    /// 衍生深色（数据渐变用）— 主强调色向墨绿/深色方向压暗
    var verdigrisLight: UInt {
        switch self {
        case .jade:    return 0x47684F
        case .gilded:  return 0x6E5A22
        case .celadon: return 0x3A6159
        case .dusk:    return 0x5A4A6B
        case .amber:   return 0x7E5434
        case .rose:    return 0x6F4249
        }
    }

    var verdigrisDark: UInt {
        switch self {
        case .jade:    return 0x6B8E7B
        case .gilded:  return 0x8E7A3C
        case .celadon: return 0x5A8C83
        case .dusk:    return 0x7B6A94
        case .amber:   return 0xA5805A
        case .rose:    return 0x956B74
        }
    }

    var accentColor: Color {
        Color(light: accentLight, dark: accentDark)
    }

    var verdigrisColor: Color {
        Color(light: verdigrisLight, dark: verdigrisDark)
    }

    var accentDimColor: Color {
        accentColor.opacity(0.15)
    }

    /// 主题名称（Text 字面量进入 String Catalog）
    var localizedName: String {
        switch self {
        case .jade:    return "主题·玉绿"
        case .gilded:  return "主题·鎏金"
        case .celadon: return "主题·青瓷"
        case .dusk:    return "主题·暮紫"
        case .amber:   return "主题·暖橘"
        case .rose:    return "主题·玫瑰"
        }
    }
}

/// 主题管理器 — 单例，供 DesignTokens 读取；视图可 observe 以即时刷新
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let storageKey = "appTheme"
    private static let displayFontKey = "displayFont"

    @Published var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
        }
    }

    /// 展示层字体（标题/语录/大数字）— Typography.serif 读取此值
    @Published var displayFont: DisplayFont {
        didSet {
            UserDefaults.standard.set(displayFont.rawValue, forKey: Self.displayFontKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        current = raw.flatMap(AppTheme.init(rawValue:)) ?? .jade
        let fontRaw = UserDefaults.standard.string(forKey: Self.displayFontKey)
        displayFont = fontRaw.flatMap(DisplayFont.init(rawValue:)) ?? .classic
    }

    /// 🎲 随机换一个不同于当前的主题
    func randomize() {
        let others = AppTheme.allCases.filter { $0 != current }
        current = others.randomElement() ?? .jade
    }
}
