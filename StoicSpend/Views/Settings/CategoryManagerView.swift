import SwiftUI
import SwiftData

/// FR-29 自定义分类管理 — 列表（emoji+名+笔数）/ 添加（emoji 池 + ≤20 字名）/ 删除（账目归入「其他」）
/// 内置 9 类锁定不可动；上限 6 个
struct CategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]

    @State private var categories: [CustomCategory] = []
    @State private var newEmoji: String = "🐱"
    @State private var newName: String = ""
    @State private var pendingDelete: CustomCategory?
    @EnvironmentObject private var theme: ThemeManager

    private var canAdd: Bool {
        categories.count < CategoryStore.maxCount
            && !newName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                headerCard
                if !categories.isEmpty { listCard }
                addCard
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)
        }
        .background(DesignTokens.paper)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardToolbar()
        .navigationTitle(Text("自定义分类"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { categories = CategoryStore.load() }
        .confirmationDialog(
            Text("删除这个分类？"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { deleteConfirmed() }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("删除后相关账目将归入「其他」")
        }
    }

    // MARK: - 区块

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("按你的生活定义分类")
                .serifTitle(15)
                .foregroundStyle(DesignTokens.ink)
            Text("最多 \(CategoryStore.maxCount) 个，会出现在快记与记账的分类选择里。内置分类保持不变。")
                .sansBody(12)
                .foregroundStyle(DesignTokens.ash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, cat in
                if index > 0 { Divider().overlay(DesignTokens.ash.opacity(0.18)) }
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(verbatim: cat.emoji)
                        .font(.system(size: 22))
                        .frame(width: 34)
                    Text(verbatim: cat.name)
                        .sansBody(14, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Spacer()
                    Text("(\(count(for: cat)))")
                        .sansBody(12)
                        .foregroundStyle(DesignTokens.ash)
                    Button {
                        pendingDelete = cat
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(DesignTokens.ash)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 11)
            }
        }
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if canAdd || categories.count < CategoryStore.maxCount {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(CategoryStore.emojiPool, id: \.self) { e in
                            Button {
                                newEmoji = e
                            } label: {
                                Text(verbatim: e)
                                    .font(.system(size: 20))
                                    .frame(width: 40, height: 40)
                                    .background(newEmoji == e ? themeAccent.opacity(0.16) : DesignTokens.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(newEmoji == e ? themeAccent : Color.clear, lineWidth: 1.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    TextField("给分类起个名字", text: $newName)
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("category.name.field")
                        .onChange(of: newName) { _, newValue in
                            newName = String(newValue.prefix(20))
                        }

                    Button {
                        categories = CategoryStore.add(name: newName, emoji: newEmoji)
                        newName = ""
                        hideKeyboard()
                    } label: {
                        Text("添加")
                            .sansBody(14, weight: .semibold)
                            .foregroundStyle(canAdd ? DesignTokens.paper : DesignTokens.ash)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(canAdd ? themeAccent : DesignTokens.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!canAdd)
                    .accessibilityIdentifier("category.add")
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(themeAccent)
                    Text("分类已满（\(CategoryStore.maxCount) 个）")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - 逻辑

    private var themeAccent: Color {
        (theme.current.accentColor)
    }

    private func count(for cat: CustomCategory) -> Int {
        expenses.filter { $0.categoryGroupKey == CategoryStore.storageKey(for: cat.id) }.count
    }

    private func deleteConfirmed() {
        guard let cat = pendingDelete else { return }
        pendingDelete = nil
        // 关联账目归入「其他」：清掉 override，回落到内置 category（默认 food？不——归「其他」）
        for e in expenses where e.categoryGroupKey == CategoryStore.storageKey(for: cat.id) {
            e.category = .other
            e.customCategoryID = nil
        }
        try? modelContext.save()
        categories = CategoryStore.remove(id: cat.id)
    }
}
