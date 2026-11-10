import Foundation

/// FR-17 常用组合 — 最近使用的（性质, 分类）组合，最多记 3 个，仅本地
/// 存储 key "recent.combos"（JSON 数组，最新在前，去重）
struct RecentCombo: Codable, Equatable, Hashable {
    let natureRaw: String
    let categoryRaw: String

    var nature: ExpenseNature? { ExpenseNature(rawValue: natureRaw) }
    var category: ExpenseCategory? { ExpenseCategory(rawValue: categoryRaw) }

    /// chip 展示文案：🍜 饮食（性质不进标签，点按仍会套用）
    var label: String {
        "\(category?.emoji ?? "◇") \(category?.localizedName ?? "")"
    }
}

enum RecentComboStore {
    static let key = "recent.combos"
    private static let maxCount = 3

    static func load() -> [RecentCombo] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let combos = try? JSONDecoder().decode([RecentCombo].self, from: data) else {
            return []
        }
        return combos
    }

    /// 保存时记录：去重后插到最前，超出 3 个截断
    static func record(nature: ExpenseNature, category: ExpenseCategory) {
        var combos = load()
        let new = RecentCombo(natureRaw: nature.rawValue, categoryRaw: category.rawValue)
        combos.removeAll { $0 == new }
        combos.insert(new, at: 0)
        if combos.count > maxCount {
            combos = Array(combos.prefix(maxCount))
        }
        if let data = try? JSONEncoder().encode(combos) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
