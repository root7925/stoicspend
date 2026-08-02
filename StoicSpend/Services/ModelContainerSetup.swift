import SwiftUI
import SwiftData

/// SwiftData 容器配置 — 单例
/// 注册所有 @Model 类型
enum ModelContainerSetup {
    static let shared = ModelContainerSetup.makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Expense.self,
            WeeklyReview.self,
            AlreadyHaveItem.self,
            DailyQuote.self,
            AppSettings.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // 明确不使用 CloudKit
        )

        // 首次尝试：直接加载现有 store
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            seedIfNeeded(in: container)
            return container
        }

        // 加载失败（常见于 schema 变更未迁移，如 Phase 4/5 新增字段后旧 store 不兼容）
        // 删除旧 store 文件后重建，避免 fatalError 阻塞启动
        let storeURL = config.url
        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            let path = storeURL.path + suffix
            try? FileManager.default.removeItem(atPath: path)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            seedIfNeeded(in: container)
            return container
        } catch {
            fatalError("ModelContainer 创建失败: \(error)")
        }
    }

    /// 首次启动时初始化 AppSettings 单例
    private static func seedIfNeeded(in container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        let existing = (try? context.fetch(descriptor)) ?? []

        if existing.isEmpty {
            context.insert(AppSettings())
            try? context.save()
        }
    }
}
