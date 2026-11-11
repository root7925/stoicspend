import Foundation

/// FR-24 Watch 快记 — 经 WatchConnectivity 传输的载荷（Watch 与 iPhone 共享）
/// Watch 端不独立存储；iPhone 收到后写入同一 SwiftData 库
struct WatchCapture: Codable, Equatable {
    let amount: Double
    let natureRaw: String
    let categoryRaw: String
    let date: Date

    var nature: ExpenseNature? { ExpenseNature(rawValue: natureRaw) }
    var category: ExpenseCategory? { ExpenseCategory(rawValue: categoryRaw) }

    /// 金额有效性：> 0（0 元占位不落库）
    var isValid: Bool { amount > 0 }

    /// 编码为传输用 JSON 数据
    var encodedData: Data? {
        try? JSONEncoder().encode(self)
    }

    /// 从消息字典解码（键为 WatchSyncKeys.messageKey）
    static func decode(from message: [String: Any]) -> WatchCapture? {
        guard let data = message[WatchSyncKeys.messageKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCapture.self, from: data)
    }
}

/// WatchConnectivity 传输键名（两端共享）
enum WatchSyncKeys {
    static let messageKey = "watchCapture"
    static let recentCombosKey = "recentCombos"
}
