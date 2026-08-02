import SwiftUI
import SwiftData

/// 页面 1 — Onboarding 隐私承诺页
/// 深色径向渐变背景 + 控制环加载态 + 斯多葛短句 + "开始"按钮
/// 与启动图共享同一视觉语言，实现无缝衔接
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    @State private var showContent = false

    private var stoicQuote: String {
        String(localized: "You have power over your mind — not outside events.\nRealize this, and you will find strength.")
    }

    var body: some View {
        ZStack {
            // 径向渐变背景 — 与图标/启动图同一视觉语言
            RadialGradient(
                colors: [DesignTokens.gradientStart, DesignTokens.gradientEnd],
                center: .center,
                startRadius: 0,
                endRadius: UIScreen.main.bounds.width * 0.7
            )
            .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.xxl) {
                Spacer()

                // 控制环加载态
                ControlRingLoading(size: 100)
                    .opacity(showContent ? 1 : 0)

                // 斯多葛短句
                VStack(spacing: DesignTokens.Spacing.md) {
                    Text(stoicQuote)
                        .serifTitle(24, weight: .regular)
                        .foregroundStyle(DesignTokens.stone)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.xl)

                    Text("— Inspired by Marcus Aurelius")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                Spacer()

                // 隐私承诺 — 胶囊式标签
                HStack(spacing: DesignTokens.Spacing.md) {
                    privacyPill(icon: "iphone", text: "On-device")
                    privacyPill(icon: "icloud.slash", text: "No server")
                    privacyPill(icon: "wifi.slash", text: "Offline")
                }
                .opacity(showContent ? 1 : 0)

                // 开始按钮
                Button {
                    completeOnboarding()
                } label: {
                    Text("Begin")
                        .sansBody(17, weight: .semibold)
                        .foregroundStyle(DesignTokens.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(DesignTokens.bronze)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.bottom, DesignTokens.Spacing.xl)
                .opacity(showContent ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).delay(0.3)) {
                showContent = true
            }
        }
    }

    // MARK: - 隐私胶囊标签

    private func privacyPill(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .sansBody(12, weight: .medium)
        }
        .foregroundStyle(DesignTokens.ash)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.stone.opacity(0.08))
        .clipShape(Capsule())
    }

    private func completeOnboarding() {
        if let appSettings = settings.first {
            appSettings.hasCompletedOnboarding = true
        } else {
            let newSettings = AppSettings()
            newSettings.hasCompletedOnboarding = true
            modelContext.insert(newSettings)
        }
        try? modelContext.save()
    }
}
