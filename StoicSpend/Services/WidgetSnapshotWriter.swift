import Foundation

/// FR-21 — App 侧快照写入（主 App 目标专用；Widget 只读 WidgetSnapshotStore）
/// 数据口径与首页一致：控制比 = 可控(主动选择)/总额，样本 < 3 笔时不展示
enum WidgetSnapshotWriter {
    static func update(expenses: [Expense]) {
        // FR-31 统计口径：仅消费，退款负冲抵；收入/转账不进任何合计
        let stat = expenses.filter { $0.isStatistical }
        let total = stat.reduce(0.0) { $0 + $1.statAmount }
        let chosen = stat.filter { $0.isControllable }.reduce(0.0) { $0 + $1.statAmount }

        let calendar = Calendar.current
        let todayTotal = stat.filter { calendar.isDateInToday($0.date) }.reduce(0.0) { $0 + $1.statAmount }
        let weekTotal = stat
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
            .reduce(0.0) { $0 + $1.statAmount }

        let currency = CurrencyService.defaultCurrencyForCurrentLocale()
        let recent = Array(stat.sorted { $0.date > $1.date }.prefix(3)).map {
            // FR-31：备注为空时用类型标签兜底，退款显示负金额
            let note = $0.note.isEmpty ? ($0.flowTag ?? "") : $0.note
            return WidgetSnapshot.RecentEntry(emoji: $0.category.emoji, note: note, amount: $0.statAmount)
        }

        let snapshot = WidgetSnapshot(
            ratio: total > 0 && stat.count >= 3 ? chosen / total : nil,
            todayTotal: todayTotal,
            weekTotal: weekTotal,
            currencySymbol: CurrencyService.shared.symbol(for: currency),
            recent: recent,
            updatedAt: .now
        )
        WidgetSnapshotStore.save(snapshot)
    }
}
