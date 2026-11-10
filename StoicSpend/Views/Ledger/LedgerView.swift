import SwiftUI
import SwiftData

/// 帐本 — 明细 / 分类 / 趋势三分区 + 月份穿梭（FR-03）
struct LedgerView: View {
    enum LedgerTab: String, CaseIterable {
        case detail = "明细"
        case category = "分类"
        case trend = "趋势"
    }

    enum NatureFilter: String, CaseIterable {
        case all = "全部"
        case chosen = "✓ 主动"
        case necessity = "· 必须"
        case impulse = "△ 冲动"

        var nature: ExpenseNature? {
            switch self {
            case .all: return nil
            case .chosen: return .chosen
            case .necessity: return .necessity
            case .impulse: return .impulse
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeManager
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var selectedSection: LedgerTab = .detail
    @State private var selectedMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var showMonthPanel = false
    @State private var natureFilter: NatureFilter = .all
    @State private var editingExpense: Expense?
    @State private var expandedCategory: ExpenseCategory?
    @State private var searchText = ""
    @State private var pendingDelete: Expense?
    @State private var subscriptionsExpanded = false

    private var calendar: Calendar { Calendar.current }
    private var currency: String { CurrencyService.shared.currentCurrency(in: modelContext) }

    // MARK: - 派生数据

    /// 所有有记录的月份（升序）
    private var recordedMonths: [Date] {
        let months = Set(expenses.map { calendar.monthStart($0.date) })
        return months.sorted()
    }

    /// 月份统计（笔数 + 合计），供全部月份面板使用
    private var monthStats: [Date: (count: Int, total: Double)] {
        var stats: [Date: (Int, Double)] = [:]
        for e in expenses {
            let m = calendar.monthStart(e.date)
            let old = stats[m] ?? (0, 0)
            stats[m] = (old.0 + 1, old.1 + e.amount)
        }
        return stats
    }

    /// 选中月份的记录
    private var monthExpenses: [Expense] {
        expenses.filter { calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
    }

    /// 明细分区：性质筛选后的记录，按天分组
    private var filteredMonthExpenses: [Expense] {
        guard let n = natureFilter.nature else { return monthExpenses }
        return monthExpenses.filter { $0.nature == n }
    }

    private var dayGroups: [(day: Date, items: [Expense], total: Double)] {
        let groups = Dictionary(grouping: filteredMonthExpenses) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            let items = groups[day]!.sorted { $0.date > $1.date }
            return (day, items, items.reduce(0) { $0 + $1.amount })
        }
    }

    /// 分类分区：九分类月汇总（金额降序）
    private var categoryTotals: [(category: ExpenseCategory, total: Double)] {
        ExpenseCategory.allCases.map { c in
            (c, monthExpenses.filter { $0.category == c }.reduce(0) { $0 + $1.amount })
        }
        .filter { $0.total > 0 }
        .sorted { $0.total > $1.total }
    }

    private var monthTotal: Double { monthExpenses.reduce(0) { $0 + $1.amount } }

    /// 月控制比
    private var monthControlRatio: Double? {
        guard monthExpenses.count >= 3 else { return nil }
        guard monthTotal > 0 else { return nil }
        let chosen = monthExpenses.filter { $0.nature == .chosen }.reduce(0) { $0 + $1.amount }
        return chosen / monthTotal
    }

    /// 趋势：近 6 个月（含当月）
    private var lastSixMonths: [Date] {
        let current = calendar.monthStart(.now)
        return (0..<6).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
    }

    private func monthTotal(_ month: Date) -> Double {
        expenses.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private func monthControlRatio(_ month: Date) -> Double? {
        let items = expenses.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        let total = items.reduce(0) { $0 + $1.amount }
        guard items.count >= 3, total > 0 else { return nil }
        return items.filter { $0.nature == .chosen }.reduce(0) { $0 + $1.amount } / total
    }

    /// 检索结果（备注 / 分类名 / 性质）
    private var searchResults: [Expense] {
        guard !searchText.isEmpty else { return [] }
        return expenses.filter { e in
            e.note.localizedCaseInsensitiveContains(searchText)
                || e.category.localizedName.localizedCaseInsensitiveContains(searchText)
                || e.amount.description.contains(searchText)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Text("帐本")
                .serifTitle(22)
                .foregroundStyle(DesignTokens.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.sm)

            sectionPicker

            switch selectedSection {
            case .detail:
                detailSection
            case .category:
                categorySection
            case .trend:
                trendSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignTokens.paper)
        .sheet(isPresented: $showMonthPanel) {
            MonthPanel(
                recordedMonths: recordedMonths,
                stats: monthStats,
                selected: selectedMonth,
                currency: currency,
                onSelect: { month in
                    selectedMonth = month
                    showMonthPanel = false
                }
            )
        }
        .sheet(item: $editingExpense) { expense in
            QuickAddView(editing: expense)
        }
        .alert("删除这条记录？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let e = pendingDelete {
                    modelContext.delete(e)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("删除后不可恢复")
        }
    }

    // MARK: - 分区切换

    private var sectionPicker: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(LedgerTab.allCases, id: \.self) { s in
                Button {
                    selectedSection = s
                } label: {
                    Text(s.rawValue)
                        .sansBody(14, weight: selectedSection == s ? .semibold : .regular)
                        .foregroundStyle(selectedSection == s ? DesignTokens.paper : DesignTokens.ash)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(selectedSection == s ? theme.current.accentColor : DesignTokens.card)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    // MARK: - 月份导航（明细/分类共用，选中状态同步）

    @ViewBuilder
    private var monthNavigator: some View {
        HStack {
            Button {
                jumpMonth(-1)
            } label: {
                Text("‹")
                    .serifTitle(20, weight: .medium)
                    .foregroundStyle(theme.current.accentColor)
                    .frame(width: 40, height: 36)
            }

            Spacer()

            Text(Self.monthText(selectedMonth))
                .sansBody(15, weight: .medium)
                .foregroundStyle(DesignTokens.ink)

            Spacer()

            Button {
                jumpMonth(1)
            } label: {
                Text("›")
                    .serifTitle(20, weight: .medium)
                    .foregroundStyle(theme.current.accentColor)
                    .frame(width: 40, height: 36)
            }

            Button {
                showMonthPanel = true
            } label: {
                Text("📅")
                    .font(.system(size: 16))
                    .frame(width: 40, height: 36)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    /// ‹ › 在有记录的月份间循环切换（无记录月份自动跳过）
    private func jumpMonth(_ direction: Int) {
        let months = recordedMonths
        guard let idx = months.firstIndex(of: selectedMonth) else {
            // 当前月无记录：直接跳最近的记录月
            if let nearest = direction < 0 ? months.last : months.first {
                selectedMonth = nearest
            }
            return
        }
        let next = (idx + direction + months.count) % months.count
        selectedMonth = months[next]
    }

    // MARK: - 明细

    private var detailSection: some View {
        VStack(spacing: 0) {
            subscriptionCard
            monthNavigator
            natureFilterBar

            if monthExpenses.isEmpty {
                emptyMonthCard
            } else if filteredMonthExpenses.isEmpty {
                Text("这个性质下本月没有记录")
                    .sansBody(14)
                    .foregroundStyle(DesignTokens.ash)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.items) { expense in
                                detailRow(expense)
                                    .listRowBackground(DesignTokens.card)
                                    .listRowSeparatorTint(DesignTokens.stoneDim)
                            }
                        } header: {
                            HStack {
                                Text(Self.dayText(group.day))
                                    .sansBody(12)
                                    .foregroundStyle(DesignTokens.ash)
                                Spacer()
                                Text(CurrencyService.shared.format(group.total, currency: currency))
                                    .sansBody(12)
                                    .foregroundStyle(DesignTokens.ash)
                            }
                            .textCase(nil)
                            .listRowBackground(DesignTokens.paper)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - FR-19 疑似订阅 + FR-22 本月预期

    private var detectedSubs: [SuspectedSubscription] {
        SubscriptionService.detect(expenses)
    }

    /// FR-19/22 — 帐本顶部卡：疑似订阅 + 已发生/待发生分列（中性措辞，不告警）
    @ViewBuilder
    private var subscriptionCard: some View {
        let subs = detectedSubs
        if !subs.isEmpty {
            let cancelled = SubscriptionService.cancelledIDs()
            let active = subs.filter { !cancelled.contains($0.id) }
            let monthEnd = calendar.dateInterval(of: .month, for: .now)!.end
            let expectedTotal = active
                .filter { ($0.nextDate ?? .distantFuture) < monthEnd }
                .reduce(0.0) { $0 + $1.monthlyAmount }
            let monthSpent = monthExpenses.reduce(0.0) { $0 + $1.amount }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                // FR-22 本月预期行
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本月已发生")
                            .sansBody(12)
                            .foregroundStyle(DesignTokens.ash)
                        Text(CurrencyService.shared.format(monthSpent, currency: currency))
                            .sansBody(16, weight: .semibold)
                            .foregroundStyle(DesignTokens.ink)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if expectedTotal > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("预计还会扣")
                                .sansBody(12)
                                .foregroundStyle(DesignTokens.ash)
                            Text(CurrencyService.shared.format(expectedTotal, currency: currency))
                                .sansBody(16, weight: .semibold)
                                .foregroundStyle(DesignTokens.ink)
                                .contentTransition(.numericText())
                        }
                    }
                }

                // FR-19 订阅列表
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        subscriptionsExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("疑似订阅 \(subs.count) 项")
                            .sansBody(13, weight: .medium)
                            .foregroundStyle(DesignTokens.ash)
                        Spacer()
                        Text(subscriptionsExpanded ? "▾" : "▸")
                            .sansBody(13)
                            .foregroundStyle(DesignTokens.ash)
                    }
                }

                if subscriptionsExpanded {
                    ForEach(subs) { sub in
                        subscriptionRow(sub, cancelled: cancelled.contains(sub.id))
                    }
                    Text("同名同额的规律扣费。取消的会计入「已守住」。")
                        .sansBody(11)
                        .foregroundStyle(DesignTokens.ash)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.sm)
        }
    }

    private func subscriptionRow(_ sub: SuspectedSubscription, cancelled: Bool) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sub.name)
                        .sansBody(14, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    if cancelled {
                        Text("已取消")
                            .sansBody(10, weight: .semibold)
                            .foregroundStyle(DesignTokens.paper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.verdigris)
                            .clipShape(Capsule())
                    }
                }
                Text("¥\(Self.trimAmount(sub.amount))/\(sub.period == .monthly ? "月" : "周") · 已扣 \(sub.dates.count) 次 · \(nextDateText(sub))")
                    .sansBody(11)
                    .foregroundStyle(DesignTokens.ash)
            }
            Spacer()
            Button {
                if cancelled {
                    SubscriptionService.unmarkCancelled(sub.id)
                } else {
                    SubscriptionService.markCancelled(sub.id, monthlyAmount: sub.monthlyAmount)
                }
            } label: {
                Text(cancelled ? "恢复" : "取消订阅")
                    .sansBody(12, weight: .semibold)
                    .foregroundStyle(cancelled ? DesignTokens.ash : DesignTokens.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(cancelled ? DesignTokens.card : DesignTokens.verdigris)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(DesignTokens.paper)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    private func nextDateText(_ sub: SuspectedSubscription) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日"
        return sub.nextDate.map { "下次预计 " + fmt.string(from: $0) } ?? "已停止"
    }

    private static func trimAmount(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.2f", v)
    }

    private func detailRow(_ expense: Expense) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(expense.category.emoji)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(expense))
                    .sansBody(14, weight: .medium)
                    .foregroundStyle(DesignTokens.ink)
                Text(natureLabel(expense.nature))
                    .sansBody(11)
                    .foregroundStyle(natureColor(expense.nature))
            }
            Spacer()
            Text(expense.formatted(currency: currency))
                .sansBody(14, weight: .medium)
                .foregroundStyle(DesignTokens.ink)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingExpense = expense }
    }

    private func rowTitle(_ expense: Expense) -> String {
        if !expense.note.isEmpty { return expense.note }
        return expense.category.localizedName
    }

    private var natureFilterBar: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(NatureFilter.allCases, id: \.self) { f in
                Button {
                    natureFilter = f
                } label: {
                    Text(f.rawValue)
                        .sansBody(12, weight: natureFilter == f ? .semibold : .regular)
                        .foregroundStyle(natureFilter == f ? theme.current.accentColor : DesignTokens.ash)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(natureFilter == f ? theme.current.accentDimColor : Color.clear)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    private var emptyMonthCard: some View {
        Text("这个月还没有记录")
            .sansBody(14)
            .foregroundStyle(DesignTokens.ash)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 分类

    private var categorySection: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.md) {
                monthNavigator

                if monthExpenses.isEmpty {
                    Text("记下第一笔，看看钱去了哪")
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ash)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .background(DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                } else {
                    summaryCard

                    ForEach(categoryTotals, id: \.category) { item in
                        categoryBar(item.category, total: item.total)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryItem(label: "月支出", value: CurrencyService.shared.format(monthTotal, currency: currency), color: DesignTokens.ink)
            Divider().frame(height: 30).overlay(DesignTokens.stoneDim)
            summaryItem(
                label: "控制比",
                value: monthControlRatio.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                color: theme.current.accentColor
            )
            Divider().frame(height: 30).overlay(DesignTokens.stoneDim)
            summaryItem(
                label: "最大分类",
                value: categoryTotals.first?.category.localizedName ?? "—",
                color: DesignTokens.ash
            )
        }
        .padding(.vertical, 14)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func summaryItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .sansBody(15, weight: .semibold)
                .foregroundStyle(color)
            Text(label)
                .sansBody(11)
                .foregroundStyle(DesignTokens.ash)
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryBar(_ category: ExpenseCategory, total: Double) -> some View {
        VStack(spacing: 0) {
            Button {
                expandedCategory = expandedCategory == category ? nil : category
            } label: {
                VStack(spacing: 6) {
                    HStack {
                        Text("\(category.emoji) \(category.localizedName)")
                            .sansBody(14)
                            .foregroundStyle(DesignTokens.ink)
                        Spacer()
                        Text(CurrencyService.shared.format(total, currency: currency))
                            .sansBody(13, weight: .medium)
                            .foregroundStyle(DesignTokens.ash)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.current.accentDimColor)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.current.accentColor.opacity(categoryTotals.first?.category == category ? 1.0 : 0.55))
                                .frame(width: max(4, geo.size.width * total / max(monthTotal, 0.01)))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(14)
                .background(DesignTokens.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }

            if expandedCategory == category {
                CategoryDetailList(items: monthExpenses.filter { $0.category == category }, currency: currency, theme: theme.current)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - 趋势

    private var trendSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                // 近 6 个月柱状图
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("近 6 个月")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                    HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                        ForEach(lastSixMonths, id: \.self) { month in
                            monthBar(month)
                        }
                    }
                    .frame(height: 140)

                    // 环比 — 中性表述：多花金色、少花绿色
                    if let prev = calendar.date(byAdding: .month, value: -1, to: selectedMonth),
                       monthTotal(prev) > 0, monthTotal > 0 {
                        let diff = monthTotal - monthTotal(prev)
                        if diff > 0 {
                            Text("比上月多花 \(CurrencyService.shared.format(diff, currency: currency))")
                                .sansBody(13)
                                .foregroundStyle(DesignTokens.gold)
                        } else if diff < 0 {
                            Text("比上月少花 \(CurrencyService.shared.format(-diff, currency: currency))")
                                .sansBody(13)
                                .foregroundStyle(theme.current.accentColor)
                        }
                    }
                }

                // 可控比 6 点走势
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("可控比走势")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(lastSixMonths, id: \.self) { month in
                            VStack {
                                if let r = monthControlRatio(month) {
                                    Text("\(Int((r * 100).rounded()))")
                                        .sansBody(11, weight: .medium)
                                        .foregroundStyle(theme.current.accentColor)
                                } else {
                                    Text("·")
                                        .sansBody(11)
                                        .foregroundStyle(DesignTokens.ash)
                                }
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(monthControlRatio(month).map { _ in theme.current.accentColor.opacity(0.5) } ?? DesignTokens.stoneDim)
                                    .frame(height: monthControlRatio(month).map { 20 + $0 * 50 } ?? 20)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                // 历史检索
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    TextField("搜索备注 / 分类 / 金额", text: $searchText)
                        .sansBody(14)
                        .padding(12)
                        .background(DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                    if !searchText.isEmpty {
                        ForEach(searchResults.prefix(20)) { expense in
                            detailRow(expense)
                                .padding(.vertical, 4)
                        }
                        if searchResults.isEmpty {
                            Text("没有匹配的记录")
                                .sansBody(13)
                                .foregroundStyle(DesignTokens.ash)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
    }

    private func monthBar(_ month: Date) -> some View {
        let total = monthTotal(month)
        let maxTotal = lastSixMonths.map { monthTotal($0) }.max() ?? 1
        return Button {
            selectedMonth = month
            selectedSection = .detail
        } label: {
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(month == selectedMonth ? theme.current.accentColor : theme.current.accentColor.opacity(0.45))
                    .frame(height: max(4, total / max(maxTotal, 0.01) * 100))
                Text(Self.monthShortText(month))
                    .sansBody(10)
                    .foregroundStyle(month == selectedMonth ? DesignTokens.ink : DesignTokens.ash)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 工具

    private func natureLabel(_ nature: ExpenseNature?) -> String {
        switch nature {
        case .chosen: return "✓ 主动选择"
        case .impulse: return "△ 冲动"
        case .necessity: return "· 必须"
        case nil: return "—"
        }
    }

    private func natureColor(_ nature: ExpenseNature?) -> Color {
        switch nature {
        case .chosen: return theme.current.accentColor
        case .impulse: return DesignTokens.gold
        case .necessity, nil: return DesignTokens.ash
        }
    }

    private static func monthText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    private static func monthShortText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f.string(from: date)
    }

    private static func dayText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}

// MARK: - Calendar 月份助手

private extension Calendar {
    func monthStart(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

// MARK: - 分类展开明细

private struct CategoryDetailList: View {
    let items: [Expense]
    let currency: String
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.prefix(8)) { expense in
                HStack {
                    Text(expense.note.isEmpty ? "—" : expense.note)
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                    Spacer()
                    Text(expense.formatted(currency: currency))
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            if items.count > 8 {
                Text("…共 \(items.count) 笔")
                    .sansBody(12)
                    .foregroundStyle(theme.accentColor)
                    .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - 全部月份面板

private struct MonthPanel: View {
    let recordedMonths: [Date]
    let stats: [Date: (count: Int, total: Double)]
    let selected: Date
    let currency: String
    let onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeObj: ThemeManager

    private var themeColor: Color { themeObj.current.accentColor }

    private var yearGroups: [(year: Int, months: [Date])] {
        let byYear = Dictionary(grouping: recordedMonths) { Calendar.current.component(.year, from: $0) }
        return byYear.keys.sorted(by: >).map { year in
            (year, (byYear[year] ?? []).sorted(by: >))
        }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text("全部月份")
                .serifTitle(20)
                .foregroundStyle(DesignTokens.ink)
                .padding(.top, DesignTokens.Spacing.lg)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    ForEach(yearGroups, id: \.year) { group in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("\(String(group.year))")
                                .sansBody(13, weight: .semibold)
                                .foregroundStyle(DesignTokens.ash)
                            ForEach(group.months, id: \.self) { month in
                                monthRow(month)
                            }
                        }
                    }
                    if recordedMonths.isEmpty {
                        Text("还没有任何记录")
                            .sansBody(14)
                            .foregroundStyle(DesignTokens.ash)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }
        }
        .background(DesignTokens.paper)
    }

    private func monthRow(_ month: Date) -> some View {
        let stat = stats[month] ?? (0, 0)
        return Button {
            onSelect(month)
        } label: {
            HStack {
                Text(Self.monthText(month))
                    .sansBody(15, weight: month == selected ? .semibold : .regular)
                    .foregroundStyle(month == selected ? themeColor : DesignTokens.ink)
                Spacer()
                Text("\(stat.count) 笔 · \(CurrencyService.shared.format(stat.total, currency: currency))")
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.ash)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(month == selected ? themeColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    private static func monthText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }
}
