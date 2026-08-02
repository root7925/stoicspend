import SwiftUI
import StoreKit

/// 页面 9 — Paywall 统一付费墙
/// 所有锁定功能点击后都跳转到此页面，不做分散的功能内弹窗
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = StoreKitService.shared

    @State private var selectedProduct: Product?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.ink.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.xl) {
                        // 标题区
                        headerSection

                        // 功能列表
                        featuresSection

                        // 订阅选项
                        subscriptionOptions

                        // 底部信息
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
                            .foregroundStyle(DesignTokens.ash)
                    }
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
                .foregroundStyle(DesignTokens.stone)

            Text("Unlock long-term perspective, advanced simulations, and personalized reflection.")
                .sansBody(15)
                .foregroundStyle(DesignTokens.ash)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DesignTokens.Spacing.xl)
    }

    // MARK: - 功能列表

    private var featuresSection: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            featureRow(icon: "chart.bar", title: "Historical Trends", desc: "Monthly & yearly comparisons")
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
                    .foregroundStyle(DesignTokens.stone)
                Text(desc)
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)
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
            // 首月体验
            if let intro = store.products.first(where: { $0.id == "stoicspend.intro" }) {
                subscriptionCard(
                    product: intro,
                    badge: "Intro Offer",
                    priceText: "$0.99",
                    period: "first month",
                    isFeatured: true
                )
            }

            // 年付
            if let yearly = store.products.first(where: { $0.id == "stoicspend.yearly" }) {
                subscriptionCard(
                    product: yearly,
                    badge: "Best Value",
                    priceText: "$39.99",
                    period: "per year",
                    isFeatured: false
                )
            }

            // 月付
            if let monthly = store.products.first(where: { $0.id == "stoicspend.monthly" }) {
                subscriptionCard(
                    product: monthly,
                    badge: nil,
                    priceText: "$4.99",
                    period: "per month",
                    isFeatured: false
                )
            }

            // 无商品时的占位
            if store.products.isEmpty {
                placeholderCard(price: "$0.99", period: "first month", badge: "Intro Offer", featured: true)
                placeholderCard(price: "$39.99", period: "per year", badge: "Best Value", featured: false)
                placeholderCard(price: "$4.99", period: "per month", badge: nil, featured: false)
            }
        }
    }

    private func subscriptionCard(
        product: Product,
        badge: LocalizedStringKey?,
        priceText: String,
        period: LocalizedStringKey,
        isFeatured: Bool
    ) -> some View {
        Button {
            selectedProduct = product
            Task { try await store.purchase(product)
            }
        } label: {
            cardContent(priceText: priceText, period: period, badge: badge, featured: isFeatured)
        }
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
                        .foregroundStyle(featured ? DesignTokens.ink : DesignTokens.bronze)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(featured ? DesignTokens.bronze.opacity(0.3) : DesignTokens.bronze.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(priceText)
                    .serifTitle(24, weight: .bold)
                    .foregroundStyle(DesignTokens.stone)
                Text(period)
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(DesignTokens.ash)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.darkCard)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .stroke(featured ? DesignTokens.bronze : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - 底部

    private var footerSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                Task { await store.restorePurchases()
                }
            } label: {
                Text("Restore Purchases")
                    .sansBody(14)
                    .foregroundStyle(DesignTokens.ash)
            }

            Text("Cancel anytime. Payment charged to your Apple ID.")
                .sansBody(12)
                .foregroundStyle(DesignTokens.ash.opacity(0.7))
        }
    }
}
