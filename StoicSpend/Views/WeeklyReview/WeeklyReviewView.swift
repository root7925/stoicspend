import SwiftUI
import SwiftData

/// 页面 5 — Weekly Review 每周斯多葛式复盘
/// 仿《沉思录》三段式结构 + 付费版 AI 追问
struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \WeeklyReview.createdAt, order: .reverse)
    private var reviews: [WeeklyReview]

    @Query(sort: \Expense.date, order: .reverse)
    private var allExpenses: [Expense]

    @State private var whatWentRight = ""
    @State private var whatDeviated = ""
    @State private var virtueToPractice = ""
    @State private var aiFollowUp: WeeklyFollowUpResult?
    @State private var followUpReply: String?       // AI 多轮追问回复
    @State private var userReplyInput: String = ""  // 用户输入的回复
    @State private var isLoadingAI = false
    @State private var isLoadingReply = false
    @State private var showShareCard = false
    @State private var showPaywall = false

    private var store = StoreKitService.shared

    /// 是否仍可追问（受 maxFollowUpTurns=1 限制）
    private var canAskFollowUp: Bool {
        aiFollowUp != nil && followUpReply == nil && FoundationModelsService.shared.canContinueFollowUp
    }

    private var weekStart: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    }

    private var recentExpenses: [Expense] {
        allExpenses.filter { $0.date >= weekStart }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    // 引言
                    introSection

                    // Q1
                    reviewQuestion(
                        number: "I",
                        question: "What financial decision did I get right this week?",
                        placeholder: "A choice that aligned with your values...",
                        text: $whatWentRight
                    )

                    // Q2
                    reviewQuestion(
                        number: "II",
                        question: "Which purchase drifted from my values? What did I learn?",
                        placeholder: "An expense that surprised you...",
                        text: $whatDeviated
                    )

                    // Q3
                    reviewQuestion(
                        number: "III",
                        question: "What financial virtue do I want to practice next week?",
                        placeholder: "One virtue, one intention...",
                        text: $virtueToPractice
                    )

                    // AI 追问（付费功能）
                    aiFollowUpSection

                    // 保存按钮
                    saveButton
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.md)
            }
            .background(DesignTokens.paper)
            .navigationTitle("Weekly Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        FoundationModelsService.shared.endFollowUpConversation()
                        dismiss()
                    }
                    .foregroundStyle(DesignTokens.ash)
                }
            }
            .sheet(isPresented: $showShareCard) {
                ShareCardView(quote: extractShareQuote())
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - 子视图

    private var introSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "book")
                .font(.title)
                .foregroundStyle(DesignTokens.bronze)

            Text("The unexamined expense is not worth making.")
                .serifTitle(18, weight: .regular)
                .foregroundStyle(DesignTokens.ash)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    private func reviewQuestion(
        number: String,
        question: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(number)
                    .serifTitle(20, weight: .bold)
                    .foregroundStyle(DesignTokens.bronze)
                Text(question)
                    .sansBody(15, weight: .medium)
                    .foregroundStyle(DesignTokens.ink)
            }

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .sansBody(15)
                        .foregroundStyle(DesignTokens.ash.opacity(0.5))
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                }
                TextEditor(text: text)
                    .sansBody(15)
                    .foregroundStyle(DesignTokens.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var aiFollowUpSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "text.quote")
                    .foregroundStyle(DesignTokens.rust)
                Text("Personalized Follow-up")
                    .sansBody(15, weight: .semibold)
                    .foregroundStyle(DesignTokens.ink)
            }

            if let followUp = aiFollowUp {
                // AI 初始追问
                Text(followUp.question)
                    .serifTitle(16, weight: .regular)
                    .foregroundStyle(DesignTokens.ink)
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.stone.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                // 反思角度标签（@Generable 结构化字段）
                if !followUp.focusAngle.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "scope")
                            .font(.caption2)
                        Text("Focus")
                            .sansBody(12, weight: .medium)
                        Text(verbatim: "·")
                        Text(verbatim: followUp.focusAngle)
                            .sansBody(12)
                    }
                    .foregroundStyle(DesignTokens.ash)
                    .textCase(.lowercase)
                }

                // 多轮对话：AI 的回复（如果已生成）
                if let reply = followUpReply {
                    Text(reply)
                        .serifTitle(15, weight: .regular)
                        .foregroundStyle(DesignTokens.ink)
                        .padding(DesignTokens.Spacing.sm)
                        .background(DesignTokens.verdigris.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }

                // 多轮追问输入区（仅当还能追问时显示）
                if canAskFollowUp {
                    followUpInputRow
                } else if isLoadingReply {
                    HStack {
                        ProgressView()
                        Text("Listening...")
                            .sansBody(13)
                            .foregroundStyle(DesignTokens.ash)
                    }
                }
            } else if isLoadingAI {
                HStack {
                    ProgressView()
                    Text("Reflecting on your week...")
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ash)
                }
            } else {
                Button {
                    Task { await generateAI()
                    }
                } label: {
                    Label("Generate Follow-up", systemImage: "sparkles")
                        .sansBody(14, weight: .medium)
                        .foregroundStyle(DesignTokens.paper)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .background(DesignTokens.rust)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    /// 多轮追问输入行 — 用户回复后调用 continueFollowUpConversation
    private var followUpInputRow: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            TextField("Type your reply...", text: $userReplyInput, axis: .vertical)
                .sansBody(14)
                .foregroundStyle(DesignTokens.ink)
                .lineLimit(1...4)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(DesignTokens.paper)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

            Button {
                Task { await sendFollowUpReply()
                }
            } label: {
                Label("Continue reflection", systemImage: "arrow.up.circle.fill")
                    .sansBody(13, weight: .medium)
                    .foregroundStyle(DesignTokens.paper)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .background(userReplyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? DesignTokens.stoneDim : DesignTokens.bronze)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }
            .disabled(userReplyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var saveButton: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Button {
                saveReview()
            } label: {
                Text("Save Reflection")
                    .sansBody(17, weight: .semibold)
                    .foregroundStyle(DesignTokens.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .background(whatWentRight.isEmpty && whatDeviated.isEmpty && virtueToPractice.isEmpty
                        ? DesignTokens.stoneDim : DesignTokens.bronze)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .disabled(whatWentRight.isEmpty && whatDeviated.isEmpty && virtueToPractice.isEmpty)

            if !whatWentRight.isEmpty || !whatDeviated.isEmpty {
                Button {
                    showShareCard = true
                } label: {
                    Label("Share Card", systemImage: "square.and.arrow.up")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.bronze)
                }
            }
        }
        .padding(.bottom, DesignTokens.Spacing.xl)
    }

    // MARK: - 逻辑

    private func generateAI() async {
        guard store.isPremium else {
            showPaywall = true
            return
        }
        isLoadingAI = true
        defer { isLoadingAI = false }
        let lastReview = reviews.first
        aiFollowUp = await FoundationModelsService.shared.generateWeeklyFollowUp(
            recentExpenses: recentExpenses,
            lastReview: lastReview
        )
        // 重置多轮对话状态
        followUpReply = nil
        userReplyInput = ""
    }

    /// 多轮追问：发送用户回复，获取 AI 的下一条追问
    private func sendFollowUpReply() async {
        let input = userReplyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isLoadingReply = true
        defer { isLoadingReply = false }
        let reply = await FoundationModelsService.shared.continueFollowUpConversation(userReply: input)
        if let reply {
            followUpReply = reply
            userReplyInput = ""
        }
    }

    private func saveReview() {
        let review = WeeklyReview(
            weekStart: weekStart,
            weekEnd: .now,
            whatWentRight: whatWentRight,
            whatDeviated: whatDeviated,
            virtueToPractice: virtueToPractice
        )
        // 持久化 AI 追问内容（首条 question；如有追问回复，拼接保存）
        if let followUp = aiFollowUp {
            if let reply = followUpReply {
                review.aiFollowUp = followUp.question + "\n\n" + reply
            } else {
                review.aiFollowUp = followUp.question
            }
            review.aiGeneratedAt = .now
        }
        modelContext.insert(review)
        try? modelContext.save()
        FoundationModelsService.shared.endFollowUpConversation()
        dismiss()
    }

    private func extractShareQuote() -> String {
        if !whatWentRight.isEmpty {
            return whatWentRight
        } else if !virtueToPractice.isEmpty {
            return virtueToPractice
        }
        return String(localized: "Every honest reflection is a small victory.")
    }
}
