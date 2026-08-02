import SwiftUI
import SwiftData

/// 控制圈 ViewModel — 计算"可控 vs 不可控"支出占比
@Observable
final class CircleViewModel {
    var controllableTotal: Double = 0
    var uncontrollableTotal: Double = 0
    var controllableRatio: Double = 0
    var expenses: [Expense] = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshWeek()
    }

    /// 刷新本周数据（免费版）
    func refreshWeek() {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now

        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= startOfWeek },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        expenses = (try? modelContext.fetch(descriptor)) ?? []
        calculate()
    }

    /// 刷新月度数据（付费版）
    func refreshMonth() {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now

        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= startOfMonth },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        expenses = (try? modelContext.fetch(descriptor)) ?? []
        calculate()
    }

    // MARK: - Private

    private func calculate() {
        controllableTotal = expenses.filter { $0.isControllable }.reduce(0) { $0 + $1.amount }
        uncontrollableTotal = expenses.filter { !$0.isControllable }.reduce(0) { $0 + $1.amount }
        let total = controllableTotal + uncontrollableTotal
        controllableRatio = total > 0 ? controllableTotal / total : 0
    }
}
