import SwiftUI
import SwiftData

/// 页面 4 — The Circle 控制圈仪表盘
/// 大型环形图显示"可控 vs 不可控"支出占比
/// 免费版仅本周数据，月度/年度趋势对比锁定为付费功能
struct CircleDashboardView: View {
    @Query private var weekExpenses: [Expense]
    @Environment(\.modelContext) private var modelContext

    @State private var showPaywall = false
    @State private var showResilience = false

    init() {
        let calendar = Calendar.current
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: .now)!
        let weekPredicate = #Predicate<Expense> { $0.date >= weekInterval.start && $0.date < weekInterval.end }
        _weekExpenses = Query(
            filter: weekPredicate,
            sort: \Expense.date, order: .reverse
        )
    }

    private var controllableTotal: Double {
        weekExpenses.filter { $0.isControllable }.reduce(0) { $0 + $1.amount }
    }

    private var uncontrollableTotal: Double {
        weekExpenses.filter { !$0.isControllable }.reduce(0) { $0 + $1.amount }
    }

    private var weekTotal: Double {
        weekExpenses.reduce(0) { $0 + $1.amount }
    }

    private var controllableRatio: Double {
        weekTotal > 0 ? controllableTotal / weekTotal : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    // 大型控制环
                    ringSection

                    // 可控 vs 不可控明细
                    breakdownSection

                    // 付费锁定区域
                    lockedTrendsCard

                    // 财务韧性模拟入口（斯多葛"预先设想负面情境"）
                    resilienceEntry

                    // 本周支出列表
                    expenseListSection
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.md)
            }
            .background(DesignTokens.paper)
            .navigationTitle("The Circle")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showResilience) {
            ResilienceView()
        }
    }

    // MARK: - 子视图

    private var ringSection: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ControlRing(
                progress: controllableRatio,
                size: DesignTokens.ControlRing.dashboardSize
            )

            Text("This Week")
                .sansBody(14, weight: .medium)
                .foregroundStyle(DesignTokens.ash)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xl)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var breakdownSection: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 可控
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Circle()
                        .fill(DesignTokens.verdigris)
                        .frame(width: 10, height: 10)
                    Text("In Control")
                        .sansBody(14, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                }
                Text(CurrencyService.shared.format(controllableTotal, currency: CurrencyService.shared.currentCurrency(in: modelContext)))
                    .serifTitle(22, weight: .bold)
                    .foregroundStyle(DesignTokens.ink)
                Text("\(Int(controllableRatio * 100))%")
                    .monoData(13)
                    .foregroundStyle(DesignTokens.verdigris)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 60)

            // 不可控
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Circle()
                        .fill(DesignTokens.stoneDim)
                        .frame(width: 10, height: 10)
                    Text("Beyond Control")
                        .sansBody(14, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                }
                Text(CurrencyService.shared.format(uncontrollableTotal, currency: CurrencyService.shared.currentCurrency(in: modelContext)))
                    .serifTitle(22, weight: .bold)
                    .foregroundStyle(DesignTokens.ink)
                Text("\(Int((1 - controllableRatio) * 100))%")
                    .monoData(13)
                    .foregroundStyle(DesignTokens.ash)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var lockedTrendsCard: some View {
        Button {
            showPaywall = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack {
                        Image(systemName: "chart.bar")
                            .foregroundStyle(DesignTokens.rust)
                        Text("Trends & History")
                            .sansBody(16, weight: .semibold)
                            .foregroundStyle(DesignTokens.ink)
                    }
                    Text("Monthly and yearly comparisons")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }

                Spacer()

                Image(systemName: "lock")
                    .foregroundStyle(DesignTokens.rust)
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    /// 财务韧性模拟入口卡 — 斯多葛"预先设想负面情境"（Premeditatio Malorum）
    private var resilienceEntry: some View {
        Button {
            showResilience = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack {
                        Image(systemName: "shield")
                            .foregroundStyle(DesignTokens.verdigris)
                        Text("Resilience")
                            .sansBody(16, weight: .semibold)
                            .foregroundStyle(DesignTokens.ink)
                    }
                    Text("Simulate income disruption")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(DesignTokens.ash)
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    private var expenseListSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("This Week's Expenses")
                .sansBody(14, weight: .semibold)
                .foregroundStyle(DesignTokens.ash)

            if weekExpenses.isEmpty {
                Text("No expenses recorded this week.")
                    .sansBody(15)
                    .foregroundStyle(DesignTokens.ash)
                    .padding(.vertical, DesignTokens.Spacing.lg)
            } else {
                ForEach(weekExpenses) { expense in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Group {
                                if expense.note.isEmpty {
                                    Text("Expense")
                                } else {
                                    Text(verbatim: expense.note)
                                }
                            }
                            .sansBody(15)
                            .foregroundStyle(DesignTokens.ink)
                            if let nature = expense.nature {
                                Text(LocalizedStringKey(nature == .chosen ? "Chosen" : "Impulse"))
                                    .sansBody(12)
                                    .foregroundStyle(nature == .chosen ? DesignTokens.verdigris : DesignTokens.rust)
                            }
                        }
                        Spacer()
                        Text(expense.formatted(currency: CurrencyService.shared.currentCurrency(in: modelContext)))
                            .monoData(15)
                            .foregroundStyle(DesignTokens.ink)
                    }
                    .padding(.vertical, DesignTokens.Spacing.sm)

                    if expense.id != weekExpenses.last?.id {
                        Divider()
                            .foregroundStyle(DesignTokens.stoneDim)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }
}
