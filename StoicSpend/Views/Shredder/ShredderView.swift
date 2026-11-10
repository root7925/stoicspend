import SwiftUI

/// 消费粉碎机 — 冲动消费急救站（FR-08）
/// 流程：输入 → 粉碎动画 → 3 条劝退弹药 → 粉碎成功 / 还是要买
struct ShredderView: View {
    /// 从快记页带入的金额（独立入口时为 0，需用户输入）
    var prefillAmount: Double = 0

    /// 粉碎成功回调 — 快记页场景下连快记一起关闭
    var onShredded: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    @State private var itemName = ""
    @State private var amountText = ""
    @State private var phase: Phase = .input
    @State private var cardOffset: CGFloat = -160
    @State private var cardOpacity: Double = 1
    @State private var stripOffsets: [CGFloat] = [0, 0, 0]
    @State private var stripOpacities: [Double] = [0, 0, 0]
    @State private var lines: [ShredAmmo.Drawn] = []
    @State private var loading = false
    @State private var pickedIndex: Int? = nil

    enum Phase { case input, shredding, result }

    private var amountValue: Double {
        Double(amountText) ?? 0
    }

    private var canShred: Bool { amountValue > 0 && !loading }

    var body: some View {
        VStack(spacing: 0) {
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

            switch phase {
            case .input: inputPhase
            case .shredding: shredMachine
            case .result: resultPhase
            }
        }
        .background(DesignTokens.paper)
        .onAppear {
            if prefillAmount > 0 {
                amountText = String(format: "%.0f", prefillAmount)
            }
        }
    }

    // MARK: - 输入阶段

    private var inputPhase: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()
            Text("⚙️")
                .font(.system(size: 56))
            Text("想买什么？")
                .serifTitle(24)
                .foregroundStyle(DesignTokens.ink)
            Text("说给它，送进粉碎机看看")
                .sansBody(13)
                .foregroundStyle(DesignTokens.ash)

            VStack(spacing: DesignTokens.Spacing.sm) {
                TextField("品名 · 可选", text: $itemName)
                    .sansBody(15)
                    .padding(14)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                TextField("金额", text: $amountText)
                    .sansBody(15, weight: .medium)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .padding(.horizontal, DesignTokens.Spacing.md)

            Button {
                startShredding()
            } label: {
                Text("送进粉碎机")
                    .sansBody(16, weight: .semibold)
                    .foregroundStyle(canShred ? DesignTokens.paper : DesignTokens.ash)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(canShred ? DesignTokens.gold : DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .disabled(!canShred)
            Spacer()
        }
    }

    // MARK: - 粉碎动画阶段

    private var shredMachine: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()

            // 商品卡掉入齿口
            Text(itemName.isEmpty ? "那件东西" : itemName)
                .sansBody(15, weight: .medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(DesignTokens.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(DesignTokens.stoneDim, lineWidth: 1))
                .offset(y: cardOffset)
                .opacity(cardOpacity)

            // 齿口
            Text("⚙️⚙️")
                .font(.system(size: 48))
                .scaleEffect(cardOpacity < 1 ? 1.12 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: cardOpacity)

            // 碎条落下
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignTokens.gold)
                        .frame(width: 8, height: 34)
                        .offset(y: stripOffsets[i])
                        .opacity(stripOpacities[i])
                }
            }
            .frame(height: 60)

            Spacer()
        }
    }

    // MARK: - 结果阶段

    private var resultPhase: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.md) {
                Text("🧵")
                    .font(.system(size: 40))
                    .padding(.top, DesignTokens.Spacing.xl)

                if loading {
                    Text("正在磨刀…")
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ash)
                        .padding(.top, DesignTokens.Spacing.lg)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lineCard(index: index, line: line)
                    }

                    // FR-27 — 对话化追问：哪条最戳你？点选记录机制偏好
                    if !lines.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            Text("哪条最戳你？")
                                .serifTitle(18)
                                .foregroundStyle(DesignTokens.ink)
                            Group {
                                if pickedIndex == nil {
                                    Text("点一条，下次优先从它拆解")
                                } else {
                                    Text("✓ 已记住这个角度")
                                }
                            }
                                .sansBody(12)
                                .foregroundStyle(pickedIndex == nil ? DesignTokens.ash : theme.current.accentColor)
                        }
                        .padding(.top, DesignTokens.Spacing.sm)
                        .transition(.opacity)
                    }
                }

                Text("¥\(String(format: "%.0f", amountValue)) 想清楚了吗？")
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)
                    .padding(.top, DesignTokens.Spacing.md)

                VStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        recordShredSuccess()
                    } label: {
                        Text("✓ 粉碎成功，不要了")
                            .sansBody(16, weight: .semibold)
                            .foregroundStyle(DesignTokens.paper)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(theme.current.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("△ 还是要买")
                            .sansBody(15)
                            .foregroundStyle(DesignTokens.gold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(DesignTokens.gold.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    }
                }
                .padding(.top, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.xl)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    // MARK: - 逻辑

    /// FR-27 — 弹药卡可点选：选中的机制记为偏好，下次生成优先
    private func lineCard(index: Int, line: ShredAmmo.Drawn) -> some View {
        let isPicked = pickedIndex == index
        return Button {
            guard pickedIndex == nil else { return }
            pickedIndex = index
            ShredAmmo.recordPreference(line.mechanism)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Text(line.text)
                    .sansBody(15)
                    .foregroundStyle(DesignTokens.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isPicked {
                    Text("✓")
                        .sansBody(15, weight: .semibold)
                        .foregroundStyle(theme.current.accentColor)
                }
            }
            .padding(14)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(isPicked ? theme.current.accentColor : DesignTokens.stoneDim.opacity(0.5),
                                  lineWidth: isPicked ? 1.5 : 1)
            )
            .opacity(pickedIndex == nil || isPicked ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(pickedIndex != nil)
    }

    private func startShredding() {
        phase = .shredding
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeIn(duration: 0.45)) {
            cardOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                cardOpacity = 0
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            // 碎条依次落下
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(i)) {
                    withAnimation(.easeIn(duration: 0.5)) {
                        stripOffsets[i] = 90
                        stripOpacities[i] = 1
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                loadLines()
            }
        }
    }

    private func loadLines() {
        loading = true
        phase = .result
        pickedIndex = nil
        let name = itemName
        let amount = amountValue
        Task {
            // 优先端侧 AI；不可用/失败降级内置弹药库
            var result = await FoundationModelsService.shared.generateShredLines(itemName: name, amount: amount)
            if result.count < 3 {
                result = ShredAmmo.drawThree(itemName: name, amount: amount)
            }
            // FR-27 — 本轮展示的机制计入每周配额（同机制 ≤ 2 次）
            ShredAmmo.noteShown(result.map(\.mechanism))
            lines = result
            loading = false
        }
    }

    private func recordShredSuccess() {
        // 本地计数：本月粉碎次数 + 守住金额
        let monthKey = Self.currentMonthKey()
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: "shred.count.\(monthKey)") + 1, forKey: "shred.count.\(monthKey)")
        defaults.set(defaults.double(forKey: "shred.amount.\(monthKey)") + amountValue, forKey: "shred.amount.\(monthKey)")
        onShredded?()
        dismiss()
    }

    private static func currentMonthKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: .now)
    }
}
