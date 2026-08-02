import SwiftUI
import SwiftData

/// 记账 ViewModel — 管理支出数据的创建、查询、统计
@Observable
final class ExpenseViewModel {
    var todayExpenses: [Expense] = []
    var weekExpenses: [Expense] = []
    var monthExpenses: [Expense] = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    /// 刷新数据
    func refresh() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let startOfMonth = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now

        todayExpenses = fetch(filter: startOfDay...)
        weekExpenses = fetch(filter: startOfWeek...)
        monthExpenses = fetch(filter: startOfMonth...)
    }

    /// 添加支出
    @discardableResult
    func addExpense(
        amount: Double,
        nature: ExpenseNature? = nil,
        values: [ValueTag] = [],
        emotionalTrigger: String? = nil,
        note: String = ""
    ) -> Expense {
        let expense = Expense(
            amount: amount,
            note: note,
            nature: nature,
            values: values,
            emotionalTrigger: emotionalTrigger
        )
        modelContext.insert(expense)
        try? modelContext.save()
        refresh()
        return expense
    }

    /// 删除支出
    func deleteExpense(_ expense: Expense) {
        modelContext.delete(expense)
        try? modelContext.save()
        refresh()
    }

    // MARK: - 统计

    var todayTotal: Double {
        todayExpenses.reduce(0) { $0 + $1.amount }
    }

    var weekTotal: Double {
        weekExpenses.reduce(0) { $0 + $1.amount }
    }

    var weekControllableTotal: Double {
        weekExpenses.filter { $0.isControllable }.reduce(0) { $0 + $1.amount }
    }

    var weekControllableRatio: Double {
        weekTotal > 0 ? weekControllableTotal / weekTotal : 0
    }

    // MARK: - Private

    private func fetch(filter: PartialRangeFrom<Date>) -> [Expense] {
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= filter.lowerBound },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
