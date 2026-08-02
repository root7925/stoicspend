import SwiftUI

/// 字体修饰符 — 三类字体风格
/// 详见 Agent.md 第 3.2 节
struct Typography {
    // 衬线体 — 标题/语录/金额
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // 无衬线体 — 界面文字
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // 等宽体 — 数据(时间/百分比/价格)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
