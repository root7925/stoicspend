import Foundation
import SwiftData

/// 已拥有清单 — 对抗消费主义欲望的知足清单
@Model
final class AlreadyHaveItem {
    var id: UUID
    var title: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(title: String, note: String = "") {
        self.id = UUID()
        self.title = title
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }
}
