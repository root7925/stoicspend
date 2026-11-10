import Foundation

/// FR-19 疑似订阅 — 纯本地规则：同名同额 + 周期间隔的记录聚合
/// 周期：月（间隔 25–35 天）/ 周（间隔 6–8 天），≥2 次才构成订阅
struct SuspectedSubscription: Identifiable, Equatable {
    enum Period: String, Codable { case monthly, weekly }

    let id: String            // 签名 "note|amount|period"，同时作为取消标记 key
    let name: String
    let amount: Double
    let period: Period
    let dates: [Date]         // 最近一次在前
    let lastDate: Date

    /// 折算月金额（周订阅 × 52/12）
    var monthlyAmount: Double {
        period == .monthly ? amount : amount * 52.0 / 12.0
    }

    /// 下次预计扣款日
    var nextDate: Date? {
        let interval: TimeInterval = period == .monthly ? 30.5 * 86400 : 7 * 86400
        let candidate = lastDate.addingTimeInterval(interval)
        // 超过一个周期未扣，视为已停止，不再预计
        guard Date.now.timeIntervalSince(candidate) < interval else { return nil }
        return candidate
    }
}

enum SubscriptionService {
    private static let cancelledKey = "subscription.cancelled"
    static let guardAmountKey = "guard.amount"   // R-6 守住金额缓存（订阅取消部分）

    // MARK: - 识别

    static func detect(_ expenses: [Expense]) -> [SuspectedSubscription] {
        // 按备注非空分组；空备注不识别
        var groups: [String: [(Date, Double)]] = [:]
        for e in expenses where !e.note.isEmpty {
            groups[e.note, default: []].append((e.date, e.amount))
        }

        var result: [SuspectedSubscription] = []
        for (note, entries) in groups {
            let sorted = entries.sorted { $0.0 > $1.0 }   // 最新在前
            let amount = sorted[0].1
            guard Set(sorted.map { $0.1 }) == [amount], sorted.count >= 2 else { continue }

            let gaps = zip(sorted, sorted.dropFirst()).map { $0.0.timeIntervalSince($1.0) / 86400 }
            let monthly = gaps.allSatisfy { $0 >= 25 && $0 <= 35 }
            let weekly = gaps.allSatisfy { $0 >= 6 && $0 <= 8 }
            guard monthly || weekly else { continue }

            let period: SuspectedSubscription.Period = monthly ? .monthly : .weekly
            let id = "\(note)|\(amount)|\(period.rawValue)"
            result.append(SuspectedSubscription(
                id: id,
                name: note,
                amount: amount,
                period: period,
                dates: sorted.map { $0.0 },
                lastDate: sorted[0].0
            ))
        }
        return result.sorted { $0.lastDate > $1.lastDate }
    }

    // MARK: - 保留 / 取消标记

    static func cancelledIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: cancelledKey) ?? [])
    }

    /// 取消 → 计入守住金额（R-6）；保留/误判 → 移出
    static func markCancelled(_ id: String, monthlyAmount: Double) {
        var ids = cancelledIDs()
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: cancelledKey)
        syncGuardAmount(subs: nil)
    }

    static func unmarkCancelled(_ id: String) {
        var ids = cancelledIDs()
        ids.remove(id)
        UserDefaults.standard.set(Array(ids), forKey: cancelledKey)
        syncGuardAmount(subs: nil)
    }

    // MARK: - R-6 守住金额（唯一口径）
    // 守住 = 粉碎成功累计（shred.amount.yyyy-MM）+ 疑似订阅「取消」折算月额
    // （冷静清单剃掉未记录金额，不计入；口径详见 PRD R-6）

    static func guardAmount(from expenses: [Expense]) -> Double {
        let detected = detect(expenses)
        let cancelled = detected.filter { cancelledIDs().contains($0.id) }
        let subTotal = cancelled.reduce(0.0) { $0 + $1.monthlyAmount }
        UserDefaults.standard.set(subTotal, forKey: guardAmountKey)
        return subTotal + totalShredAmount()
    }

    /// 仅订阅部分（内部调用），支持外部传入已识别列表避免重复扫描
    static func syncGuardAmount(subs: [SuspectedSubscription]?) {
        _ = guardAmount(from: [])
    }

    /// 粉碎成功累计：扫描全部月份 shred.amount.* 键
    static func totalShredAmount() -> Double {
        let d = UserDefaults.standard
        var total = 0.0
        for (key, value) in d.dictionaryRepresentation() where key.hasPrefix("shred.amount.") {
            if let v = value as? Double { total += v }
        }
        return total
    }
}
