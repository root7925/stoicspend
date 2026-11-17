import SwiftUI
import SwiftData
import os.log

/// SwiftData 容器配置 — 单例
///
/// 工程化整改（2026-08-07）：
/// - 引入 VersionedSchema，为 schema 变更提供版本参照
/// - 移除「加载失败即销毁 store + fatalError」逻辑，避免升级时静默清空用户数据
/// - 加载失败时降级为内存容器并记录日志，保证 App 可启动
///
/// P0 修复（2026-11-17，V1.4）：
/// - 不再使用显式 SchemaMigrationPlan：加字段（FR-29/31）后 V2 版本哈希变化，
///   staged migration 报「unknown model version」拒载 → 内存降级 → 真机升级数据不可见
/// - 改用 SwiftData 自动轻量迁移（新增可选/带默认值字段可安全自动迁移）
enum AppSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Expense.self,
            WeeklyReview.self,
            AlreadyHaveItem.self,
            DailyQuote.self,
            AppSettings.self
        ]
    }
}

/// v2 — P0-2 新增 BudgetModel（月度预算，免费功能）
enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        AppSchema.models + [BudgetModel.self]
    }
}

enum ModelContainerSetup {
    private static let logger = Logger(subsystem: "com.zhenglin.stoicspend", category: "ModelContainer")
    static let shared: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        // P1-5：可选 iCloud 同步（默认关）。开关存于 UserDefaults，下次启动生效
        let cloudSync = UserDefaults.standard.bool(forKey: "cloudSyncEnabled")
        let config = ModelConfiguration(
            schema: Schema(versionedSchema: AppSchemaV2.self),
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudSync ? .automatic : .none
        )

        // 不传 migrationPlan：SwiftData 对「加可选字段/带默认值字段」自动轻量迁移
        if let container = try? ModelContainer(
            for: Schema(versionedSchema: AppSchemaV2.self),
            configurations: [config]
        ) {
            seedIfNeeded(in: container)
            return container
        }

        // 加载失败：不再销毁用户数据，降级为内存容器避免 fatalError 阻塞启动
        logger.error("ModelContainer 加载失败，降级为内存容器（用户数据本次不持久化，请排查 schema/迁移）")
        let memoryConfig = ModelConfiguration(
            schema: Schema(versionedSchema: AppSchemaV2.self),
            isStoredInMemoryOnly: true
        )
        let container = try! ModelContainer(
            for: Schema(versionedSchema: AppSchemaV2.self),
            configurations: [memoryConfig]
        )
        seedIfNeeded(in: container)
        return container
    }

    /// 首次启动时初始化 AppSettings / BudgetModel 单例（保证唯一，避免重复行）
    private static func seedIfNeeded(in container: ModelContainer) {
        let context = ModelContext(container)
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let settingsExisting = (try? context.fetch(settingsDescriptor)) ?? []
        if settingsExisting.isEmpty {
            context.insert(AppSettings())
        }

        // 月度预算：免费功能，首次启动即创建默认（未设置）预算条目
        let budgetDescriptor = FetchDescriptor<BudgetModel>()
        let budgetExisting = (try? context.fetch(budgetDescriptor)) ?? []
        if budgetExisting.isEmpty {
            context.insert(BudgetModel())
        }

        try? context.save()
    }
}
