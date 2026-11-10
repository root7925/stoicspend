import SwiftUI
import SwiftData

/// 晚间回顾 — 完全可选的 10 秒练习（FR-05）
/// 当天一笔消费 → ✓ 会再做同样选择 / △ 会重新考虑 → 30 天热力条
struct EveningReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    private var calendar: Calendar { Calendar.current }

    /// 今天已回顾的记录（重复进入直接显示历史）
    private var todayReviewed: Expense? {
        expenses.first { calendar.isDateInToday($0.date) && $0.review != nil }
    }

    /// 今天待回顾的一笔（取最近一笔未回顾的）
    private var todayPending: Expense? {
        expenses.first { calendar.isDateInToday($0.date) && $0.review == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Text("←")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(DesignTokens.ash)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)

            ScrollView(showsIndicators: false) {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    if let reviewed = todayReviewed {
                        historySection(reviewed)
                    } else if let pending = todayPending {
                        reviewSection(pending)
                    } else {
                        restSection
                    }
                    heatSection
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.xl)
            }
        }
        .background(DesignTokens.paper)
    }

    // MARK: - 待回顾

    private func reviewSection(_ expense: Expense) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("今天这笔")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(expense.category.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.category.localizedName)
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Text(expense.formatted(currency: CurrencyService.shared.currentCurrency(in: modelContext)))
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                Spacer()
            }
            .padding(16)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

            VStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    mark(.affirm)
                } label: {
                    Text("✓ 会再做同样选择")
                        .sansBody(16, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(theme.current.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }

                Button {
                    mark(.reconsider)
                } label: {
                    Text("△ 会重新考虑")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DesignTokens.gold.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
            }
        }
    }

    // MARK: - 已回顾 / 无记录

    private func historySection(_ expense: Expense) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text(expense.review == .affirm ? "✓ 今天已回顾：会再做同样选择" : "△ 今天已回顾：会重新考虑")
                .sansBody(15, weight: .medium)
                .foregroundStyle(expense.review == .affirm ? theme.current.accentColor : DesignTokens.gold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("每天一次，明天见")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var restSection: some View {
        Text("今天没有记录，休息一天")
            .sansBody(15)
            .foregroundStyle(DesignTokens.ash)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - 30 天热力条

    private var heatSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("过去 30 天")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)

            let reviewed = reviewedByDay()
            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: -29 + offset, to: calendar.startOfDay(for: .now))!
                    let result = reviewed[day]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(result))
                        .frame(height: 26)
                }
            }

            if reviewed.isEmpty {
                Text("还没有回顾记录")
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.ash)
            } else {
                let affirm = reviewed.values.filter { $0 == .affirm }.count
                let reconsider = reviewed.values.filter { $0 == .reconsider }.count
                Text("✓ 会再做 ×\(affirm)　△ 会重想 ×\(reconsider)")
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.ash)
            }
        }
    }

    private func heatColor(_ result: ReviewResult?) -> Color {
        switch result {
        case .affirm: return theme.current.accentColor
        case .reconsider: return DesignTokens.gold
        case nil: return DesignTokens.stoneDim
        }
    }

    // MARK: - 逻辑

    private func reviewedByDay() -> [Date: ReviewResult] {
        var map: [Date: ReviewResult] = [:]
        for e in expenses {
            if let r = e.review {
                map[calendar.startOfDay(for: e.date)] = r
            }
        }
        return map
    }

    private func mark(_ result: ReviewResult) {
        guard let pending = todayPending else { return }
        pending.review = result
        try? modelContext.save()
    }
}
