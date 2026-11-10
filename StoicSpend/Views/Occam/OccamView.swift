import SwiftUI

/// 理性消费 · 奥卡姆 — 「如无必要，勿增实体」（FR-12）
/// 奥卡姆之刃三问 + 时间剃刀冷静清单（72h）+ 已剃统计 + 粉碎机入口
struct OccamView: View {
    @EnvironmentObject private var theme: ThemeManager
    @State private var showShredder = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("理性消费 · 奥卡姆")
                    .serifTitle(22)
                    .foregroundStyle(DesignTokens.ink)
                Text("如无必要，勿增实体")
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)

                shavedStats
                OccamBladeSection()
                RazorListSection()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .background(DesignTokens.paper)
        .sheet(isPresented: $showShredder) {
            ShredderView()
        }
    }

    // MARK: - 已剃统计

    private var shavedStats: some View {
        let (count, amount) = Self.monthShredStats()
        return HStack(spacing: 0) {
            statItem(value: "\(count)", label: "本月已剃")
            Divider().frame(height: 30).overlay(DesignTokens.stoneDim)
            statItem(value: "¥\(String(format: "%.0f", amount))", label: "守住金额")
            Divider().frame(height: 30).overlay(DesignTokens.stoneDim)
            Button {
                showShredder = true
            } label: {
                VStack(spacing: 4) {
                    Text("⚙️")
                        .font(.system(size: 18))
                    Text("粉碎机")
                        .sansBody(11)
                        .foregroundStyle(DesignTokens.gold)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .sansBody(16, weight: .semibold)
                .foregroundStyle(DesignTokens.gold)
            Text(label)
                .sansBody(11)
                .foregroundStyle(DesignTokens.ash)
        }
        .frame(maxWidth: .infinity)
    }

    static func monthShredStats() -> (Int, Double) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let key = f.string(from: .now)
        let d = UserDefaults.standard
        return (d.integer(forKey: "shred.count.\(key)"), d.double(forKey: "shred.amount.\(key)"))
    }
}

// MARK: - 奥卡姆之刃（三问）

private struct OccamBladeSection: View {
    @EnvironmentObject private var theme: ThemeManager

    enum Stage { case idle, asking, verdict }

    @State private var stage: Stage = .idle
    @State private var itemName = ""
    @State private var answers: [String] = ["", "", ""]
    @State private var verdict: String?
    @State private var loading = false

    private let questions = [
        "它解决什么问题？没有它，问题还在吗？",
        "你已经拥有的东西里，有替代品吗？",
        "72 小时后，你还会想要它吗？",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("⚔️ 奥卡姆之刃")
                .sansBody(15, weight: .semibold)
                .foregroundStyle(DesignTokens.ink)

            switch stage {
            case .idle:
                Text("想买但拿不准？回答三个问题，用剃刀刮掉不必要的部分。")
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)

                TextField("想买什么？", text: $itemName)
                    .sansBody(14)
                    .padding(12)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                Button {
                    stage = .asking
                } label: {
                    Text("开始三问")
                        .sansBody(14, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.current.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .disabled(itemName.isEmpty)

            case .asking:
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("问 \(i + 1)：\(questions[i])")
                            .sansBody(13)
                            .foregroundStyle(DesignTokens.ash)
                        TextField("你的回答", text: $answers[i])
                            .sansBody(14)
                            .padding(10)
                            .background(DesignTokens.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }
                }

                Button {
                    judge()
                } label: {
                    Text(loading ? "剃刀落下…" : "落下剃刀")
                        .sansBody(14, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.current.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .disabled(loading || answers.contains { $0.isEmpty })

            case .verdict:
                Text(verdict ?? "")
                    .sansBody(15)
                    .foregroundStyle(DesignTokens.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.current.accentDimColor)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                Button {
                    stage = .idle
                    itemName = ""
                    answers = ["", "", ""]
                    verdict = nil
                } label: {
                    Text("再剃一件")
                        .sansBody(14, weight: .medium)
                        .foregroundStyle(theme.current.accentColor)
                }
            }
        }
        .padding(16)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    /// 剃刀结论 — 优先端侧 AI 总结三答，不可用降级固定判断
    private func judge() {
        loading = true
        let name = itemName
        let a1 = answers[0], a2 = answers[1], a3 = answers[2]
        Task { @MainActor in
            let line = await Self.aiVerdict(item: name, a1: a1, a2: a2, a3: a3)
            verdict = line
            loading = false
            stage = .verdict
        }
    }

    @MainActor
    private static func aiVerdict(item: String, a1: String, a2: String, a3: String) async -> String {
        if let ai = await FoundationModelsService.shared.generateOccamVerdict(item: item, answers: [a1, a2, a3]) {
            return ai
        }
        // 降级：基于回答关键词的规则判断
        let all = (a1 + a2 + a3).lowercased()
        if a3.contains("会") || a3.contains("是") || all.contains("没有") || all.contains("没") {
            return "三答之后仍不清晰。按剃刀原则：先放下，72 小时后再看它还在不在。"
        }
        return "问题真实、无替代、且你确定三天后还想要——那就不再是冲动，记下它。"
    }
}

// MARK: - 时间剃刀冷静清单（72h 倒计时）

private struct RazorListSection: View {
    @EnvironmentObject private var theme: ThemeManager

    // RazorItem 存储与 Live Activity 联动在 Shared/RazorKit.swift（FR-20）
    @State private var items: [RazorItem] = []
    @State private var newName = ""
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    Text("⏳ 时间剃刀 · 冷静清单")
                        .sansBody(15, weight: .semibold)
                        .foregroundStyle(DesignTokens.ink)
                    Spacer()
                    Text(expanded ? "▾" : "▸")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
            }

            if expanded {
                Text("先放 72 小时。到期还想要，再让它进来。")
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.ash)

                HStack {
                    TextField("想先放一放的东西", text: $newName)
                        .sansBody(14)
                        .padding(10)
                        .background(DesignTokens.paper)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    Button {
                        guard !newName.isEmpty else { return }
                        Haptics.saveSuccess()
                        items = RazorStore.add(name: newName)
                        newName = ""
                    } label: {
                        Text("放入")
                            .sansBody(13, weight: .semibold)
                            .foregroundStyle(theme.current.accentColor)
                    }
                }

                ForEach(items) { item in
                    HStack {
                        Text(item.name)
                            .sansBody(14)
                            .foregroundStyle(DesignTokens.ink)
                        Spacer()
                        Text(item.expired ? "到期了 · 还想要吗？" : Self.remaining(item.createdAt))
                            .sansBody(12)
                            .foregroundStyle(item.expired ? DesignTokens.gold : DesignTokens.ash)
                        Button {
                            Haptics.selectionChanged()
                            items = RazorStore.remove(id: item.id)
                        } label: {
                            Text("✕")
                                .sansBody(12)
                                .foregroundStyle(DesignTokens.ash)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(DesignTokens.paper)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }

                if items.isEmpty {
                    Text("清单是空的")
                        .sansBody(12)
                        .foregroundStyle(DesignTokens.ash)
                }
            }
        }
        .padding(16)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .onAppear { load() }
    }

    private static func remaining(_ createdAt: Date) -> String {
        let left = max(0, 72 * 3600 - Date.now.timeIntervalSince(createdAt))
        let hours = Int(left / 3600)
        return "剩 \(hours) 小时"
    }

    private func load() {
        items = RazorStore.load()
    }
}
