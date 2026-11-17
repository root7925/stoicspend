import Foundation

/// FR-29 自定义分类 — 用户在设置里自建的类别（最多 6 个，内置 9 类锁定不可动）
/// 存 UserDefaults JSON（与 RazorStore 同模式）；Watch/Share target 只读内置 9 类，不受影响
struct CustomCategory: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String      // ≤20 字，用户自建不翻译
    var emoji: String
}

/// 纯 Foundation 实现（UserDefaults 线程安全），不加 @MainActor——
/// Expense 模型扩展需在任意上下文调用 storageKey/find
enum CategoryStore {
    static let storageKey = "custom.categories"
    static let maxCount = 6

    /// 预置 emoji 池（覆盖常见消费场景，够用克制）
    static let emojiPool: [String] = [
        "🐱", "🐶", "🎮", "🎧", "🎸", "⚽️", "🏀", "🚴",
        "☕️", "🍺", "🧋", "🍰", "🥡", "🛒", "💊", "🏥",
        "🚗", "⛽️", "🅿️", "🚌", "🎓", "📝", "💻", "🖨",
        "💅", "✂️", "🧴", "👕", "👓", "💍", "🎁", "🧧",
        "📖", "✍️", "🎬", "📷", "🏕", "🎡", "🛠", "🪴",
        "👶", "🧓", "🤝", "🫶", "💰", "📊", "🔁", "📦"
    ]

    static func load() -> [CustomCategory] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([CustomCategory].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [CustomCategory]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    @discardableResult
    static func add(name: String, emoji: String) -> [CustomCategory] {
        var items = load()
        guard items.count < maxCount else { return items }
        let trimmed = String(name.prefix(20)).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        items.append(CustomCategory(id: UUID(), name: trimmed, emoji: emoji))
        save(items)
        return items
    }

    @discardableResult
    static func remove(id: UUID) -> [CustomCategory] {
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
        return items
    }

    static func find(id: UUID) -> CustomCategory? {
        load().first { $0.id == id }
    }

    /// 账目关联自定义类别时存的 key（"custom:<uuid>"，与内置 rawValue 同槽位使用）
    static func storageKey(for id: UUID) -> String { "custom:\(id.uuidString)" }
    static func uuid(fromKey key: String) -> UUID? {
        guard key.hasPrefix("custom:") else { return nil }
        return UUID(uuidString: String(key.dropFirst(7)))
    }

    // MARK: - 快记宫格显示顺序（长按拖动重排）

    static let orderKey = "category.order"

    /// 宫格 key 顺序：持久化顺序优先，失效 key 过滤，缺失 key 追加（内置在前、自定义在后）
    static func orderedKeys() -> [String] {
        let saved = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        var keys = saved.filter {
            ExpenseCategory(rawValue: $0) != nil
                || (uuid(fromKey: $0).flatMap { find(id: $0) } != nil)
        }
        let all = ExpenseCategory.allCases.map(\.rawValue) + load().map { storageKey(for: $0.id) }
        for k in all where !keys.contains(k) { keys.append(k) }
        return keys
    }

    static func saveOrder(_ keys: [String]) {
        UserDefaults.standard.set(keys, forKey: orderKey)
    }
}

