import WidgetKit
import SwiftUI
import AppIntents

// MARK: - FR-13 全局快捷入口（控制中心 / 锁屏 / 操作按钮 → 直达快记）

/// 点击即打开 App 快记页（stoicspend://quickadd），自动就绪金额键盘
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if let url = URL(string: "stoicspend://quickadd") {
                NotificationCenter.default.post(name: .widgetOpenQuickAdd, object: url)
            }
        }
        return .result()
    }
}

extension Notification.Name {
    static let widgetOpenQuickAdd = Notification.Name("widget.openQuickAdd")
}

struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zhenglin.stoicspend.quickadd.control") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("记一笔", systemImage: "plus.circle")
            }
        }
        .displayName("记一笔")
        .description("一键直达快记页")
    }
}

// MARK: - 锁屏小组件（圆环 + 行内）

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry { QuickAddEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        completion(Timeline(entries: [QuickAddEntry(date: .now)], policy: .never))
    }
}

struct QuickAddLockWidgetView: View {
    var entry: QuickAddEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("记一笔", systemImage: "plus.circle")
                .widgetURL(URL(string: "stoicspend://quickadd"))
        default:
            VStack(spacing: 2) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24, weight: .light))
                Text("记一笔")
                    .font(.system(size: 9))
            }
            .widgetURL(URL(string: "stoicspend://quickadd"))
        }
    }
}

struct QuickAddLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.zhenglin.stoicspend.quickadd.lock", provider: QuickAddProvider()) { entry in
            QuickAddLockWidgetView(entry: entry)
        }
        .configurationDisplayName("记一笔")
        .description("一键直达快记页")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

@main
struct StoicSpendWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickAddControl()
        QuickAddLockWidget()
        RatioWidget()
        RatioLockWidget()
        RazorLiveActivity()
    }
}
