import Foundation
import SwiftData

/// 每周斯多葛式复盘 — 仿《沉思录》三段式结构
@Model
final class WeeklyReview {
    var id: UUID
    var weekStart: Date
    var weekEnd: Date

    // 三段式固定问题（免费版）
    var whatWentRight: String       // 本周做对了什么财务决策
    var whatDeviated: String        // 哪次消费偏离了价值观
    var virtueToPractice: String    // 下周想练习的财务德性

    // 付费版 AI 追问（Foundation Models 生成）
    var aiFollowUp: String?
    var aiGeneratedAt: Date?

    var createdAt: Date

    init(
        weekStart: Date,
        weekEnd: Date,
        whatWentRight: String = "",
        whatDeviated: String = "",
        virtueToPractice: String = ""
    ) {
        self.id = UUID()
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.whatWentRight = whatWentRight
        self.whatDeviated = whatDeviated
        self.virtueToPractice = virtueToPractice
        self.createdAt = .now
    }

    /// 本周复盘是否已完成（三段都填写）
    var isComplete: Bool {
        !whatWentRight.isEmpty && !whatDeviated.isEmpty && !virtueToPractice.isEmpty
    }
}
