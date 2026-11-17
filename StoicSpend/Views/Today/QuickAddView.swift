import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension Notification.Name {
    /// FR-16 — 新记录已保存（带 pendingUndoID），首页展示「已记下 · 撤销」
    static let quickAddSaved = Notification.Name("quickadd.saved")
}

/// 单页快记 — 只输金额即可保存，v1.1 目标 ≤ 3 秒（FR-02/FR-13~FR-18）
/// 自绘数字键盘（⌫ 右下拇指热区）+ 累加 chips + 算式（+ / ÷2）+ 常用组合一键套用
/// 触感：按键 light / chip selection / 保存 success（FR-15）
struct QuickAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    // 上次选择记忆（首次默认：主动选择 / 饮食）
    @AppStorage("lastNatureRaw") private var lastNatureRaw: String = ExpenseNature.chosen.rawValue
    @AppStorage("lastCategoryRaw") private var lastCategoryRaw: String = ExpenseCategory.food.rawValue

    @State private var amountText = ""      // 支持算式：12+8÷2
    @State private var nature: ExpenseNature
    @State private var categoryKey: String   // 内置 rawValue 或 "custom:<uuid>"（FR-29）
    @State private var emotion: ExpenseEmotion?
    @State private var flowType: FlowType = .expense   // FR-31 默认支出，补充 sheet 里切换
    @State private var categoryTouched = false         // FR-32 用户是否手动选过分类（未选时允许规则套用）
    @State private var zeroFlash = false
    @State private var dotInserted = false  // 长按 0 插入小数点后吞掉随后的 tap
    @State private var showExtra = false    // 补充三问 sheet（性质/情绪/备注）
    @State private var showManager = false  // 自定义分类管理页
    @State private var items: [CategoryItem] = []   // 宫格显示顺序（长按拖动可重排）
    @State private var draggingKey: String? // 正在拖动的类别 key
    @State private var recentCombos: [RecentCombo] = RecentComboStore.load()
    @State private var note = ""            // 备注（语音记账全文落在这里）
    @State private var showVoiceCard = false
    @State private var voiceDraft = ""      // 语音听写文案（可二次编辑）
    @StateObject private var transcriber = VoiceTranscriber()

    private let maxAmount: Double = 999_999

    /// 编辑模式 — 传入已有记录时预填并就地更新
    private let editing: Expense?

    /// FR-25 截图记账 — 分享扩展解析出的捕获，预填金额/商户，确认页只补分类
    private let capture: PendingCapture?

    init(editing: Expense? = nil, capture: PendingCapture? = nil) {
        self.editing = editing
        self.capture = capture
        if let e = editing {
            _amountText = State(initialValue: Self.format(e.amount))
            _nature = State(initialValue: e.nature ?? .chosen)
            _categoryKey = State(initialValue: e.categoryGroupKey)
            _emotion = State(initialValue: e.emotion)
            _note = State(initialValue: e.note)
            _flowType = State(initialValue: e.flowType)
            _categoryTouched = State(initialValue: true)   // 编辑模式保持原分类
        } else if let cap = capture {
            // 性质/分类走默认上次值，识别失败时金额留空手动输入
            let natureRaw = UserDefaults.standard.string(forKey: "lastNatureRaw") ?? ExpenseNature.chosen.rawValue
            _nature = State(initialValue: ExpenseNature(rawValue: natureRaw) ?? .chosen)
            let categoryRaw = UserDefaults.standard.string(forKey: "lastCategoryRaw") ?? ExpenseCategory.food.rawValue
            _categoryKey = State(initialValue: Self.validKey(categoryRaw))
            _amountText = State(initialValue: cap.amount.map(Self.format) ?? "")
            _note = State(initialValue: cap.merchant ?? "")
        } else {
            let natureRaw = UserDefaults.standard.string(forKey: "lastNatureRaw") ?? ExpenseNature.chosen.rawValue
            _nature = State(initialValue: ExpenseNature(rawValue: natureRaw) ?? .chosen)
            let categoryRaw = UserDefaults.standard.string(forKey: "lastCategoryRaw") ?? ExpenseCategory.food.rawValue
            _categoryKey = State(initialValue: Self.validKey(categoryRaw))
        }
    }

    /// 上次 key 有效性校验：自定义类别可能已被删除，失效则回落饮食
    private static func validKey(_ key: String) -> String {
        if let raw = ExpenseCategory(rawValue: key) { return raw.rawValue }
        if let id = CategoryStore.uuid(fromKey: key), CategoryStore.find(id: id) != nil { return key }
        return ExpenseCategory.food.rawValue
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }

    // MARK: - FR-18 算式求值：加法串，每项可带一次 ÷2（AA 分摊）

    static func evaluate(_ expr: String) -> Double {
        let parts = expr.split(separator: "+")
        guard !parts.isEmpty else { return 0 }
        var sum = 0.0
        for p in parts {
            if p.hasSuffix("÷2") {
                sum += (Double(p.dropLast(2)) ?? 0) / 2
            } else {
                sum += Double(p) ?? 0
            }
        }
        return sum
    }

    private var amountValue: Double {
        Self.evaluate(amountText)
    }

    // MARK: - 语音文案实时解析（听写过程中即预览）

    private var voiceParsedAmount: Double? {
        guard !voiceDraft.isEmpty else { return nil }
        return NaturalExpenseParser.parseVoiceAmount(from: voiceDraft)
    }

    private var voiceParsedCategory: ExpenseCategory? {
        guard !voiceDraft.isEmpty else { return nil }
        return NaturalExpenseParser.parseCategory(from: voiceDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：静默取消
            HStack {
                Button {
                    dismiss()
                } label: {
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
                    if capture != nil {
                        captureBanner
                    }
                    incrementChips
                    if !recentCombos.isEmpty {
                        comboSection
                    }
                    categoryGrid
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)   // 装得下就不滚动（一屏宫格）

            saveBar
        }
        .background(DesignTokens.paper)
        .onReceive(transcriber.$transcript) { text in
            // 听写文案实时回显（录音结束后可在卡片内二次编辑）
            if transcriber.isRecording {
                voiceDraft = text
            }
        }
        .onDisappear {
            transcriber.stop()
        }
        .onAppear { reloadCategories() }
        .sheet(isPresented: $showExtra) { extraSheet }
        .sheet(isPresented: $showManager, onDismiss: reloadCategories) {
            CategoryManagerView()
        }
    }

    // MARK: - 金额显示（FR-15 数字滚动 / 长按清零）

    private var amountDisplay: some View {
        HStack(spacing: 4) {
            Text("¥")
                .font(Typography.serif(26, weight: .medium))
                .foregroundStyle(amountText.isEmpty ? DesignTokens.ash : theme.current.accentColor)
            Text(amountText.isEmpty ? "0" : amountText)
                .font(Typography.serif(64, weight: .semibold))
                .tracking(-1.5)
                .foregroundStyle(amountText.isEmpty
                    ? (zeroFlash ? DesignTokens.gold : DesignTokens.stoneDim)
                    : DesignTokens.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .onLongPressGesture(minimumDuration: 0.4) {
                    guard !amountText.isEmpty else { return }
                    amountText = ""
                    Haptics.selectionChanged()
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .animation(.easeOut(duration: 0.18), value: amountText)
    }

    // MARK: - FR-25 截图捕获来源提示（识别成功金额/商户 / 失败回落手动输入）

    private var captureBanner: some View {
        Group {
            if let amount = capture?.amount {
                HStack(spacing: 4) {
                    Text("已从截图识别")
                    Text(verbatim: "¥\(formatAmount(amount))")
                    if let m = capture?.merchant {
                        Text(verbatim: "· \(m)")
                    }
                }
                .sansBody(12)
                .foregroundStyle(theme.current.accentColor)
            } else {
                Text("截图里没识别到金额，请手动输入")
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 快捷增量 chips（累加逻辑）

    private var incrementChips: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ForEach([10, 50, 100, 500], id: \.self) { inc in
                Button {
                    Haptics.keyLight()
                    let next = min(amountValue + Double(inc), maxAmount)
                    amountText = formatAmount(next)
                } label: {
                    Text("+\(inc)")
                        .sansBody(14, weight: .medium)
                        .foregroundStyle(theme.current.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(theme.current.accentDimColor)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }

    // MARK: - FR-17 常用组合一键套用

    private var comboSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("最近常用")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(recentCombos, id: \.self) { combo in
                    Button {
                        Haptics.selectionChanged()
                        withAnimation(.easeOut(duration: 0.18)) {
                            if let n = combo.nature { nature = n }
                            if let c = combo.category { categoryKey = c.rawValue }
                        }
                    } label: {
                        Text(combo.label)
                            .sansBody(13, weight: .medium)
                            .foregroundStyle(DesignTokens.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignTokens.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(DesignTokens.stoneDim, lineWidth: 1))
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - 性质三选一（在「补充」sheet 内）

    private func natureChip(_ n: ExpenseNature, label: String) -> some View {
        chipButton(label: label, selected: nature == n) {
            nature = n
        }
    }

    // MARK: - 补充三问 sheet（性质 / 情绪 / 备注 — 可选，不挡主流程）

    private var extraSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("补充三问（可不填）")
                    .serifTitle(15)
                    .foregroundStyle(DesignTokens.ink)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("这笔钱花得怎么样？")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        natureChip(.chosen, label: "✓ 主动选择")
                        natureChip(.necessity, label: "· 必须花")
                        natureChip(.impulse, label: "△ 冲动了")
                    }
                }

                // FR-31 资金流类型（默认支出；收入仅落库不统计，退款负冲抵，转账不进分类）
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("这笔钱的类型")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(FlowType.allCases) { t in
                            chipButton(label: t.localizedName, selected: flowType == t) {
                                flowType = t
                            }
                        }
                    }
                    if flowType != .expense {
                        Text("收入不进任何统计；退款按负值冲抵本月支出；转账不进分类。")
                            .sansBody(11)
                            .foregroundStyle(DesignTokens.ash)
                    }
                }

                emotionSection
                noteField

                // FR-32 规则命中提示（未手动选分类时保存将套用）
                if !categoryTouched, !note.isEmpty,
                   let hit = CategoryRuleStore.match(note: note),
                   let name = CategoryRuleStore.displayName(for: hit) {
                    Text("保存时将按你的习惯归入「\(name)」")
                        .sansBody(11)
                        .foregroundStyle(theme.current.accentColor)
                }

                Button {
                    showExtra = false
                } label: {
                    Text("收起")
                        .sansBody(15, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.current.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.paper)
        .presentationDetents([.medium, .large])
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardToolbar()
    }

    // MARK: - 分类宫格（一屏 4 列常驻；长按拖动重排，落点自动让位并持久化）

    /// 宫格单元（内置 / 自定义统一形态）
    struct CategoryItem: Identifiable, Equatable {
        let key: String
        let emoji: String
        let name: String
        var id: String { key }
    }

    private func reloadCategories() {
        items = CategoryStore.orderedKeys().map { key in
            if let raw = ExpenseCategory(rawValue: key) {
                return CategoryItem(key: key, emoji: raw.emoji, name: raw.localizedName)
            }
            if let id = CategoryStore.uuid(fromKey: key), let cat = CategoryStore.find(id: id) {
                return CategoryItem(key: key, emoji: cat.emoji, name: cat.name)
            }
            return CategoryItem(key: key, emoji: "◇", name: key)
        }
    }

    private var categoryGrid: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), count: 4), spacing: DesignTokens.Spacing.sm) {
                ForEach(items) { item in
                    gridChip(item)
                        .onDrag {
                            draggingKey = item.key
                            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                                if draggingKey == item.key { draggingKey = nil }  // 拖动取消兜底
                            }
                            return NSItemProvider(object: item.key as NSString)
                        }
                        .onDrop(of: [.text], delegate: CategoryDropDelegate(
                            item: item,
                            items: $items,
                            draggingKey: $draggingKey
                        ) {
                            CategoryStore.saveOrder(items.map(\.key))
                        })
                }
                manageChip
            }
            Text("长按可拖动排序")
                .sansBody(11)
                .foregroundStyle(DesignTokens.ash)
        }
    }

    private func gridChip(_ item: CategoryItem) -> some View {
        let selected = categoryKey == item.key
        return Button {
            Haptics.selectionChanged()
            categoryTouched = true
            withAnimation(.easeOut(duration: 0.18)) {
                categoryKey = item.key
            }
        } label: {
            VStack(spacing: 3) {
                Text(verbatim: item.emoji)
                    .font(.system(size: 20))
                Text(verbatim: item.name)
                    .sansBody(11, weight: selected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? theme.current.accentColor : DesignTokens.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(selected ? theme.current.accentDimColor : DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(
                    selected ? theme.current.accentColor : DesignTokens.stoneDim,
                    lineWidth: selected ? 1.5 : 1
                )
            )
            .opacity(draggingKey == item.key ? 0.4 : 1)
        }
    }

    /// 管理入口 — 打开自定义分类页
    private var manageChip: some View {
        Button {
            Haptics.selectionChanged()
            showManager = true
        } label: {
            VStack(spacing: 3) {
                Text("＋").font(.system(size: 16))
                Text("管理").sansBody(11)
            }
            .foregroundStyle(DesignTokens.ash)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DesignTokens.card.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.stoneDim, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
    }

    // MARK: - 情绪六选一（可选）— emoji 圆钮一行排布

    private var emotionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("当时什么情绪？")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)

            HStack(spacing: 0) {
                ForEach(ExpenseEmotion.allCases) { e in
                    emotionButton(e)
                }
            }
        }
    }

    private func emotionButton(_ e: ExpenseEmotion) -> some View {
        let selected = emotion == e
        return Button {
            Haptics.selectionChanged()
            emotion = selected ? nil : e   // 再点一次取消
        } label: {
            VStack(spacing: 5) {
                Text(Self.emotionEmoji(e))
                    .font(.system(size: 22))
                    .frame(width: 42, height: 42)
                    .background(selected ? theme.current.accentDimColor : DesignTokens.card)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(
                            selected ? theme.current.accentColor : Color.clear,
                            lineWidth: 1.5
                        )
                    )
                Text(e.localizedName)
                    .sansBody(11, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? theme.current.accentColor : DesignTokens.ash)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
    }

    private static func emotionEmoji(_ e: ExpenseEmotion) -> String {
        switch e {
        case .calm: return "😌"
        case .anxious: return "😰"
        case .excited: return "🤩"
        case .tired: return "🥱"
        case .stressed: return "😖"
        case .satisfied: return "🥰"
        }
    }

    // MARK: - 自绘数字键盘 + 保存

    private var saveBar: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if showVoiceCard {
                voiceCard
            }
            amountDisplay
            expressionRow
            keypad
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    Haptics.selectionChanged()
                    showExtra = true
                } label: {
                    VStack(spacing: 2) {
                        Text("＋").font(.system(size: 17, weight: .medium))
                        Text("补充").sansBody(10)
                    }
                    .foregroundStyle(DesignTokens.ash)
                    .frame(width: 60, height: 52)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }
                .accessibilityIdentifier("quickadd.extra")

                Button {
                    save()
                } label: {
                    Text("记好了")
                        .sansBody(18, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.current.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .accessibilityIdentifier("quickadd.save")
                .padding(.bottom, DesignTokens.Spacing.md)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .background(DesignTokens.paper)
        .dismissKeyboardToolbar()
    }

    /// FR-18 算式操作行 + FR-26 语音入口
    private var expressionRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            keyButton(title: "+", subtitle: "加一笔") {
                guard !currentTerm.isEmpty, !amountText.isEmpty,
                      amountText.split(separator: "+").count < 8 else { return }
                amountText += "+"
            }
            keyButton(title: "÷2", subtitle: "AA 分摊") {
                guard !currentTerm.isEmpty, !amountText.contains("÷") else { return }
                amountText += "÷2"
            }
            keyButton(title: transcriber.isRecording ? "⏹" : "🎤",
                      subtitle: transcriber.isRecording ? "停止" : "语音") {
                toggleVoice()
            }
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }

    private func keyButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.keyLight()
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.current.accentColor)
                Text(LocalizedStringKey(subtitle))
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.ash)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    // MARK: - FR-26 语音记账（听写 → 实时文案 → 可编辑 → 解析填入）

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 6) {
                Text(transcriber.isRecording ? "🔴 正在听写…" : "✍️ 听写结果 · 可修改")
                    .sansBody(12)
                    .foregroundStyle(transcriber.isRecording ? DesignTokens.gold : DesignTokens.ash)
                Spacer()
                Button {
                    showVoiceCard = false
                    voiceDraft = ""
                    transcriber.stop()
                } label: {
                    Text("关闭")
                        .sansBody(12)
                        .foregroundStyle(DesignTokens.ash)
                }
            }

            if transcriber.isRecording {
                // 听写中：文案实时刷新，只读展示
                Text(voiceDraft.isEmpty ? "…" : voiceDraft)
                    .sansBody(15)
                    .foregroundStyle(DesignTokens.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(DesignTokens.paper)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            } else {
                // 听写结束：可二次编辑
                TextField("听写结果会出现在这里", text: $voiceDraft, axis: .vertical)
                    .sansBody(15)
                    .lineLimit(3)
                    .padding(10)
                    .background(DesignTokens.paper)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                if let a = voiceParsedAmount {
                    Text("¥\(formatAmount(a))")
                        .sansBody(13, weight: .semibold)
                        .foregroundStyle(theme.current.accentColor)
                }
                if let c = voiceParsedCategory {
                    Text("\(c.emoji) \(c.localizedName)")
                        .sansBody(13)
                        .foregroundStyle(theme.current.accentColor)
                }
                Spacer()
                Button {
                    applyVoice()
                } label: {
                    Text("填入")
                        .sansBody(13, weight: .semibold)
                        .foregroundStyle(voiceParsedAmount == nil ? DesignTokens.ash : DesignTokens.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(voiceParsedAmount == nil ? DesignTokens.card : theme.current.accentColor)
                        .clipShape(Capsule())
                }
                .disabled(voiceParsedAmount == nil)
            }

            if voiceParsedAmount == nil && !voiceDraft.isEmpty {
                Text("文案里没找到金额，可以手动输入后保存")
                    .sansBody(11)
                    .foregroundStyle(DesignTokens.gold)
            }

            if let hint = transcriber.errorHint {
                Text(hint)
                    .sansBody(11)
                    .foregroundStyle(DesignTokens.gold)
            }
        }
        .padding(12)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func toggleVoice() {
        Haptics.selectionChanged()
        if transcriber.isRecording {
            transcriber.stop()
        } else if showVoiceCard {
            transcriber.start()   // 再听一次，重新开始
            voiceDraft = ""
        } else {
            showVoiceCard = true
            voiceDraft = ""
            transcriber.start()
        }
    }

    private func applyVoice() {
        guard let a = voiceParsedAmount else { return }
        Haptics.saveSuccess()
        withAnimation(.easeOut(duration: 0.18)) {
            amountText = formatAmount(a)
            if let c = voiceParsedCategory {
                categoryKey = c.rawValue
            }
        }
        note = voiceDraft   // 全文作备注，可在备注栏再改
        showVoiceCard = false
        voiceDraft = ""
    }

    /// 备注（可选）— 语音记账的落点
    private var noteField: some View {
        TextField("备注（可选）", text: $note)
            .sansBody(14)
            .padding(12)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private var keypad: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            let rows: [[String]] = [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"], ["000", "0", "⌫"]]
            ForEach(rows, id: \.self) { row in
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(row, id: \.self) { key in
                        if key == "0" {
                            zeroKeyButton
                        } else {
                            keypadButton(key)
                        }
                    }
                }
            }
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }

    private func keypadButton(_ key: String) -> some View {
        Button {
            Haptics.keyLight()
            handleKey(key)
        } label: {
            Text(key)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(DesignTokens.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(DesignTokens.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    /// 「0」长按输入小数点（FR-18）；长按后吞掉释放时的 tap
    private var zeroKeyButton: some View {
        keypadButton("0")
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        appendDot()
                        dotInserted = true
                    }
            )
    }

    // MARK: - 逻辑

    /// 当前正在输入的项（最后一个 + 之后的部分；以 ÷2 结尾时为空）
    private var currentTerm: String {
        if amountText.hasSuffix("÷2") { return "" }
        return amountText.split(separator: "+", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    }

    private func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if amountText.hasSuffix("÷2") {
                amountText.removeLast(2)
            } else if !amountText.isEmpty {
                amountText.removeLast()
            }
        case "0":
            if dotInserted {
                dotInserted = false   // 长按插入过小数点，吞掉本次 tap
                return
            }
            appendToTerm("0")
        default:
            appendToTerm(key)
        }
    }

    /// 向当前项追加数字串（含小数位校验、去前导零、上限校验）
    /// 空状态直接开新项；以 ÷2 结尾时自动开启新项
    private func appendToTerm(_ s: String) {
        var term = currentTerm
        if term.contains(".") {
            let decimals = term.split(separator: ".").last?.count ?? 0
            guard decimals + s.count <= 2 else { return }
        }
        term += s
        while term.count > 1 && term.hasPrefix("0") && !term.hasPrefix("0.") {
            term.removeFirst()
        }
        let candidate: String
        if amountText.hasSuffix("÷2") {
            candidate = amountText + "+" + term
        } else {
            candidate = String(amountText.dropLast(currentTerm.count)) + term
        }
        guard Self.evaluate(candidate) <= maxAmount else { return }
        amountText = candidate
    }

    /// 长按 0：向当前项插入小数点（每项最多一个，小数最多 2 位）
    private func appendDot() {
        guard !currentTerm.isEmpty, !currentTerm.contains(".") else { return }
        amountText += "."
    }

    private func formatAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        let s = String(format: "%.2f", value)
        // 去掉末尾多余的 0（如 12.50 → 12.5）
        return s.hasSuffix("0") ? String(s.dropLast()) : s
    }

    private func save() {
        guard amountValue > 0 else {
            // 金额为 0：金色高亮 0.9 秒，不弹窗
            zeroFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                zeroFlash = false
            }
            return
        }

        // FR-32 分类纠错记忆：未手动选分类且备注命中规则 → 按习惯归类
        var effectiveKey = categoryKey
        if !categoryTouched, !note.isEmpty,
           let hit = CategoryRuleStore.match(note: note) {
            effectiveKey = hit.categoryKey
        }

        if let e = editing {
            e.amount = amountValue
            e.nature = nature
            e.category = ExpenseCategory(rawValue: effectiveKey) ?? .other
            e.customCategoryID = CategoryStore.uuid(fromKey: effectiveKey)
            e.emotion = emotion
            e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            e.flowType = flowType
        } else {
            let expense = Expense(
                amount: amountValue,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                nature: nature,
                category: ExpenseCategory(rawValue: effectiveKey) ?? .other,
                emotion: emotion
            )
            expense.customCategoryID = CategoryStore.uuid(fromKey: effectiveKey)
            expense.flowType = flowType
            modelContext.insert(expense)

            // FR-16 — 首页「已记下 · 撤销」通道
            UserDefaults.standard.set(expense.id.uuidString, forKey: "pendingUndoID")
            NotificationCenter.default.post(name: .quickAddSaved, object: nil)
        }

        Haptics.saveSuccess()

        // 记忆本次选择 + 常用组合（FR-31：仅消费进组合与最近分类记忆）
        if flowType == .expense {
            lastNatureRaw = nature.rawValue
            lastCategoryRaw = effectiveKey
            if let c = ExpenseCategory(rawValue: effectiveKey) {
                RecentComboStore.record(nature: nature, category: c)
            }
        }

        dismiss()
    }

    // MARK: - 通用 chip（选中 180ms 形变）

    private func chipButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selectionChanged()
            withAnimation(.easeOut(duration: 0.18)) {
                action()
            }
        } label: {
            Text(label)
                .sansBody(13, weight: selected ? .semibold : .regular)
                .foregroundStyle(selected ? DesignTokens.paper : DesignTokens.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(selected ? theme.current.accentColor : DesignTokens.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.clear : DesignTokens.stoneDim,
                        lineWidth: 1
                    )
                )
        }
    }
}

// MARK: - 宫格拖动排序 Delegate — 进入目标格自动让位（弹簧动画），落点持久化顺序

private struct CategoryDropDelegate: DropDelegate {
    let item: QuickAddView.CategoryItem
    @Binding var items: [QuickAddView.CategoryItem]
    @Binding var draggingKey: String?
    let onDropEnd: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingKey, dragging != item.key,
              let from = items.firstIndex(where: { $0.key == dragging }),
              let to = items.firstIndex(where: { $0.key == item.key }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingKey = nil
        onDropEnd()
        return true
    }
}
