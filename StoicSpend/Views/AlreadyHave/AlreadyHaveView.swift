import SwiftUI
import SwiftData

/// 页面 7 — Already Have 已拥有清单
/// 用户主动添加的知足清单，记账时如果三问选择了"冲动驱动"可弹出做对比提醒
struct AlreadyHaveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlreadyHaveItem.createdAt, order: .reverse)
    private var items: [AlreadyHaveItem]

    @State private var showAddSheet = false
    @State private var newItemTitle = ""
    @State private var newItemNote = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: DesignTokens.Spacing.md) {
                        ForEach(items) { item in
                            itemCard(item)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.md)
                }
            }
            .background(DesignTokens.paper)
            .navigationTitle("Already Have")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(DesignTokens.bronze)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                addSheet
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()
                .frame(height: DesignTokens.Spacing.xxl)

            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.stoneDim)

            Text("What you already have is enough.")
                .serifTitle(20, weight: .regular)
                .foregroundStyle(DesignTokens.ash)

            Text("Add things you're grateful to already own.")
                .sansBody(14)
                .foregroundStyle(DesignTokens.ash)

            Button {
                showAddSheet = true
            } label: {
                Label("Add Item", systemImage: "plus")
                    .sansBody(15, weight: .medium)
                    .foregroundStyle(DesignTokens.paper)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .background(DesignTokens.bronze)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 清单项卡片

    private func itemCard(_ item: AlreadyHaveItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.verdigris)
                Text(item.title)
                    .serifTitle(18, weight: .semibold)
                    .foregroundStyle(DesignTokens.ink)
                Spacer()
            }

            if !item.note.isEmpty {
                Text(item.note)
                    .sansBody(14)
                    .foregroundStyle(DesignTokens.ash)
            }

            Text(item.createdAt, style: .date)
                .monoData(12)
                .foregroundStyle(DesignTokens.ash)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .contextMenu {
            Button(role: .destructive) {
                deleteItem(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - 添加 Sheet

    private var addSheet: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.lg) {
                TextField("What do you already have?", text: $newItemTitle)
                    .sansBody(16)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                TextField("A note (optional)", text: $newItemNote, axis: .vertical)
                    .sansBody(15)
                    .lineLimit(3...6)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                Spacer()

                Button {
                    addItem()
                } label: {
                    Text("Add to List")
                        .sansBody(16, weight: .semibold)
                        .foregroundStyle(DesignTokens.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(newItemTitle.isEmpty ? DesignTokens.stoneDim : DesignTokens.bronze)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .disabled(newItemTitle.isEmpty)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)
            .background(DesignTokens.paper)
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newItemTitle = ""
                        newItemNote = ""
                        showAddSheet = false
                    }
                }
            }
        }
    }

    // MARK: - 逻辑

    private func addItem() {
        let item = AlreadyHaveItem(title: newItemTitle, note: newItemNote)
        modelContext.insert(item)
        try? modelContext.save()
        newItemTitle = ""
        newItemNote = ""
        showAddSheet = false
    }

    private func deleteItem(_ item: AlreadyHaveItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}
