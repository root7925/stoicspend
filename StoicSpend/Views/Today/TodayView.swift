import SwiftUI
import SwiftData

/// 页面 2 — Today 首页
/// 当日语录 + 记账主按钮 + 今日汇总卡片 + 本周控制圈预览
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var todayExpenses: [Expense]
    @Query private var weekExpenses: [Expense]

    @State private var showAddExpense = false
    @State private var showWeeklyReview = false

    init() {
        let calendar = Calendar.current
        let now = Date.now

        // 今天范围
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let todayPredicate = #Predicate<Expense> { $0.date >= startOfDay && $0.date < endOfDay }
        _todayExpenses = Query(
            filter: todayPredicate,
            sort: \Expense.date, order: .reverse
        )

        // 本周范围
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
        let weekPredicate = #Predicate<Expense> { $0.date >= weekInterval.start && $0.date < weekInterval.end }
        _weekExpenses = Query(
            filter: weekPredicate,
            sort: \Expense.date, order: .reverse
        )
    }

    private var todayTotal: Double {
        todayExpenses.reduce(0) { $0 + $1.amount }
    }

    private var weekControllableRatio: Double {
        guard !weekExpenses.isEmpty else { return 0 }
        let controllable = weekExpenses.filter { $0.isControllable }.reduce(0.0) { $0 + $1.amount }
        let total = weekExpenses.reduce(0.0) { $0 + $1.amount }
        return total > 0 ? controllable / total : 0
    }

    private var dailyQuote: StoicQuote {
        let quotes = StoicQuotes.all
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        return quotes[(dayOfYear - 1) % quotes.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    // 当日语录
                    quoteSection

                    // 本周记录连续性（7天圆点，无羞耻可视化，仅展示"我在"）
                    continuityDotsSection

                    // 记账主按钮
                    addExpenseButton

                    // 今日汇总
                    todaySummaryCard

                    // 本周控制圈预览
                    weeklyPreviewCard

                    // 周复盘入口
                    weeklyReviewEntry
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.md)
                .padding(.bottom, 30)
            }
            .background(DesignTokens.paper)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showAddExpense) {
            AddExpenseFlow()
        }
        .sheet(isPresented: $showWeeklyReview) {
            WeeklyReviewView()
        }
    }

    // MARK: - 子视图

    /// 返回本周7天（周一到周日或周日到周六，根据系统设置）
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let now = Date.now
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
        var days: [Date] = []
        var day = weekInterval.start
        while day < weekInterval.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    /// 判断某一天是否至少有1条记录
    private func hasRecord(on day: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return false }
        return weekExpenses.contains { $0.date >= startOfDay && $0.date < endOfDay }
    }

    /// 本周连续记录天数（从今天向前数，中断即停止 — 但不显示"streak"词，避免羞耻）
    private var consecutiveDaysCount: Int {
        let calendar = Calendar.current
        var count = 0
        var checkDay = calendar.startOfDay(for: .now)
        while hasRecord(on: checkDay) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prev
        }
        return count
    }

    private var continuityDotsSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .bottom) {
                Text("Present this week")
                    .sansBody(13, weight: .medium)
                    .foregroundStyle(DesignTokens.ash)
                Spacer()
                if consecutiveDaysCount > 0 {
                    Text("\(consecutiveDaysCount) days")
                        .monoData(12, weight: .semibold)
                        .foregroundStyle(DesignTokens.verdigris)
                }
            }
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    let isToday = Calendar.current.isDateInToday(day)
                    let hasRecord = hasRecord(on: day)
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        Circle()
                            .fill(hasRecord ? DesignTokens.bronze : DesignTokens.stoneDim.opacity(0.4))
                            .frame(width: isToday ? 14 : 10, height: isToday ? 14 : 10)
                            .overlay(
                                Circle()
                                    .stroke(isToday ? DesignTokens.ink : Color.clear, lineWidth: isToday ? 1.5 : 0)
                            )
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .sansBody(11)
                            .foregroundStyle(DesignTokens.ash)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var quoteSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            // 装饰性引号（细线，克制）
            Image(systemName: "quote.opening")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DesignTokens.bronze.opacity(0.6))

            Text(dailyQuote.text)
                .serifTitle(18, weight: .regular)
                .foregroundStyle(DesignTokens.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // 作者署名
            Text("— \(dailyQuote.author)")
                .sansBody(13, weight: .medium)
                .foregroundStyle(DesignTokens.ash)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var addExpenseButton: some View {
        Button {
            showAddExpense = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Record an Expense")
                    .sansBody(17, weight: .semibold)
            }
            .foregroundStyle(DesignTokens.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(DesignTokens.bronze)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
    }

    private var todaySummaryCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Today")
                .sansBody(13, weight: .medium)
                .foregroundStyle(DesignTokens.ash)

            HStack {
                Text(CurrencyService.shared.format(todayTotal, currency: CurrencyService.shared.currentCurrency(in: modelContext)))
                    .serifTitle(32, weight: .bold)
                    .foregroundStyle(DesignTokens.ink)
                Spacer()
                (Text(verbatim: "\(todayExpenses.count) ") + Text("entries"))
                    .monoData(14)
                    .foregroundStyle(DesignTokens.ash)
            }

            if !todayExpenses.isEmpty {
                Divider()
                    .foregroundStyle(DesignTokens.stoneDim)

                ForEach(todayExpenses.prefix(3)) { expense in
                    HStack {
                        if expense.isControllable {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(DesignTokens.verdigris)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(DesignTokens.ash)
                        }
                        Text(expense.note.isEmpty ? expense.formatted(currency: CurrencyService.shared.currentCurrency(in: modelContext)) : expense.note)
                            .sansBody(15)
                            .foregroundStyle(DesignTokens.ink)
                        Spacer()
                        Text(expense.formatted(currency: CurrencyService.shared.currentCurrency(in: modelContext)))
                            .monoData(14)
                            .foregroundStyle(DesignTokens.ink)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var weeklyPreviewCard: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ControlRingBadge(progress: weekControllableRatio)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("This Week")
                    .sansBody(13, weight: .medium)
                    .foregroundStyle(DesignTokens.ash)
                (Text(verbatim: "\(Int(weekControllableRatio * 100))% ") + Text("in control"))
                    .serifTitle(18, weight: .semibold)
                    .foregroundStyle(DesignTokens.ink)
                (Text(verbatim: "\(weekExpenses.count) ") + Text("expenses tracked"))
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)
            }

            Spacer()

            NavigationLink {
                CircleDashboardView()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(DesignTokens.ash)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var weeklyReviewEntry: some View {
        Button {
            showWeeklyReview = true
        } label: {
            HStack {
                Image(systemName: "book")
                    .foregroundStyle(DesignTokens.bronze)
                Text("Weekly Reflection")
                    .sansBody(15, weight: .medium)
                    .foregroundStyle(DesignTokens.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DesignTokens.ash)
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }
}

// MARK: - 斯多葛语录预置数据

struct StoicQuote {
    let text: String
    let author: String
}

enum StoicQuotes {
    static let all: [StoicQuote] = [
        StoicQuote(text: String(localized: "quote.1"), author: "Epictetus"),
        StoicQuote(text: String(localized: "quote.2"), author: "Marcus Aurelius"),
        StoicQuote(text: String(localized: "quote.3"), author: "Seneca"),
        StoicQuote(text: String(localized: "quote.4"), author: "Marcus Aurelius"),
        StoicQuote(text: String(localized: "quote.5"), author: "Epictetus"),
        StoicQuote(text: String(localized: "quote.6"), author: "Seneca"),
        StoicQuote(text: String(localized: "quote.7"), author: "Marcus Aurelius"),
        StoicQuote(text: String(localized: "quote.8"), author: "Epictetus"),
        StoicQuote(text: String(localized: "quote.9"), author: "Seneca"),
        StoicQuote(text: String(localized: "quote.10"), author: "Marcus Aurelius"),
    ]
}
