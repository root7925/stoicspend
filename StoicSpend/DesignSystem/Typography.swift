import SwiftUI

/// 展示层字体选项 — 仅作用于标题/语录/大数字（serif 层）
/// 正文 sans / 数据 mono 始终保持系统字体，保证 UI 布局安全
/// 三款均为可商用授权：系统衬线（随系统）、LXGW WenKai Lite（OFL）、Playfair Display（OFL）
enum DisplayFont: String, CaseIterable, Identifiable {
    case classic    // 书卷 · 系统衬线（默认，与历史版本一致）
    case wenkai     // 文楷 · 温润书写
    case editorial  // 杂志 · 编辑排版

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("font.\(rawValue)", comment: "")
    }
}

/// 字体修饰符 — 三类字体风格
/// 详见 Agent.md 第 3.2 节
struct Typography {
    // 展示层 — 标题/语录/金额，跟随用户字体选择
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch ThemeManager.shared.displayFont {
        case .classic:
            return .system(size: size, weight: weight, design: .serif)
        case .wenkai:
            // 单一字重（Medium），weight 不参与匹配
            return .custom("LXGW WenKai Lite", size: size)
        case .editorial:
            // 家族名 + 字重匹配（Medium/SemiBold/Bold 已注册，.regular 落到最近字重）
            return .custom("Playfair Display", size: size).weight(weight)
        }
    }

    // 无衬线体 — 界面文字（保持系统，不随字体设置变化）
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // 等宽体 — 数据(时间/百分比/价格)（保持系统，保证数字对齐）
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// 字体设置的说明文案
    static var displayPreviewNote: String {
        NSLocalizedString("font.note", comment: "")
    }
}

// MARK: - View 修饰符扩展

extension View {
    func serifTitle(_ size: CGFloat = 28, weight: Font.Weight = .bold) -> some View {
        font(Typography.serif(size, weight: weight))
    }

    func sansBody(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> some View {
        font(Typography.sans(size, weight: weight))
    }

    func monoData(_ size: CGFloat = 14, weight: Font.Weight = .medium) -> some View {
        font(Typography.mono(size, weight: weight))
    }
}
