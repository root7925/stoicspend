import SwiftUI

// MARK: - 分享卡片模板

enum CardTemplate: Int, CaseIterable, Identifiable {
    case inkClassic    // 免费：深色经典 + 青铜
    case parchment     // 免费：羊皮纸 + 灰墨
    case sunrise       // 付费：渐变暖日
    case nightSky      // 付费：深蓝夜空

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .inkClassic: return "Classic"
        case .parchment:  return "Parchment"
        case .sunrise:    return "Sunrise"
        case .nightSky:   return "Night Sky"
        }
    }

    /// 是否为付费模板
    var isPremium: Bool {
        switch self {
        case .inkClassic, .parchment: return false
        case .sunrise, .nightSky:     return true
        }
    }
}

/// 页面 6 — Share Card 分享卡片
/// 深色背景语录卡片，提取复盘中的一句话，可保存/分享
/// 免费版 2 个模板，付费版 4 个模板（Sunrise + NightSky 解锁）
struct ShareCardView: View {
    let quote: String

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var showSavedToast = false
    @State private var savedImage: UIImage?
    @State private var selectedTemplate: CardTemplate = .inkClassic
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.ink.ignoresSafeArea()

                VStack(spacing: DesignTokens.Spacing.xl) {
                    Spacer()

                    // 卡片预览（模板动态切换）
                    cardForTemplate(selectedTemplate)

                    // 模板选择器（横滑）
                    templatePicker

                    Spacer()

                    // 操作按钮
                    actionButtons
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.xl)

                // 保存成功提示
                if showSavedToast {
                    VStack {
                        Spacer()
                        Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                            .sansBody(15, weight: .medium)
                            .foregroundStyle(DesignTokens.stone)
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                            .padding(.vertical, DesignTokens.Spacing.md)
                            .background(DesignTokens.darkCard)
                            .clipShape(Capsule())
                            .padding(.bottom, DesignTokens.Spacing.xxl)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignTokens.stone)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = savedImage {
                    ShareSheet(items: [image])
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - 模板选择器

    private var templatePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(CardTemplate.allCases) { template in
                    Button {
                        selectTemplate(template)
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(previewColor(for: template))
                                .frame(width: 44, height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedTemplate == template ? DesignTokens.bronze : Color.clear, lineWidth: 2)
                                )
                                .overlay {
                                    if template.isPremium && !StoreKitService.shared.isPremium {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                            Text(template.name)
                                .sansBody(11, weight: selectedTemplate == template ? .semibold : .regular)
                                .foregroundStyle(selectedTemplate == template ? DesignTokens.bronze : DesignTokens.ash)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 80)
    }

    private func previewColor(for template: CardTemplate) -> Color {
        switch template {
        case .inkClassic: return DesignTokens.darkCard
        case .parchment:  return Color(red: 0.93, green: 0.89, blue: 0.81)
        case .sunrise:    return Color(red: 0.95, green: 0.60, blue: 0.50)
        case .nightSky:   return Color(red: 0.10, green: 0.13, blue: 0.35)
        }
    }

    private func selectTemplate(_ template: CardTemplate) {
        if template.isPremium && !StoreKitService.shared.isPremium {
            showPaywall = true
            return
        }
        withAnimation { selectedTemplate = template }
    }

    // MARK: - 模板动态卡片

    @ViewBuilder
    private func cardForTemplate(_ template: CardTemplate) -> some View {
        let base = VStack(spacing: DesignTokens.Spacing.lg) {
            ControlRingBadge(progress: 0.7)
            Text("\"\(quote)\"")
                .serifTitle(22, weight: .regular)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(accentColor(for: template).opacity(0.4))
                .frame(width: 40, height: 1)
            VStack(spacing: 2) {
                Text("Stoic Spend")
                    .serifTitle(14, weight: .semibold)
                    .foregroundStyle(accentColor(for: template))
                Text("Control what you can.")
                    .sansBody(11)
                    .foregroundStyle(secondaryColor(for: template))
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .foregroundStyle(primaryColor(for: template))

        switch template {
        case .inkClassic:
            base
                .background(DesignTokens.darkCard)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        case .parchment:
            base
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .fill(Color(red: 0.93, green: 0.89, blue: 0.81))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .stroke(Color(red: 0.78, green: 0.70, blue: 0.55), lineWidth: 1)
                )
        case .sunrise:
            base
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.78, blue: 0.55),
                                    Color(red: 0.90, green: 0.45, blue: 0.45),
                                    Color(red: 0.55, green: 0.35, blue: 0.60)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        case .nightSky:
            base
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.08, green: 0.10, blue: 0.30),
                                        Color(red: 0.20, green: 0.18, blue: 0.42)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        // 星星点
                        VStack {
                            HStack {
                                Circle().fill(.white.opacity(0.6)).frame(width: 2, height: 2)
                                    .padding(24)
                                Spacer()
                                Circle().fill(.white.opacity(0.4)).frame(width: 1.5, height: 1.5)
                                    .padding(40)
                            }
                            Spacer()
                            HStack {
                                Spacer()
                                Circle().fill(.white.opacity(0.7)).frame(width: 2.5, height: 2.5)
                                    .padding(32)
                            }
                        }
                    }
                )
        }
    }

    private func primaryColor(for template: CardTemplate) -> Color {
        switch template {
        case .inkClassic: return DesignTokens.stone
        case .parchment:  return DesignTokens.ink
        case .sunrise:    return .white
        case .nightSky:   return .white.opacity(0.92)
        }
    }

    private func secondaryColor(for template: CardTemplate) -> Color {
        switch template {
        case .inkClassic: return DesignTokens.ash
        case .parchment:  return DesignTokens.ash
        case .sunrise:    return .white.opacity(0.8)
        case .nightSky:   return .white.opacity(0.7)
        }
    }

    private func accentColor(for template: CardTemplate) -> Color {
        switch template {
        case .inkClassic: return DesignTokens.bronze
        case .parchment:  return Color(red: 0.55, green: 0.42, blue: 0.25)
        case .sunrise:    return .white
        case .nightSky:   return Color(red: 0.85, green: 0.75, blue: 1.0)
        }
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // 保存到相册
            Button {
                saveCardToPhotos()
            } label: {
                Label("Save Image", systemImage: "square.and.arrow.down")
                    .sansBody(16, weight: .semibold)
                    .foregroundStyle(DesignTokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .background(DesignTokens.bronze)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }

            // 分享
            Button {
                shareCard()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .sansBody(15)
                    .foregroundStyle(DesignTokens.stone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .background(DesignTokens.ink)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.stoneDim, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
        }
    }

    // MARK: - 逻辑

    /// 使用 ImageRenderer 将卡片渲染为 UIImage 并保存到相册
    private func saveCardToPhotos() {
        let content = cardForTemplate(selectedTemplate).frame(width: 300, height: 460)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else { return }

        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        savedImage = image

        withAnimation {
            showSavedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedToast = false
            }
        }
    }

    private func shareCard() {
        let content = cardForTemplate(selectedTemplate).frame(width: 300, height: 460)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        savedImage = renderer.uiImage
        showShareSheet = true
    }
}

// MARK: - ShareSheet UIKit 桥接

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
