import AppIntents
import SwiftData
import Foundation

extension Notification.Name {
    /// FR-13 — Widget/控制中心深链直达快记页
    static let widgetOpenQuickAdd = Notification.Name("widget.openQuickAdd")
}

// MARK: - FR-14 自然语言解析（纯本地规则，无网络）

/// 「记一笔 35 咖啡」→ 金额 + 分类 + 性质
/// 分类按备注关键词匹配九分法；未命中沿用上次分类；性质默认上次选择
enum NaturalExpenseParser {
    /// 关键词 → 分类（顺序即优先级：travel 先于 transport，避免「机票」误入交通）
    private static let keywordMap: [(ExpenseCategory, [String])] = [
        (.travel,   ["旅行", "酒店", "民宿", "机票", "火车票", "景点", "门票", "签证"]),
        (.food,     ["咖啡", "餐", "饭", "面", "奶茶", "外卖", "食", "早点", "早餐", "午餐", "晚餐", "夜宵", "菜", "酒", "茶", "果", "零食"]),
        (.beauty,   ["化妆", "美", "发", "剪", "护肤", "面膜", "指甲", "香", "口红"]),
        (.transport,["打车", "地铁", "公交", "加油", "停车", "滴滴", "车费", "骑行", "充电宝"]),
        (.family,   ["宠物", "猫粮", "狗粮", "猫", "狗", "妈", "爸", "娃", "孩子", "玩具", "礼"]),
        (.housing,  ["房租", "水费", "电费", "燃气", "物业", "网费", "房贷"]),
        (.gadget,   ["手机", "电脑", "耳机", "数码", "键盘", "鼠标", "屏幕", "相机", "平板", "配件"]),
        (.learning, ["书", "课程", "学习", "学费", "知识", "考试", "会员", "专栏"]),
    ]

    static func parseCategory(from text: String) -> ExpenseCategory? {
        guard !text.isEmpty else { return nil }
        for (category, keywords) in keywordMap {
            if keywords.contains(where: { text.contains($0) }) {
                return category
            }
        }
        return nil
    }

    /// 解析「35 咖啡」「咖啡 35」混合文本中的金额（数字部分）
    static func parseAmount(from text: String) -> Double? {
        text.split(whereSeparator: { !"0123456789.".contains($0) })
            .compactMap { Double($0) }
            .first
    }

    // MARK: FR-26 语音文本金额解析（阿拉伯数字 + 中文数字口语）

    /// 「花了三十五块五」「打车一百二」→ 金额；阿拉伯数字优先，其次中文数字
    static func parseVoiceAmount(from text: String) -> Double? {
        if let arabic = parseAmount(from: text) { return arabic }

        let charset = Set("零一二两三四五六七八九十百千万点块元毛角")
        var cur: [Character] = []
        var best: Double?

        func flush() {
            guard !cur.isEmpty else { return }
            let s = String(cur)
            cur = []
            var value: Double?
            if let r = s.range(of: "块") ?? s.range(of: "元") {
                // 「三十五块五」= 35 + 5/10
                if let main = cnNumber(String(s[..<r.lowerBound])) {
                    let tailStr = String(s[r.upperBound...])
                    let tail = tailStr.isEmpty ? 0 : (cnNumber(tailStr).map { $0 >= 10 ? $0 : $0 / 10 } ?? 0)
                    value = main + tail
                }
            } else if s.contains("点") {
                let parts = s.split(separator: "点")
                let intPart = cnNumber(String(parts.first ?? "")) ?? 0
                if parts.count > 1 {
                    let fracCount = Double(String(parts[1]).count)
                    value = intPart + (cnNumber(String(parts[1])) ?? 0) / pow(10, fracCount)
                } else {
                    value = intPart
                }
            } else {
                value = cnNumber(s)
            }
            if let v = value, v > 0, best == nil { best = v }
        }

        for ch in text {
            if charset.contains(ch) {
                cur.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return best
    }

    /// 纯中文数字转数值（「三十五」35 / 「一百二十」120 / 「十万」100000）
    private static func cnNumber(_ s: String) -> Double? {
        let digitMap: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let unitMap: [Character: Double] = ["十": 10, "百": 100, "千": 1000, "万": 10000]
        var total = 0.0
        var section = 0.0
        var num = 0
        var hasNum = false
        for ch in s {
            if let d = digitMap[ch] {
                num = num * 10 + d
                hasNum = true
            } else if let u = unitMap[ch] {
                if u >= 10000 {
                    let base = section + Double(num)
                    total += (base == 0 && !hasNum ? 1 : base) * u
                    section = 0
                } else {
                    if num == 0 && !hasNum { num = 1 }   // 「十」=10、「十五」=15
                    section += Double(num) * u
                }
                num = 0
                hasNum = false
            } else {
                return nil
            }
        }
        let result = total + section + Double(num)
        return result > 0 ? result : nil
    }
}

// MARK: - App Intent（Siri / 快捷指令 / Spotlight）

struct QuickAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var description: IntentDescription = "用一句话记下这笔钱，例如「记一笔 35 咖啡」"
    static var openAppWhenRun = false

    @Parameter(title: "金额", requestValueDialog: "这笔花了多少？")
    var amount: Double

    @Parameter(title: "备注", default: "")
    var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0, amount <= 999_999 else {
            return .result(dialog: "金额需要大于 0")
        }

        let category = NaturalExpenseParser.parseCategory(from: note)
            ?? ExpenseCategory(rawValue: UserDefaults.standard.string(forKey: "lastCategoryRaw") ?? "")
            ?? .food
        let nature = ExpenseNature(rawValue: UserDefaults.standard.string(forKey: "lastNatureRaw") ?? "")
            ?? .chosen

        // FR-14 — 保存前确认（Siri 卡片展示解析字段；上下文不支持确认 UI 时直接保存）
        do {
            try await requestConfirmation(
                conditions: [],
                actionName: .continue,
                dialog: IntentDialog("¥\(String(format: "%.2f", amount)) · \(category.localizedName) · \(nature == .chosen ? "主动选择" : nature == .impulse ? "冲动" : "必须")")
            )
        } catch { /* 环境无确认 UI（如自动化），继续保存 */ }

        // 写入与主 App 相同的 SwiftData 容器（本地，无网络）
        let context = ModelContext(ModelContainerSetup.shared)
        let expense = Expense(amount: amount, note: note, nature: nature, category: category)
        context.insert(expense)
        try context.save()

        // FR-16 撤销通道 — 回到 App 时底部浮出「已记下 · 撤销」
        UserDefaults.standard.set(expense.id.uuidString, forKey: "pendingUndoID")
        RecentComboStore.record(nature: nature, category: category)
        NotificationCenter.default.post(name: .quickAddSaved, object: nil)

        return .result(dialog: "已记下 ¥\(String(format: "%.2f", amount)) · \(category.localizedName) · \(nature == .chosen ? "主动选择" : nature == .impulse ? "冲动" : "必须")")
    }
}

struct StoicSpendShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddExpenseIntent(),
            phrases: ["\(.applicationName)记一笔"],
            shortTitle: "记一笔",
            systemImageName: "plus.circle"
        )
    }
}
