import SwiftUI
import SwiftData

/// 历史记录页 — 按周/月/年分组的支出汇总与明细（免费功能）
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    @State private var granularity: Granularity = .month

    private var currency: String {
        CurrencyService.shared.currentCurrency(in: modelContext)
    }

    /// 按当前维度分组
    private var groups: [(key: Date, value: [Expense])] {
        let calendar = Calendar.current
        let component: Calendar.Component = {
            switch granularity {
            case .week:  return .weekOfYear
            case .month: return .month
            case .year:  return .year
            }
        }()
        let grouped = Dictionary(grouping: allExpenses) { expense in
            calendar.dateInterval(of: component, for: expense.date)!.start
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private func groupTitle(_ date: Date) -> String {
        switch granularity {
        case .week:
            let calendar = Calendar.current
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(interval.end.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return date.formatted(.dateTime.year().month(.wide))
        case .year:
            return date.formatted(.dateTime.year())
        }
    }

    private func entryDateLabel(_ date: Date) -> String {
        switch granularity {
        case .week:
            return date.formatted(.dateTime.weekday(.wide))
        case .month:
            return date.formatted(.dateTime.day().weekday(.short))
        case .year:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func total(_ expenses: [Expense]) -> Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    private func controllableRatio(_ expenses: [Expense]) -> Double {
        guard !expenses.isEmpty else { return 0 }
        let controllable = expenses.filter { $0.isControllable }.reduce(0.0) { $0 + $1.amount }
        let total = expenses.reduce(0.0) { $0 + $1.amount }
        return total > 0 ? controllable / total : 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // 维度切换
                Picker("Granularity", selection: $granularity) {
                    Text("Week").tag(Granularity.week)
                    Text("Month").tag(Granularity.month)
                    Text("Year").tag(Granularity.year)
                }
                .pickerStyle(.segmented)

                if allExpenses.isEmpty {
                    Text("No expenses recorded yet.")
                        .sansBody(15)
                        .foregroundStyle(DesignTokens.ash)
                        .padding(.vertical, DesignTokens.Spacing.xxl)
                } else {
                    ForEach(groups, id: \.key) { group in
                        groupSection(title: groupTitle(group.key),
                                     expenses: group.value)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .background(DesignTokens.paper)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mock") {
                    insertMockData()
                }
            }
        }
        #endif
    }

    // MARK: - 分组卡片

    private func groupSection(title: String, expenses: [Expense]) -> some View {
        let groupTotal = total(expenses)
        let ratio = controllableRatio(expenses)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(title)
                    .sansBody(15, weight: .semibold)
                    .foregroundStyle(DesignTokens.ink)
                Spacer()
                Text(CurrencyService.shared.format(groupTotal, currency: currency))
                    .monoData(15, weight: .semibold)
                    .foregroundStyle(DesignTokens.ink)
            }

            // 可控占比条
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(DesignTokens.stoneDim)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DesignTokens.verdigris)
                            .frame(width: geo.size.width * ratio)
                    }
                    .frame(height: 6)
            }
            .frame(height: 6)

            Text("\(Int(ratio * 100))% in control · \(expenses.count) entries")
                .sansBody(12)
                .foregroundStyle(DesignTokens.ash)

            // 组内明细
            ForEach(expenses) { expense in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if expense.note.isEmpty {
                                Text("Expense")
                            } else {
                                Text(verbatim: expense.note)
                            }
                        }
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ink)
                        Text(entryDateLabel(expense.date))
                            .sansBody(11)
                            .foregroundStyle(DesignTokens.ash)
                    }
                    Spacer()
                    Text(expense.formatted(currency: currency))
                        .monoData(14)
                        .foregroundStyle(DesignTokens.ink)
                }
                .padding(.vertical, DesignTokens.Spacing.xs)

                if expense.id != expenses.last?.id {
                    Divider()
                        .foregroundStyle(DesignTokens.stoneDim)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Mock 数据

    /// DEBUG：插入跨越多周/多月/多年的测试数据
    private func insertMockData() {
        let calendar = Calendar.current
        let now = Date.now

        // 样本模板：(距今天数, 金额, note, nature)
        let samples: [(Int, Double, String, ExpenseNature)] = [
            // 本周
            (0, 12.5, "Coffee", .chosen),
            (1, 45.0, "Groceries", .necessity),
            (2, 28.0, "Book", .chosen),
            (3, 15.0, "Snack", .impulse),
            // 上周
            (8, 60.0, "Fuel", .necessity),
            (9, 22.0, "Movie ticket", .impulse),
            (10, 35.0, "Lunch out", .chosen),
            // 上月
            (35, 120.0, "Electricity bill", .necessity),
            (38, 9.9, "App subscription", .chosen),
            (42, 55.0, "Gift", .chosen),
            // 去年
            (400, 300.0, "Flight ticket", .chosen),
            (405, 80.0, "Hotel", .necessity),
            (410, 25.0, "Souvenir", .impulse),
        ]

        for s in samples {
            if let date = calendar.date(byAdding: .day, value: -s.0, to: now) {
                let expense = Expense(
                    amount: s.1,
                    date: date,
                    note: s.2,
                    nature: s.3,
                    values: [],
                    emotionalTrigger: nil
                )
                modelContext.insert(expense)
            }
        }
        try? modelContext.save()
    }
}

// MARK: - 维度

enum Granularity: Hashable {
    case week
    case month
    case year
}
