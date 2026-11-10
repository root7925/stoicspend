import Foundation
import SwiftData

/// 月度预算模式
/// - free:    免费（默认，P0-2 月度预算对所有用户开放）
/// - premium: 预留，未来若对预算做高级能力（如多预算/子分类）再启用
enum BudgetMode: String, Codable, CaseIterable, Identifiable {
    case free
    case premium

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .free:    NSLocalizedString("budget.mode.free", comment: "")
        case .premium: NSLocalizedString("budget.mode.premium", comment: "")
        }
    }
}

/// 月度预算模型 — P0-2 新增（免费功能）
///
/// 设计要点：
/// - 全用户默认可用（mode 默认 .free），无付费门槛
/// - `monthlyLimit` 为 0 表示未设置预算
/// - 进度按"当前自然月的可控支出（nature == .chosen）"计算，跨月自然重置，无需持久化每月快照
@Model
final class BudgetModel {
    var id: UUID
    var monthlyLimit: Double
    var mode: BudgetMode
    var createdAt: Date

    init(monthlyLimit: Double = 0, mode: BudgetMode = .free) {
        self.id = UUID()
        self.monthlyLimit = monthlyLimit
        self.mode = mode
        self.createdAt = .now
    }
}
