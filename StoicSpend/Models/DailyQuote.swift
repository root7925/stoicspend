import Foundation
import SwiftData

/// 每日语录 — 原创斯多葛式短句，打开 App 时展示
@Model
final class DailyQuote {
    var id: UUID
    var date: Date
    var text: String
    var isOriginal: Bool  // 标记为原创改写，非逐字引用

    init(date: Date, text: String, isOriginal: Bool = true) {
        self.id = UUID()
        self.date = date
        self.text = text
        self.isOriginal = isOriginal
    }
}
