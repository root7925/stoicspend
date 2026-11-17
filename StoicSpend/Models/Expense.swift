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

/// FR-31 资金流类型 — 统计只认消费；退款负冲抵；收入仅落库不统计（产品拍板：不做收入统计）；转账不进任何统计
enum FlowType: String, Codable, CaseIterable, Identifiable {
    case expense  = "flow.expense"   // 消费
    case income   = "flow.income"    // 收入（仅导入落库）
    case transfer = "flow.transfer"  // 转账/还款（不进分类统计）
    case refund   = "flow.refund"    // 退款（负值冲抵）

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString(rawValue, comment: "")
    }
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

    // FR-29 自定义分类（可空；"custom:<uuid>"，覆盖 category 的显示与统计）
    var categoryRawOverride: String?

    // FR-31 资金流类型（默认消费，SwiftData 轻量迁移，旧数据自动回落）
    var flowTypeRaw: String = FlowType.expense.rawValue

    // FR-30 导入去重：外部账单交易单号
    var refId: String?

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

// MARK: - FR-29 自定义分类统一显示出口（内置 / 自定义）

extension Expense {
    /// 自定义类别 id（未关联时为 nil → 走内置 9 类）
    var customCategoryID: UUID? {
        get { categoryRawOverride.flatMap(CategoryStore.uuid(fromKey:)) }
        set { categoryRawOverride = newValue.map { CategoryStore.storageKey(for: $0) } }
    }

    /// 是否走自定义类别（类别已被删除时视为否，回落内置）
    var isCustomCategory: Bool {
        guard let id = customCategoryID else { return false }
        return CategoryStore.find(id: id) != nil
    }

    /// 统一显示 emoji：自定义优先，回退内置
    var categoryEmoji: String {
        if let id = customCategoryID, let cat = CategoryStore.find(id: id) {
            return cat.emoji
        }
        return category.emoji
    }

    /// 统一显示名：自定义优先（用户原文，不翻译），回退内置本地化名
    var categoryDisplayName: String {
        if let id = customCategoryID, let cat = CategoryStore.find(id: id) {
            return cat.name
        }
        return category.localizedName
    }

    /// 分组 key：内置用 rawValue，自定义用 "custom:<id>"（帐本/工作台/备份通用）
    /// 类别已被删除时回落内置 rawValue，避免孤儿分组
    var categoryGroupKey: String {
        if let id = customCategoryID, CategoryStore.find(id: id) != nil {
            return CategoryStore.storageKey(for: id)
        }
        return category.rawValue
    }
}

// MARK: - FR-31 资金流类型（统计口径统一出口）

extension Expense {
    var flowType: FlowType {
        get { FlowType(rawValue: flowTypeRaw) ?? .expense }
        set { flowTypeRaw = newValue.rawValue }
    }

    /// 是否计入统计（消费 + 退款；收入/转账永不进合计、图表、控制比、提醒）
    var isStatistical: Bool {
        flowType == .expense || flowType == .refund
    }

    /// 统计金额：消费为正，退款负冲抵，收入/转账为 0
    var statAmount: Double {
        switch flowType {
        case .expense:  return amount
        case .refund:   return -amount
        case .income, .transfer: return 0
        }
    }

    /// 列表展示用的类型标签（消费不显示）
    var flowTag: String? {
        flowType == .expense ? nil : flowType.localizedName
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
