import SwiftUI

/// 页面 8 — Resilience 财务韧性模拟
/// 场景 pills 切换 + 简洁结果卡 + 斯多葛语录 + 端侧 AI 建议卡 + Adjust numbers 触发输入
/// 免费版仅 Income pause 场景；付费版解锁 Shock cost / Early retirement + AI counsel
struct ResilienceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var savings: String = ""
    @State private var monthlyIncome: String = ""
    @State private var monthlyExpenses: String = ""
    @State private var aiAdvice: ResilienceAdviceResult?
    @State private var isLoadingAI = false
    @State private var showPaywall = false
    @State private var showAdjustSheet = false
    @State private var selectedScenario: Scenario = .incomePause

    private var store = StoreKitService.shared

    enum Scenario: String, CaseIterable {
        case incomePause = "Income interruption"
        case shockCost = "Shock cost"
        case earlyRetirement = "Early retirement"

        var label: LocalizedStringKey {
            switch self {
            case .incomePause: return "Income pause"
            case .shockCost: return "Shock cost"
            case .earlyRetirement: return "Early retirement"
            }
        }

        var isFree: Bool { self == .incomePause }
    }

    private var runwayMonths: Double {
        let s = Double(savings) ?? 0
        let e = Double(monthlyExpenses) ?? 1
        return e > 0 ? s / e : 0
    }

    private var runwayText: String {
        if runwayMonths >= 12 {
            return String(format: "%.1f years", runwayMonths / 12)
        } else {
            return String(format: "%.1f months", runwayMonths)
        }
    }

    private var coveredText: String {
        String(format: String(localized: "%@ covered"), runwayText)
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
                    // 场景 pills
                    scenarioPills

                    // 结果卡片
                    if Double(savings) ?? 0 > 0 {
                        resultCard
                    } else {
                        emptyHint
                    }

                    // 斯多葛语录
                    quoteCard

                    // 端侧 AI 建议卡
                    counselCard

                    // 调整参数按钮
                    adjustButton
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.md)
                .padding(.bottom, 100)
            }
            .background(DesignTokens.paper)
            .navigationTitle("Resilience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignTokens.ash)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showAdjustSheet) {
                adjustSheet
            }
        }
    }

    // MARK: - 场景 pills

    private var scenarioPills: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(Scenario.allCases, id: \.self) { s in
                Button {
                    if s.isFree {
                        selectedScenario = s
                    } else if store.isPremium {
                        selectedScenario = s
                    } else {
                        showPaywall = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(s.label)
                            .sansBody(13, weight: .medium)
                        if !s.isFree && !store.isPremium {
                            Image(systemName: "lock")
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 6)
                    .foregroundStyle(selectedScenario == s ? DesignTokens.paper : DesignTokens.ash)
                    .background(selectedScenario == s ? DesignTokens.ink : DesignTokens.card)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - 结果卡片

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("At current savings")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)
            Text(coveredText)
                .serifTitle(20, weight: .semibold)
                .foregroundStyle(DesignTokens.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("At current savings")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)
            Text("Enter your numbers to begin")
                .serifTitle(16, weight: .regular)
                .foregroundStyle(DesignTokens.ash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - 斯多葛语录

    private var quoteCard: some View {
        Text(dailyQuote.text)
            .serifTitle(12, weight: .regular)
            .foregroundStyle(DesignTokens.ash)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 端侧 AI 建议卡

    private var counselCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if let advice = aiAdvice {
                Text(advice.advice)
                    .serifTitle(15, weight: .regular)
                    .foregroundStyle(DesignTokens.ink)
                if !advice.focusArea.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "scope")
                            .font(.caption2)
                        Text("Focus")
                            .sansBody(12, weight: .medium)
                        Text(verbatim: "·")
                        Text(verbatim: advice.focusArea)
                            .sansBody(12)
                    }
                    .foregroundStyle(DesignTokens.ash)
                    .textCase(.lowercase)
                }
            } else if isLoadingAI {
                HStack {
                    ProgressView()
                    Text("Finding wisdom...")
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ash)
                }
            } else {
                Button {
                    if store.isPremium {
                        Task { await generateAdvice() }
                    } else {
                        showPaywall = true
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "text.quote")
                            .foregroundStyle(DesignTokens.bronze)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On-device counsel")
                                .sansBody(15, weight: .medium)
                                .foregroundStyle(DesignTokens.ink)
                            Text("Personalized, generated on your phone")
                                .sansBody(13)
                                .foregroundStyle(DesignTokens.ash)
                        }
                        Spacer()
                        Image(systemName: store.isPremium ? "chevron.right" : "lock")
                            .foregroundStyle(DesignTokens.ash)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - 调整参数按钮

    private var adjustButton: some View {
        Button {
            showAdjustSheet = true
        } label: {
            Text("Adjust numbers")
                .sansBody(14, weight: .medium)
                .foregroundStyle(DesignTokens.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(DesignTokens.ink, lineWidth: 1.4)
                )
        }
    }

    // MARK: - 调整参数 sheet

    private var adjustSheet: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.lg) {
                inputField(title: "Savings", value: $savings, placeholder: "10,000")
                inputField(title: "Monthly Income", value: $monthlyIncome, placeholder: "5,000")
                inputField(title: "Monthly Expenses", value: $monthlyExpenses, placeholder: "3,000")
                Spacer()
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.paper)
            .navigationTitle("Adjust Numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showAdjustSheet = false }
                        .foregroundStyle(DesignTokens.bronze)
                }
            }
        }
    }

    private func inputField(title: LocalizedStringKey, value: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .sansBody(13, weight: .medium)
                .foregroundStyle(DesignTokens.ash)

            HStack {
                Text(CurrencyService.shared.symbol(for: CurrencyService.shared.currentCurrency(in: modelContext)))
                    .sansBody(16)
                    .foregroundStyle(DesignTokens.ash)
                TextField(placeholder, text: value)
                    .sansBody(16)
                    .foregroundStyle(DesignTokens.ink)
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    // MARK: - 逻辑

    private func generateAdvice() async {
        guard store.isPremium else {
            showPaywall = true
            return
        }
        isLoadingAI = true
        aiAdvice = await FoundationModelsService.shared.generateResilienceAdvice(
            savings: Double(savings) ?? 0,
            monthlyIncome: Double(monthlyIncome) ?? 0,
            monthlyExpenses: Double(monthlyExpenses) ?? 0,
            scenario: selectedScenario.rawValue
        )
        isLoadingAI = false
    }
}
