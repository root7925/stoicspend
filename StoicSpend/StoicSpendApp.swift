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

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(0)

            CircleDashboardView()
                .tabItem {
                    Label("The Circle", systemImage: "circle.dashed")
                }
                .tag(1)

            AlreadyHaveView()
                .tabItem {
                    Label("Have", systemImage: "checkmark")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .tint(DesignTokens.bronze)
    }
}
