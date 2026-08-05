import SwiftUI
import StoreKit

/// 页面 9 — Paywall 统一付费墙
/// 所有锁定功能点击后都跳转到此页面，不做分散的功能内弹窗
/// 常驻深色 UI：不随系统外观切换，强制使用固定深色 token（darkInk/darkStone/darkAsh 等）
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var viewModel = SubscriptionViewModel()
    @State private var isPurchasing = false
    @State private var showPurchaseError = false
    @State private var purchaseErrorText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.darkInk.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.xl) {
                        headerSection
                        featuresSection
                        subscriptionOptions
                        footerSection
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.top, DesignTokens.Spacing.xl)
                    .padding(.bottom, DesignTokens.Spacing.xxl)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(DesignTokens.darkAsh)
                    }
                    .disabled(isPurchasing)
                }
            }
            .alert("Purchase Failed", isPresented: $showPurchaseError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseErrorText)
            }
            .onChange(of: viewModel.isPremium) { _, newValue in
                if newValue {
                    dismiss()
                }
            }
        }
    }

    // MARK: - 标题

    private var headerSection: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ControlRingBadge(progress: 0.75)

            Text("Go Deeper")
                .serifTitle(32, weight: .bold)
                .foregroundStyle(DesignTokens.darkStone)

            Text("Unlock long-term perspective, advanced simulations, and personalized reflection.")
                .sansBody(15)
                .foregroundStyle(DesignTokens.darkAsh)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DesignTokens.Spacing.xl)
    }

    // MARK: - 功能列表

    private var featuresSection: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            featureRow(icon: "shield", title: "Advanced Scenarios", desc: "Multiple resilience simulations")
            featureRow(icon: "text.quote", title: "AI Follow-ups", desc: "Personalized weekly reflections")
            featureRow(icon: "square.grid.2x2", title: "Premium Card Designs", desc: "More share card templates")
            featureRow(icon: "clock", title: "Cooldown Reminders", desc: "24h / 72h impulse delay")
        }
    }

    private func featureRow(icon: String, title: LocalizedStringKey, desc: LocalizedStringKey) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DesignTokens.bronze)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .sansBody(15, weight: .semibold)
                    .foregroundStyle(DesignTokens.darkStone)
                Text(desc)
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.darkAsh)
            }

            Spacer()

            Image(systemName: "checkmark")
                .foregroundStyle(DesignTokens.verdigris)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 订阅选项

    private var subscriptionOptions: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // 已订阅态：展示当前订阅 + 管理入口
            if viewModel.isPremium, let status = viewModel.subscriptionStatus {
                activeSubscriptionCard(status: status)
            } else if viewModel.products.isEmpty {
                // 无商品（StoreKit 未加载或本地配置缺失）：占位卡展示价目
                placeholderCard(price: "$0.99", period: "first month", badge: "Intro Offer", featured: true)
                placeholderCard(price: "$39.99", period: "per year", badge: "Best Value", featured: false)
                placeholderCard(price: "$4.99", period: "per month", badge: nil, featured: false)
            } else {
                // 首月体验
                if let intro = viewModel.products.first(where: { $0.id == StoreKitService.ProductID.intro }) {
                    subscriptionCard(
                        product: intro,
                        badge: "Intro Offer",
                        period: "first month",
                        isFeatured: true
                    )
                }

                // 年付
                if let yearly = viewModel.products.first(where: { $0.id == StoreKitService.ProductID.yearly }) {
                    subscriptionCard(
                        product: yearly,
                        badge: "Best Value",
                        period: "per year",
                        isFeatured: false
                    )
                }

                // 月付
                if let monthly = viewModel.products.first(where: { $0.id == StoreKitService.ProductID.monthly }) {
                    subscriptionCard(
                        product: monthly,
                        badge: nil,
                        period: "per month",
                        isFeatured: false
                    )
                }
            }
        }
    }

    private func subscriptionCard(
        product: Product,
        badge: LocalizedStringKey?,
        period: LocalizedStringKey,
        isFeatured: Bool
    ) -> some View {
        Button {
            Task { await handlePurchase(product) }
        } label: {
            cardContent(
                priceText: product.displayPrice,
                period: period,
                badge: badge,
                featured: isFeatured
            )
        }
        .disabled(isPurchasing)
    }

    private func placeholderCard(price: String, period: LocalizedStringKey, badge: LocalizedStringKey?, featured: Bool) -> some View {
        cardContent(priceText: price, period: period, badge: badge, featured: featured)
    }

    private func cardContent(priceText: String, period: LocalizedStringKey, badge: LocalizedStringKey?, featured: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let badge {
                    Text(badge)
                        .sansBody(11, weight: .bold)
                        .foregroundStyle(featured ? DesignTokens.darkInk : DesignTokens.bronze)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(featured ? DesignTokens.bronze.opacity(0.3) : DesignTokens.bronze.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(priceText)
                    .serifTitle(24, weight: .bold)
                    .foregroundStyle(DesignTokens.darkStone)
                Text(period)
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.darkAsh)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(DesignTokens.darkAsh)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.darkCard)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .stroke(featured ? DesignTokens.bronze : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    /// 已订阅卡片：显示当前套餐 + 到期日 + Manage Subscription 入口
    private func activeSubscriptionCard(status: StoreKitService.SubscriptionStatus) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(DesignTokens.verdigris)
                Text("Premium Active")
                    .sansBody(16, weight: .semibold)
                    .foregroundStyle(DesignTokens.darkStone)
                Spacer()
            }

            if let name = viewModel.activeProductDisplayName {
                Text(name)
                    .sansBody(14)
                    .foregroundStyle(DesignTokens.darkAsh)
            }

            if let exp = status.expirationDate {
                Text("Renews \(exp.formatted(date: .abbreviated, time: .omitted))")
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.darkAsh)
            }

            Button {
                openURL(LegalLinks.manageSubscription)
            } label: {
                Text("Manage Subscription")
                    .sansBody(14, weight: .semibold)
                    .foregroundStyle(DesignTokens.bronze)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.bronze.opacity(0.6), lineWidth: 1)
                    )
            }
            .padding(.top, DesignTokens.Spacing.xs)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.darkCard)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .stroke(DesignTokens.verdigris.opacity(0.5), lineWidth: 1.5)
        )
    }

    // MARK: - 购买流程

    private func handlePurchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }

        let success = await viewModel.purchase(product)
        if !success, let error = viewModel.purchaseError {
            purchaseErrorText = error
            showPurchaseError = true
        }
        // 成功 → onChange(isPremium) 自动 dismiss
    }

    // MARK: - 底部（含苹果审核必需的披露条款）

    private var footerSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            // 恢复购买
            Button {
                Task { await viewModel.restore() }
            } label: {
                Text("Restore Purchases")
                    .sansBody(14)
                    .foregroundStyle(DesignTokens.darkAsh)
            }
            .disabled(isPurchasing)

            // 条款链接
            HStack(spacing: DesignTokens.Spacing.md) {
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.darkAsh)
                Text("·").foregroundStyle(DesignTokens.darkAsh)
                Link("Terms of Use", destination: LegalLinks.termsOfUse)
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.darkAsh)
            }

            // 自动续订披露（苹果 Guideline 3.1.2 必需）
            Text("Cancel anytime. Payment is charged to your Apple ID. Subscription auto-renews unless cancelled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions.")
                .sansBody(11)
                .foregroundStyle(DesignTokens.darkAsh.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.sm)
        }
    }
}
