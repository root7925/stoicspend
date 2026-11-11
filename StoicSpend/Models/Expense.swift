import Foundation
import SwiftData

// MARK: - 枚举定义

/// 价值观标签 — 记账三问第二题
/// rawValue 用稳定 key（与 Localizable.xcstrings key 对应），不随语言变化
enum ValueTag: String, Codable, CaseIterable, Identifiable {
    case health = "value.health"
    case growth = "value.growth"
    case family = "value.family"
    case freedom = "value.freedom"
    case enjoyment = "value.enjoyment"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .health:    return "heart"
        case .growth:    return "sprout"
        case .family:    return "house"
        case .freedom:   return "bird"
        case .enjoyment: return "wineglass"
        }
    }

    /// 本地化显示名称 — 从 Localizable.xcstrings 读取
    var localizedName: String {
        NSLocalizedString(rawValue, comment: "")
    }
}

// 消费性质 ExpenseNature（原「支出性质 — 控制圈二分法」）与消费分类 ExpenseCategory
// 已抽出至 Shared/Categories.swift（FR-24 Watch 快记需要与 watchOS target 共享这两组枚举）

/// 晚间回顾结果 — 每天 1 次，标记在某笔消费上
enum ReviewResult: String, Codable {
    case affirm      // ✓ 会再做同样选择
    case reconsider  // △ 会重新考虑
}

/// 记账时可选的情绪 — 可不选
enum ExpenseEmotion: String, Codable, CaseIterable, Identifiable {
    case calm      = "emo.calm"      // 平静
    case anxious   = "emo.anxious"   // 焦虑
    case excited   = "emo.excited"   // 兴奋
    case tired     = "emo.tired"     // 疲惫
    case stressed  = "emo.stressed"  // 压力
    case satisfied = "emo.satisfied" // 欣慰

    var id: String { rawValue }

    /// 本地化显示名称 — 从 Localizable.xcstrings 读取
    var localizedName: String {
        NSLocalizedString(rawValue, comment: "")
    }
}

// MARK: - 数据模型

/// 支出记录 — 核心模型，包含三问数据
@Model
final class Expense {
    var id: UUID
    var amount: Double
    var date: Date
    var note: String

    // 三问数据（均可选，用户可跳过）
    var nature: ExpenseNature?       // Q1: 主动选择 vs 冲动驱动
    var values: [ValueTag]           // Q2: 服务于哪个价值观（多选）
    var emotionalTrigger: String?    // Q3: 冲动消费的情绪触发点

    // 九分法分类（带默认值，兼容 CloudKit 旧数据）
    var category: ExpenseCategory = ExpenseCategory.food

    // 记账时情绪（可选）
    var emotion: ExpenseEmotion?

    // 晚间回顾结果（可选，每天最多 1 笔被标记）
    var review: ReviewResult?

    var createdAt: Date

    init(
        amount: Double,
        date: Date = .now,
        note: String = "",
        nature: ExpenseNature? = nil,
        values: [ValueTag] = [],
        emotionalTrigger: String? = nil,
        category: ExpenseCategory = .food,
        emotion: ExpenseEmotion? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.note = note
        self.nature = nature
        self.values = values
        self.emotionalTrigger = emotionalTrigger
        self.category = category
        self.emotion = emotion
        self.createdAt = .now
    }
}

// MARK: - 便捷查询扩展

extension Expense {
    /// 是否为可控支出（主动选择）
    var isControllable: Bool {
        nature == .chosen
    }

    /// 格式化金额（按 locale 默认币种，兼容旧调用）
    /// 注意：如用户已切换币种，View 层应改用 `formatted(currency:)` 传当前币种
    var formattedAmount: String {
        let currency = CurrencyService.defaultCurrencyForCurrentLocale()
        return CurrencyService.shared.format(amount, currency: currency)
    }

    /// 格式化金额（指定币种）
    func formatted(currency: String) -> String {
        CurrencyService.shared.format(amount, currency: currency)
    }

    /// 属于今天
    static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    /// 属于本周
    static func isThisWeek(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
    }
}
