import SwiftUI

/// FR-32 分类纠错规则管理 — 查看/删除（可检查，不做黑盒）
struct CategoryRulesView: View {
    @State private var rules: [(rule: CategoryRule, display: String?)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Text("导入或快记时，备注/商家命中关键词就自动归入你指定的分类。")
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)

                if rules.isEmpty {
                    Text("还没有规则。在导入预览里多选账目改分类后，这里会出现你教过的规则。")
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ash)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .background(DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rules.enumerated()), id: \.element.rule.id) { index, item in
                            if index > 0 { Divider().overlay(DesignTokens.ash.opacity(0.18)) }
                            ruleRow(item)
                        }
                    }
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                    Button {
                        Haptics.selectionChanged()
                        CategoryRuleStore.clear()
                        reload()
                    } label: {
                        Text("清空全部规则")
                            .sansBody(14, weight: .medium)
                            .foregroundStyle(DesignTokens.gold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DesignTokens.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)
        }
        .background(DesignTokens.paper)
        .navigationTitle(Text("分类规则"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
    }

    private func ruleRow(_ item: (rule: CategoryRule, display: String?)) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.rule.keyword)
                    .sansBody(14, weight: .medium)
                    .foregroundStyle(DesignTokens.ink)
                Text(item.display ?? NSLocalizedString("已失效（分类已删除）", comment: ""))
                    .sansBody(12)
                    .foregroundStyle(item.display == nil ? DesignTokens.gold : DesignTokens.ash)
            }
            Spacer()
            Button {
                Haptics.selectionChanged()
                rules = CategoryRuleStore.remove(id: item.rule.id).map {
                    ($0, CategoryRuleStore.displayName(for: $0))
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(DesignTokens.ash)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 11)
    }

    private func reload() {
        rules = CategoryRuleStore.load().map {
            ($0, CategoryRuleStore.displayName(for: $0))
        }
    }
}
