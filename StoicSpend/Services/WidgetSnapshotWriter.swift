import Foundation

/// FR-21 — App 侧快照写入（主 App 目标专用；Widget 只读 WidgetSnapshotStore）
/// 数据口径与首页一致：控制比 = 可控(主动选择)/总额，样本 < 3 笔时不展示
enum WidgetSnapshotWriter {
    static func update(expenses: [Expense]) {
        let total = expenses.reduce(0.0) { $0 + $1.amount }
        let chosen = expenses.filter { $0.isControllable }.reduce(0.0) { $0 + $1.amount }

        let calendar = Calendar.current
        let todayTotal = expenses.filter { calendar.isDateInToday($0.date) }.reduce(0.0) { $0 + $1.amount }
        let weekTotal = expenses
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
            .reduce(0.0) { $0 + $1.amount }

        let currency = CurrencyService.defaultCurrencyForCurrentLocale()
        let recent = Array(expenses.sorted { $0.date > $1.date }.prefix(3)).map {
            WidgetSnapshot.RecentEntry(emoji: $0.category.emoji, note: $0.note, amount: $0.amount)
        }

        let snapshot = WidgetSnapshot(
            ratio: total > 0 && expenses.count >= 3 ? chosen / total : nil,
            todayTotal: todayTotal,
            weekTotal: weekTotal,
            currencySymbol: CurrencyService.shared.symbol(for: currency),
            recent: recent,
            updatedAt: .now
        )
        WidgetSnapshotStore.save(snapshot)
    }
}
