import SwiftUI
import SwiftData

/// 页面 3 — 三问记账流程
/// 金额输入 → Q1(主动/冲动) → Q2(价值观多选) → Q3(情绪触发文本,仅冲动) → Note(笔记) → 完成
/// 每题可跳过
struct AddExpenseFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: FlowStep = .amount
    @State private var amount: String = ""
    @State private var nature: ExpenseNature?
    @State private var selectedValues: Set<ValueTag> = []
    @State private var emotionalTrigger: String = ""
    @State private var note: String = ""

    @State private var showHavePause = false  // 冲动时弹"已拥有清单"冷静期
    @Query private var haves: [AlreadyHaveItem] = []     // 已拥有清单，用于对比提醒

    @FocusState private var amountFocused: Bool

    /// 当前币种代码（从 AppSettings 读取，用于金额显示）
    private var currentCurrencyCode: String {
        CurrencyService.shared.currentCurrency(in: modelContext)
    }

    enum FlowStep: Int, CaseIterable {
        case amount
        case question1  // 主动选择 vs 冲动驱动 vs 必需品
        case question2  // 价值观标签
        case question3  // 情绪触发点（仅冲动时）
        case noteStep   // 笔记输入（任何情况，可跳过）
        case done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.paper.ignoresSafeArea()

                VStack {
                    switch step {
                    case .amount:
                        amountStep
                    case .question1:
                        question1Step
                    case .question2:
                        question2Step
                    case .question3:
                        question3Step
                    case .noteStep:
                        noteStepView
                    case .done:
                        doneStep
                    }
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignTokens.ash)
                }
            }
            .sheet(isPresented: $showHavePause) {
                havePauseView
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var stepTitle: LocalizedStringKey {
        switch step {
        case .amount:       return "New Expense"
        case .question1:    return "Question 1 of 3"
        case .question2:    return "Question 2 of 3"
        case .question3:    return "Question 3 of 3"
        case .noteStep:     return "Note"
        case .done:         return ""
        }
    }

    // MARK: - Step: Amount

    private var amountStep: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            Spacer()

            Text("How much?")
                .serifTitle(24, weight: .regular)
                .foregroundStyle(DesignTokens.ash)

            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(CurrencyService.shared.symbol(for: currentCurrencyCode))
                    .serifTitle(40, weight: .bold)
                    .foregroundStyle(DesignTokens.ash)

                TextField("0.00", text: $amount)
                    .serifTitle(48, weight: .bold)
                    .foregroundStyle(DesignTokens.ink)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 200)
                    .focused($amountFocused)
            }

            Spacer()

            Button {
                proceedToQuestions()
            } label: {
                Text("Continue")
                    .sansBody(17, weight: .semibold)
                    .foregroundStyle(DesignTokens.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .background(amount.isEmpty ? DesignTokens.stoneDim : DesignTokens.bronze)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .disabled(amount.isEmpty)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .onAppear { amountFocused = true }
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - Step: Q1 主动选择 vs 冲动驱动

    private var question1Step: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()

            Text("Was this a deliberate choice, or driven by impulse?")
                .serifTitle(22, weight: .regular)
                .foregroundStyle(DesignTokens.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.lg)

            VStack(spacing: DesignTokens.Spacing.md) {
                choiceButton(
                    title: "Chosen",
                    subtitle: "A deliberate, intentional decision",
                    color: DesignTokens.verdigris
                ) {
                    nature = .chosen
                    advanceStep()
                }

                choiceButton(
                    title: "Impulse",
                    subtitle: "Driven by emotion or habit",
                    color: DesignTokens.rust
                ) {
                    nature = .impulse
                    // 先弹"已拥有清单"冷静期 — 设计文档要求的"Premeditatio Malorum/逆向"
                    showHavePause = true
                }

                choiceButton(
                    title: "Necessity",
                    subtitle: "A fixed bill or essential need",
                    color: DesignTokens.ash
                ) {
                    nature = .necessity
                    advanceStep()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer()

            skipButton
        }
    }

    // MARK: - Step: Q2 价值观标签

    private var question2Step: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()

            Text("Which value does this serve?")
                .serifTitle(22, weight: .regular)
                .foregroundStyle(DesignTokens.ink)
                .multilineTextAlignment(.center)

            Text("Select all that apply")
                .sansBody(14)
                .foregroundStyle(DesignTokens.ash)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.md) {
                ForEach(ValueTag.allCases) { tag in
                    Button {
                        toggleValue(tag)
                    } label: {
                        HStack {
                            Image(systemName: tag.systemImage)
                            Text(tag.localizedName)
                        }
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(selectedValues.contains(tag) ? DesignTokens.paper : DesignTokens.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(selectedValues.contains(tag) ? DesignTokens.bronze : DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer()

            // Continue / Skip
            HStack(spacing: DesignTokens.Spacing.md) {
                skipButton
                Button {
                    advanceStep()
                } label: {
                    Text("Continue")
                        .sansBody(17, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(DesignTokens.bronze)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - Step: Q3 情绪触发点

    private var question3Step: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()

            Text("What triggered this impulse?")
                .serifTitle(22, weight: .regular)
                .foregroundStyle(DesignTokens.ink)
                .multilineTextAlignment(.center)

            Text("One sentence. No deep analysis.")
                .sansBody(14)
                .foregroundStyle(DesignTokens.ash)

            TextEditor(text: $emotionalTrigger)
                .sansBody(16)
                .foregroundStyle(DesignTokens.ink)
                .padding(DesignTokens.Spacing.md)
                .background(DesignTokens.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .frame(minHeight: 100)
                .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer()

            HStack(spacing: DesignTokens.Spacing.md) {
                skipButton
                Button {
                    saveExpense()
                } label: {
                    Text("Save")
                        .sansBody(17, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(DesignTokens.bronze)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - Step: Note 笔记输入

    private var noteStepView: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()

            Text("Any note? (Optional)")
                .serifTitle(22, weight: .regular)
                .foregroundStyle(DesignTokens.ink)
                .multilineTextAlignment(.center)

            Text("Merchant, category, context…")
                .sansBody(14)
                .foregroundStyle(DesignTokens.ash)

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("e.g. Coffee with Sam")
                        .sansBody(16)
                        .foregroundStyle(DesignTokens.ash.opacity(0.6))
                        .padding(.top, DesignTokens.Spacing.md + 4)
                        .padding(.leading, DesignTokens.Spacing.md + 4)
                }
                TextEditor(text: $note)
                    .sansBody(16)
                    .foregroundStyle(DesignTokens.ink)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .frame(minHeight: 100)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer()

            HStack(spacing: DesignTokens.Spacing.md) {
                skipButton
                Button {
                    saveExpense()
                } label: {
                    Text("Save")
                        .sansBody(17, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(DesignTokens.bronze)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - 冲动时的"已拥有清单"冷静期

    private var havePauseView: some View {
        NavigationStack {
            ZStack {
                DesignTokens.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(DesignTokens.rust)
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                                Text("Before you record this impulse…")
                                    .serifTitle(20, weight: .semibold)
                                    .foregroundStyle(DesignTokens.ink)
                                Text("Take one breath. Remember what you already have.")
                                    .sansBody(14)
                                    .foregroundStyle(DesignTokens.ash)
                            }
                        }
                        .padding(.top, DesignTokens.Spacing.xl)

                        if haves.isEmpty {
                            VStack(spacing: DesignTokens.Spacing.md) {
                                Image(systemName: "checkmark.seal")
                                    .font(.system(size: 36))
                                    .foregroundStyle(DesignTokens.ash.opacity(0.5))
                                Text("Your \"Already Have\" list is empty. Start there later — for now, continue if you truly need this.")
                                    .sansBody(14)
                                    .foregroundStyle(DesignTokens.ash)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.xl)
                        } else {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                                Text("You already have:")
                                    .sansBody(13, weight: .semibold)
                                    .foregroundStyle(DesignTokens.ash)
                                ForEach(Array(haves.prefix(8))) { have in
                                    HStack(spacing: DesignTokens.Spacing.sm) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(DesignTokens.bronze.opacity(0.85))
                                        Text(have.title)
                                            .sansBody(15)
                                            .foregroundStyle(DesignTokens.ink)
                                        Spacer()
                                    }
                                    .padding(.vertical, DesignTokens.Spacing.xs)
                                }
                            }
                        }

                        Spacer(minLength: DesignTokens.Spacing.xxl)

                        VStack(spacing: DesignTokens.Spacing.md) {
                            Button {
                                // 仍然决定买 — 继续流程
                                showHavePause = false
                                advanceStep()
                            } label: {
                                Text("Still want it. Continue.")
                                    .sansBody(16, weight: .semibold)
                                    .foregroundStyle(DesignTokens.paper)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DesignTokens.Spacing.md)
                                    .background(DesignTokens.rust)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            }

                            Button {
                                // 冷静后放弃
                                showHavePause = false
                                dismiss()
                            } label: {
                                Text("I don't need it. Cancel.")
                                    .sansBody(15, weight: .medium)
                                    .foregroundStyle(DesignTokens.verdigris)
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                }
            }
            .navigationTitle("A Moment of Reflection")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Step: Done

    private var doneStep: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            ControlRingLoading(size: 60)
                .opacity(0)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.verdigris)

            Text("Recorded")
                .serifTitle(24, weight: .bold)
                .foregroundStyle(DesignTokens.ink)

            Text("Every honest reflection is a small victory.")
                .sansBody(15)
                .foregroundStyle(DesignTokens.ash)

            Spacer()
        }
        .onAppear {
            // 短暂展示后关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }

    // MARK: - 通用组件

    private func choiceButton(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .serifTitle(20, weight: .semibold)
                Text(subtitle)
                    .sansBody(13)
            }
            .foregroundStyle(DesignTokens.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.lg)
            .background(DesignTokens.card)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(color, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    private var skipButton: some View {
        Button {
            handleSkip()
        } label: {
            Text("Skip")
                .sansBody(15)
                .foregroundStyle(DesignTokens.ash)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.md)
        }
    }

    // MARK: - 流程逻辑

    private func proceedToQuestions() {
        withAnimation { step = .question1 }
    }

    private func advanceStep() {
        withAnimation {
            switch step {
            case .question1:
                step = .question2
            case .question2:
                if nature == .impulse {
                    step = .question3
                } else {
                    step = .noteStep
                }
            case .question3:
                step = .noteStep
            case .noteStep:
                saveExpense()
            default:
                break
            }
        }
    }

    private func handleSkip() {
        withAnimation {
            switch step {
            case .question1:
                nature = nil
                step = .question2
            case .question2:
                selectedValues.removeAll()
                if nature == .impulse {
                    step = .question3
                } else {
                    step = .noteStep
                }
            case .question3:
                emotionalTrigger = ""
                step = .noteStep
            case .noteStep:
                note = ""
                saveExpense()
            default:
                break
            }
        }
    }

    private func toggleValue(_ tag: ValueTag) {
        if selectedValues.contains(tag) {
            selectedValues.remove(tag)
        } else {
            selectedValues.insert(tag)
        }
    }

    private func saveExpense() {
        let expense = Expense(
            amount: Double(amount) ?? 0,
            note: note,
            nature: nature,
            values: Array(selectedValues),
            emotionalTrigger: emotionalTrigger.isEmpty ? nil : emotionalTrigger
        )
        modelContext.insert(expense)
        try? modelContext.save()

        withAnimation {
            step = .done
        }
    }
}
