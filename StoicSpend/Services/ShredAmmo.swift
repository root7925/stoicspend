import Foundation

/// 消费粉碎机 — 9 类消费心理学机制弹药库（FR-08）
/// 降级路径：设备不支持本地 AI 时，从此库随机取 3 条不同机制
enum ShredAmmo {

    /// 弹药条目 — 部分模板含 {item}/{amount} 占位，由金额与品名个性化填充
    struct Line {
        let mechanism: String   // 机制名（仅内部区分，不展示给用户）
        let template: String
    }

    /// 已抽出的弹药 — 附机制名供 FR-27 偏好记录
    struct Drawn {
        let mechanism: String
        let text: String
    }

    /// 内部机制 key ↔ 中文机制名（AI 输出用中文名，本地库用 key）
    static let mechanismNames: [String: String] = [
        "anchoring": "锚定陷阱", "identity": "身份幻觉", "dopamine": "多巴胺结算",
        "scarcity": "限量话术", "opportunity": "机会成本", "discount": "折扣算术",
        "compound": "复利视角", "memory": "回忆测试", "delay": "延迟魔法"
    ]

    /// 中文名 → 内部 key（无法识别时返回原样）
    static func normalize(_ name: String) -> String {
        if mechanismNames[name] != nil { return name }
        return mechanismNames.first(where: { $0.value == name })?.key ?? name
    }

    static let all: [Line] = [
        // 锚定陷阱
        Line(mechanism: "anchoring", template: "「原价」是先抬价再打折的数字游戏。没有那个虚高原价，它就值那么多。"),
        Line(mechanism: "anchoring", template: "满减凑单让你盯着「省了多少」，没让你看「花了多少」。"),
        // 身份幻觉
        Line(mechanism: "identity", template: "买{item}不会让你变成另一种人，只会让钱包轻一点。"),
        Line(mechanism: "identity", template: "它承诺的是一种生活方式，交付的只是一件东西。"),
        // 多巴胺结算
        Line(mechanism: "dopamine", template: "你想要的是按下购买键的那一秒，不是{item}本身。"),
        Line(mechanism: "dopamine", template: "拆快递的快乐三天就没了，¥{amount}可是实实在在花出去的。"),
        // 限量话术
        Line(mechanism: "scarcity", template: "「最后一件」「今晚截止」都是写好的台词。错过它，明天太阳照常升起。"),
        Line(mechanism: "scarcity", template: "制造稀缺是最高效的催单术。真正的需要从不催你。"),
        // 机会成本
        Line(mechanism: "opportunity", template: "__OPPORTUNITY__"),
        Line(mechanism: "opportunity", template: "¥{amount}也可以是一顿好饭、一本书，或什么都不做的从容。"),
        // 折扣算术
        Line(mechanism: "discount", template: "省 50% 的前提是先花 100%。不买，省下的是全部。"),
        Line(mechanism: "discount", template: "「回本」的算法里没有一项是「你真的需要它」。"),
        // 复利视角
        Line(mechanism: "compound", template: "__COMPOUND__"),
        Line(mechanism: "compound", template: "现在的你替未来的你签了单。未来的你同意了吗？"),
        // 回忆测试
        Line(mechanism: "memory", template: "想象一年后的今天：你记得买过{item}吗？会为没买而后悔吗？"),
        Line(mechanism: "memory", template: "多数购物在记忆里活不过一个月，账单比记忆诚实。"),
        // 延迟魔法
        Line(mechanism: "delay", template: "先放购物车 72 小时。三天后还想要，再回来找它——多数时候你不会回来。"),
        Line(mechanism: "delay", template: "把「现在就要」改成「明天再说」。冲动最怕过夜。"),
    ]

    // MARK: - FR-27 机制偏好与每周配额（全部本地 UserDefaults）

    /// 用户点选「最戳」的机制，下次生成优先
    static var preferredMechanism: String? {
        get { UserDefaults.standard.string(forKey: "shred.pref.mechanism") }
        set { UserDefaults.standard.set(newValue, forKey: "shred.pref.mechanism") }
    }

    static func recordPreference(_ name: String) {
        preferredMechanism = normalize(name)
    }

    private static func usageKey(_ mechanism: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-'W'ww"
        return "shred.mech.\(f.string(from: .now)).\(mechanism)"
    }

    /// 本周该机制已出现次数（每周同机制 ≤ 2 次）
    static func weeklyUsage(_ mechanism: String) -> Int {
        UserDefaults.standard.integer(forKey: usageKey(normalize(mechanism)))
    }

    /// 本轮展示后按机制计数（供每周配额判断）
    static func noteShown(_ mechanisms: [String]) {
        let d = UserDefaults.standard
        for raw in mechanisms {
            let m = normalize(raw)
            d.set(d.integer(forKey: usageKey(m)) + 1, forKey: usageKey(m))
        }
    }

    /// 随机取 3 条不同机制的弹药；偏好机制优先占一席，达每周配额的机制跳过
    static func drawThree(itemName: String, amount: Double) -> [Drawn] {
        var pools: [String: [Line]] = [:]
        for line in all { pools[line.mechanism, default: []].append(line) }
        // 每周同机制 ≤ 2 次：已达上限的机制本轮不再出现
        let available = pools.filter { weeklyUsage($0.key) < 2 }
        let source = available.isEmpty ? pools : available
        // 偏好机制优先占一席（若仍可用）
        var chosen: [String] = []
        if let pref = preferredMechanism, source[pref] != nil {
            chosen.append(pref)
        }
        for key in source.keys.shuffled() where chosen.count < 3 && !chosen.contains(key) {
            chosen.append(key)
        }
        return chosen.prefix(3).compactMap { key in
            guard let line = source[key]?.randomElement() else { return nil }
            return Drawn(mechanism: key, text: render(line.template, itemName: itemName, amount: amount))
        }
    }

    /// 模板渲染 — 机会成本/复利按金额动态换算
    static func render(_ template: String, itemName: String, amount: Double) -> String {
        let amountText = String(format: "%.0f", amount)
        let item = itemName.isEmpty ? "它" : itemName
        switch template {
        case "__OPPORTUNITY__":
            let meals = Int(amount / 30)
            let rides = Int(amount / 15)
            return "¥\(amountText) ≈ \(meals)顿午饭 或 \(rides)次打车。换成这些，哪个更实在？"
        case "__COMPOUND__":
            let futureValue = amount * pow(1.05, 10)
            return "¥\(amountText)放 10 年按年化 5% ≈ ¥\(String(format: "%.0f", futureValue))。现在花掉，是向未来的你借钱。"
        default:
            return template
                .replacingOccurrences(of: "{item}", with: item)
                .replacingOccurrences(of: "{amount}", with: amountText)
        }
    }
}
