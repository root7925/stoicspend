import Foundation

/// 消费性质 — 主动选择（可控）/ 冲动驱动（可改善）/ 必需品（不可控）
/// rawValue 持久化，不随语言变化；从 Expense.swift 抽出以便 Watch target 共享（FR-24）
enum ExpenseNature: String, Codable {
    case chosen     // 主动选择 — 可控
    case impulse    // 冲动驱动 — 可改善
    case necessity  // 必需品 — 不可控

    /// 本地化显示标签（与快记页 natureChip 文案同 key）
    var localizedName: String {
        switch self {
        case .chosen:    return NSLocalizedString("✓ 主动选择", comment: "")
        case .necessity: return NSLocalizedString("· 必须花", comment: "")
        case .impulse:   return NSLocalizedString("△ 冲动了", comment: "")
        }
    }
}

/// 消费分类 — 九分法（饮食/爱美/交通/亲朋宠/住房/电子/旅行/学习/其他）
/// rawValue 用稳定 key（与 Localizable.xcstrings key 对应），不随语言变化
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food      = "cat.food"
    case beauty    = "cat.beauty"
    case transport = "cat.transport"
    case family    = "cat.family"
    case housing   = "cat.housing"
    case gadget    = "cat.gadget"
    case travel    = "cat.travel"
    case learning  = "cat.learning"
    case other     = "cat.other"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .food:      return "🍜"
        case .beauty:    return "💄"
        case .transport: return "🚕"
        case .family:    return "🐾"
        case .housing:   return "🏠"
        case .gadget:    return "📱"
        case .travel:    return "✈️"
        case .learning:  return "📚"
        case .other:     return "◇"
        }
    }

    /// 本地化显示名称 — 从 Localizable.xcstrings 读取
    var localizedName: String {
        NSLocalizedString(rawValue, comment: "")
    }
}
