import SwiftUI
import SwiftData

@main
struct StoicSpendApp: App {
    let container: ModelContainer

    init() {
        container = ModelContainerSetup.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }
}

/// 根视图：根据 Onboarding 状态决定显示引导页还是主界面
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    private var hasCompletedOnboarding: Bool {
        settings.first?.hasCompletedOnboarding ?? false
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(appearanceScheme)
        .task { applyUITestHooksIfNeeded() }
        // FR-13 — Widget/控制中心深链：stoicspend://quickadd → 直达快记页
        .onOpenURL { url in
            guard url.scheme == "stoicspend" else { return }
            if url.host == "quickadd" {
                NotificationCenter.default.post(name: .widgetOpenQuickAdd, object: nil)
            }
            // FR-25 — 分享扩展识别完截图后深链回 App，弹出预填确认页
            if url.host == "capture" {
                NotificationCenter.default.post(name: .captureOpenQuickAdd, object: nil)
            }
        }
    }

    /// UI 测试启动钩子：UITEST_FRESH 清空数据 / UITEST_SKIP_ONBOARDING 跳过引导
    private func applyUITestHooksIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("UITEST") else { return }

        var settingsObj: AppSettings
        if let existing = settings.first {
            settingsObj = existing
        } else {
            let created = AppSettings()
            modelContext.insert(created)
            settingsObj = created
        }

        if args.contains("UITEST_FRESH") {
            try? modelContext.delete(model: Expense.self)
            try? modelContext.delete(model: BudgetModel.self)
            modelContext.insert(BudgetModel())
            if !args.contains("UITEST_SKIP_ONBOARDING") {
                settingsObj.hasCompletedOnboarding = false
            }
        }
        if args.contains("UITEST_SKIP_ONBOARDING") {
            settingsObj.hasCompletedOnboarding = true
        }
        try? modelContext.save()
    }

    @AppStorage("appearancePreference") private var appearance: String = "system"

    private var appearanceScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

/// 底部导航：4 Tab — Today / The Circle / Already Have / Settings
/// Resilience 从 The Circle 页面内入口触发（见设计文档底部导航节）
struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var theme = ThemeManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                .tag(0)

            LedgerView()
                .tabItem {
                    Label("帐本", systemImage: "book")
                }
                .tag(1)

            OccamView()
                .tabItem {
                    Label("奥卡姆", systemImage: "scissors")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(3)
        }
        .tint(DesignTokens.bronze)
        .environmentObject(theme)
        .id(theme.current)
        // 启动时同步 App 图标（若开启了图标跟随主题）
        .onAppear { AppIconService.syncIcon(for: theme.current) }
        // FR-13 — 深链跳首页
        .onReceive(NotificationCenter.default.publisher(for: .widgetOpenQuickAdd)) { _ in
            selectedTab = 0
        }
    }
}
