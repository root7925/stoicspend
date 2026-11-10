import SwiftUI
import SwiftData
import WidgetKit

/// 首页 — 控制环 + 本周概览 + 今日明细 + 记一笔 + ◈ 晚间回顾入口（FR-01/FR-05）
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeManager
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    private var currency: String { CurrencyService.shared.currentCurrency(in: modelContext) }

    @State private var showQuickAdd = false
    @State private var showEveningReview = false
    // FR-25 截图记账 — 分享扩展捕获的待确认账单
    @State private var captureToAdd: PendingCapture?
    @Environment(\.scenePhase) private var scenePhase

    // FR-16 即时因果反馈
    @State private var undoExpenseID: String?   // 非空 = 底部显示「已记下 · 撤销」
    @State private var highlightID: UUID?       // 新记录高亮 1.5s

    private var calendar: Calendar { Calendar.current }

    // MARK: - 派生数据

    /// 本周记录（自然周口径）
    private var weekExpenses: [Expense] {
        expenses.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
    }

    /// 控制比（周口径，金额口径；样本 < 3 笔不展示）
    private var controlRatio: Double? {
        guard weekExpenses.count >= 3 else { return nil }
        let total = weekExpenses.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return nil }
        let chosen = weekExpenses.filter { $0.nature == .chosen }.reduce(0) { $0 + $1.amount }
        return chosen / total
    }

    private var weekTotal: Double { weekExpenses.reduce(0) { $0 + $1.amount } }
    private var weekChosen: Double { weekExpenses.filter { $0.nature == .chosen }.reduce(0) { $0 + $1.amount } }
    private var weekNecessity: Double { weekExpenses.filter { $0.nature == .necessity }.reduce(0) { $0 + $1.amount } }

    /// 今日明细（倒序最多 5 笔）
    private var todayExpenses: [Expense] {
        expenses.filter { calendar.isDateInToday($0.date) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    header
                    controlRingSection
                    weekOverviewCard
                    todaySection
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.xl)
            }

            bottomBar
        }
        .background(DesignTokens.paper)
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView()
        }
        // FR-25 — 截图捕获确认页（预填金额/商户，只补分类）
        .sheet(item: $captureToAdd, onDismiss: { PendingCaptureStore.clear() }) { cap in
            QuickAddView(capture: cap)
        }
        .sheet(isPresented: $showEveningReview) {
            // FR-23 — 半屏卡片，回顾不离开首页
            EveningReviewView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickAddSaved)) { _ in
            presentUndoToast()
            // FR-21 — 数据变化 → 刷新小组件快照
            WidgetSnapshotWriter.update(expenses: expenses)
            WidgetCenter.shared.reloadAllTimelines()
        }
        // FR-21 — 增删改都落到 derived 值变化，统一刷新快照
        .onChange(of: weekTotal) { _, _ in
            WidgetSnapshotWriter.update(expenses: expenses)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: controlRatio) { _, _ in
            WidgetSnapshotWriter.update(expenses: expenses)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .task {
            WidgetSnapshotWriter.update(expenses: expenses)
        }
        // FR-13 — 全局快捷入口直达快记页
        .onReceive(NotificationCenter.default.publisher(for: .widgetOpenQuickAdd)) { _ in
            showQuickAdd = true
        }
        // FR-25 — 分享扩展深链 / 前台激活时消费待处理截图捕获
        .onReceive(NotificationCenter.default.publisher(for: .captureOpenQuickAdd)) { _ in
            consumePendingCapture()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                consumePendingCapture()
            }
        }
        .overlay(alignment: .bottom) {
            if let undoID = undoExpenseID {
                undoToast(id: undoID)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: undoExpenseID)
    }

    // MARK: - FR-16 已记下 · 撤销

    /// FR-25 — 消费待处理截图捕获（无待处理时静默跳过）
    private func consumePendingCapture() {
        guard captureToAdd == nil, showQuickAdd == false,
              let pending = PendingCaptureStore.load() else { return }
        captureToAdd = pending
    }

    private func presentUndoToast() {
        guard let idStr = UserDefaults.standard.string(forKey: "pendingUndoID") else { return }
        undoExpenseID = idStr
        if let id = UUID(uuidString: idStr) {
            highlightID = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { highlightID = nil }
            }
        }
        // 5 秒后自动收起
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if undoExpenseID == idStr {
                undoExpenseID = nil
            }
        }
    }

    private func undoToast(id: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("已记下")
                .sansBody(14)
                .foregroundStyle(DesignTokens.ink)
            Button {
                undoLastSave(id: id)
            } label: {
                Text("撤销")
                    .sansBody(14, weight: .semibold)
                    .foregroundStyle(theme.current.accentColor)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DesignTokens.stoneDim, lineWidth: 1))
    }

    private func undoLastSave(id: String) {
        guard let uuid = UUID(uuidString: id),
              let expense = expenses.first(where: { $0.id == uuid }) else {
            undoExpenseID = nil
            return
        }
        modelContext.delete(expense)
        try? modelContext.save()
        UserDefaults.standard.removeObject(forKey: "pendingUndoID")
        undoExpenseID = nil
    }

    // MARK: - ① 日期与连续记录 7 日点阵（FR-28）

    private var header: some View {
        HStack(alignment: .center) {
            Text(Self.dateText())
                .serifTitle(22)
                .foregroundStyle(DesignTokens.ink)
            Spacer()
            streakDots
        }
    }

    /// FR-28 — 近 7 日点阵：有记录点亮主题色，今天稍大；只反映事实，不做签到奖励与断签惩罚
    private var streakDots: some View {
        let recorded = Set(expenses.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: .now)
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
                Circle()
                    .fill(recorded.contains(day) ? theme.current.accentColor : DesignTokens.stoneDim.opacity(0.35))
                    .frame(width: day == today ? 11 : 9, height: day == today ? 11 : 9)
            }
        }
    }

    // MARK: - ② 控制比 · 刊头式排版（hairline 框边 + eyebrow 字距 + 大数字）

    private var controlRingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部细规线 — 杂志刊头框边
            Rectangle().fill(DesignTokens.stoneDim).frame(height: 1)

            if let ratio = controlRatio {
                // eyebrow 行：小字距点题 + 公式
                HStack(alignment: .firstTextBaseline) {
                    Text("本周可控")
                        .sansBody(11, weight: .semibold)
                        .tracking(2)
                        .foregroundStyle(theme.current.accentColor)
                    Spacer()
                    Text("主动选择 ÷ 本周支出")
                        .sansBody(11)
                        .foregroundStyle(DesignTokens.ash)
                }
                .padding(.top, DesignTokens.Spacing.sm)

                // 大数字：衬线主体 + 主题色小号百分号
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int((ratio * 100).rounded()))")
                        .serifTitle(72, weight: .bold)
                        .foregroundStyle(DesignTokens.ink)
                        .tracking(-1)
                        .contentTransition(.numericText())
                    Text("%")
                        .serifTitle(28, weight: .semibold)
                        .foregroundStyle(theme.current.accentColor)
                        .contentTransition(.numericText())
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
                .animation(.easeOut(duration: 0.4), value: ratio)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("本周可控")
                        .sansBody(11, weight: .semibold)
                        .tracking(2)
                        .foregroundStyle(DesignTokens.ash)
                    Spacer()
                    Text("记录满 3 笔后可见")
                        .sansBody(11)
                        .foregroundStyle(DesignTokens.ash)
                }
                .padding(.top, DesignTokens.Spacing.sm)

                Text("···")
                    .serifTitle(72, weight: .bold)
                    .foregroundStyle(DesignTokens.stoneDim)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            }

            // 进度线：细轨 + 圆头 + 端点小珠
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignTokens.stoneDim)
                        .frame(height: 4)
                    if let ratio = controlRatio {
                        ZStack(alignment: .trailing) {
                            Capsule()
                                .fill(theme.current.accentColor)
                                .frame(width: max(geo.size.width * ratio, 8), height: 4)
                            Circle()
                                .fill(theme.current.accentColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .frame(height: 8)
            .padding(.bottom, DesignTokens.Spacing.sm)

            // 底部细规线
            Rectangle().fill(DesignTokens.stoneDim).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ③ 本周概览

    private var weekOverviewCard: some View {
        HStack(spacing: 0) {
            overviewItem(label: "本周支出", value: weekTotal, color: DesignTokens.ink)
            Divider().frame(height: 32).overlay(DesignTokens.stoneDim)
            overviewItem(label: "主动选择", value: weekChosen, color: theme.current.accentColor)
            Divider().frame(height: 32).overlay(DesignTokens.stoneDim)
            overviewItem(label: "必须花", value: weekNecessity, color: DesignTokens.ash)
        }
        .padding(.vertical, 16)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func overviewItem(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(CurrencyService.shared.format(value, currency: currency))
                .sansBody(16, weight: .semibold)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .sansBody(11)
                .foregroundStyle(DesignTokens.ash)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.4), value: value)
    }

    // MARK: - ④ 今日明细

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("今天")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)

            if todayExpenses.isEmpty {
                Text("今天还没有记录")
                    .sansBody(14)
                    .foregroundStyle(DesignTokens.ash)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayExpenses.prefix(5).enumerated()), id: \.element.id) { index, expense in
                        expenseRow(expense)
                        if index < min(todayExpenses.count, 5) - 1 {
                            Divider().overlay(DesignTokens.stoneDim)
                        }
                    }
                }
                .background(DesignTokens.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

                if todayExpenses.count > 5 {
                    Text("查看全部 \(todayExpenses.count) 笔")
                        .sansBody(13)
                        .foregroundStyle(theme.current.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(expense.category.emoji)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category.localizedName)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            // FR-16 — 新记录高亮 1.5 秒
            highlightID == expense.id ? theme.current.accentDimColor : Color.clear
        )
        .animation(.easeInOut(duration: 0.3), value: highlightID)
    }

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

    // MARK: - ⑤ 底部主按钮 + 回顾入口

    private var bottomBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button {
                showEveningReview = true
            } label: {
                Text("◈")
                    .serifTitle(20, weight: .regular)
                    .foregroundStyle(theme.current.accentColor)
                    .frame(width: 52, height: 52)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }

            Button {
                showQuickAdd = true
            } label: {
                Text("+ 记一笔")
                    .sansBody(17, weight: .semibold)
                    .foregroundStyle(DesignTokens.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(theme.current.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private static func dateText() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: .now)
    }
}
