import SwiftUI
import SwiftData

/// 页面 1 — Onboarding（FR-07 P1：1 屏极简引导）
/// 品牌句 + 隐私一行 + 「开始」；不做多屏教学、不解释哲学概念
/// 与启动图共享同一视觉语言，实现无缝衔接
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    @State private var showContent = false

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

                VStack(spacing: DesignTokens.Spacing.xl) {
                    ControlRingLoading(size: 92)

                    VStack(spacing: DesignTokens.Spacing.md) {
                        Text("Some money you spend feels right.")
                            .serifTitle(26, weight: .regular)
                            .foregroundStyle(DesignTokens.stone)

                        Text("Some you regret the moment it's gone.")
                            .serifTitle(26, weight: .regular)
                            .foregroundStyle(DesignTokens.bronze)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Spacing.xl)

                    Text("Three quick questions right after you spend — about 10 seconds per expense.")
                        .sansBody(15)
                        .foregroundStyle(DesignTokens.ash)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.xl)

                    // 隐私一行（不做第二屏）
                    HStack(spacing: DesignTokens.Spacing.md) {
                        privacyPill(icon: "iphone", text: "On-device")
                        privacyPill(icon: "icloud.slash", text: "No server")
                        privacyPill(icon: "wifi.slash", text: "Offline")
                    }
                }
                .opacity(showContent ? 1 : 0)

                Spacer()

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
            withAnimation(.easeInOut(duration: 0.9).delay(0.2)) {
                showContent = true
            }
        }
    }

    // MARK: - 组件

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
