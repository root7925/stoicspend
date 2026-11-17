import Foundation

/// FR-32 分类纠错记忆 — 商家/备注关键词 → 分类
/// 用户在导入预览批量改分类时写入；下次导入/快记自动套用；设置页可查看删除（不做黑盒）
struct CategoryRule: Codable, Identifiable, Equatable {
    let id: UUID
    var keyword: String      // 商家或备注关键词（≤12 字，用户原文不翻译）
    var categoryKey: String  // 内置 rawValue 或 "custom:<uuid>"
}

/// 纯 Foundation 实现（UserDefaults JSON），Shared 可编译入扩展 target
enum CategoryRuleStore {
    static let storageKey = "category.rules"
    static let maxCount = 50

    static func load() -> [CategoryRule] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([CategoryRule].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [CategoryRule]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    @discardableResult
    static func add(keyword: String, categoryKey: String) -> [CategoryRule] {
        let trimmed = String(keyword.trimmingCharacters(in: .whitespaces).prefix(12))
        guard !trimmed.isEmpty else { return load() }
        var items = load()
        // 同关键词覆盖旧规则
        items.removeAll { $0.keyword == trimmed }
        if items.count >= maxCount { items.removeFirst() }   // 满员挤掉最旧的
        items.append(CategoryRule(id: UUID(), keyword: trimmed, categoryKey: categoryKey))
        save(items)
        return items
    }

    @discardableResult
    static func remove(id: UUID) -> [CategoryRule] {
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
        return items
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// 命中规则：备注/商家包含关键词；多个命中取最长关键词（更具体）
    static func match(note: String) -> CategoryRule? {
        guard !note.isEmpty else { return nil }
        return load()
            .filter { note.contains($0.keyword) }
            .max { $0.keyword.count < $1.keyword.count }
    }

    /// 规则的分类显示名（内置本地化 / 自定义原文；规则指向已删除类别时为 nil）
    static func displayName(for rule: CategoryRule) -> String? {
        if let raw = ExpenseCategory(rawValue: rule.categoryKey) {
            return raw.localizedName
        }
        if let id = CategoryStore.uuid(fromKey: rule.categoryKey), let cat = CategoryStore.find(id: id) {
            return "\(cat.emoji) \(cat.name)"
        }
        return nil
    }
}
