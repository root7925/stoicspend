import Foundation

/// FR-21 小组件快照 — App Group UserDefaults 传递（不动 SwiftData 容器，避免数据迁移）
/// App 侧写入（WidgetSnapshotWriter），Widget 扩展侧只读
struct WidgetSnapshot: Codable {
    struct RecentEntry: Codable, Equatable, Hashable {
        var emoji: String
        var note: String
        var amount: Double
    }

    var ratio: Double?            // 控制比（可选，样本不足为 nil）
    var todayTotal: Double
    var weekTotal: Double
    var currencySymbol: String
    var recent: [RecentEntry]     // 最近 3 笔
    var updatedAt: Date
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.zhenglin.stoicspend"
    static let key = "widget.snapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let d = defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        d.set(data, forKey: key)
    }

    static func load() -> WidgetSnapshot? {
        guard let d = defaults, let data = d.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
