import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - FR-21 小组件家族（控制比，无红色）

/// 快照 Provider — 时间线只在启动快照变化时刷新（.never），App 保存后由 App 侧触发重载
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.load())], policy: .never))
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// 小号 = 控制比环
struct RatioSmallWidgetView: View {
    var entry: SnapshotEntry

    var body: some View {
        VStack(spacing: 6) {
            ratioRing
            Text("可控")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    @ViewBuilder
    private var ratioRing: some View {
        if let ratio = entry.snapshot?.ratio {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(Color(red: 0.42, green: 0.56, blue: 0.45), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 64, height: 64)
        } else {
            Text("记满 3 笔\n可见")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

// 中号 = 环 + 今日/本周 + 最近 3 笔
struct RatioMediumWidgetView: View {
    var entry: SnapshotEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                if let s = entry.snapshot {
                    Text("\(s.currencySymbol)\(Self.trim(s.todayTotal))")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                    Text("今日")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: 15))
                }
            }
            .frame(width: 56)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if let s = entry.snapshot, !s.recent.isEmpty {
                    ForEach(s.recent, id: \.self) { r in
                        HStack(spacing: 4) {
                            Text(r.emoji)
                                .font(.system(size: 12))
                            Text(r.note.isEmpty ? "消费" : r.note)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer()
                            Text("\(s.currencySymbol)\(Self.trim(r.amount))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("本周没有记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    static func trim(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// 锁屏 = 单色迷你环
struct RatioLockWidgetView: View {
    var entry: SnapshotEntry

    var body: some View {
        if let ratio = entry.snapshot?.ratio {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((ratio * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold))
                    .minimumScaleFactor(0.6)
            }
        } else {
            Text("·")
                .font(.system(size: 12))
        }
    }
}

struct RatioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.zhenglin.stoicspend.ratio", provider: SnapshotProvider()) { entry in
            RatioMediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("控制比")
        .description("本月可控支出的占比与最近记录")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RatioLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.zhenglin.stoicspend.ratio.lock", provider: SnapshotProvider()) { entry in
            RatioLockWidgetView(entry: entry)
        }
        .configurationDisplayName("控制比（锁屏）")
        .description("锁屏上的迷你控制环")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - FR-20 冷静清单 Live Activity（锁屏 + 灵动岛）

struct RazorLiveActivityView: View {
    var context: ActivityViewContext<RazorActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            Text("⏳")
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.itemName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(timerInterval: context.state.createdAt...context.state.createdAt.addingTimeInterval(72 * 3600), countsDown: true)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("72 小时冷静")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .containerBackground(for: .widget) { Color(red: 0.09, green: 0.09, blue: 0.07) }
    }
}

struct RazorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RazorActivityAttributes.self) { context in
            RazorLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("⏳").font(.system(size: 20))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.itemName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(timerInterval: context.state.createdAt...context.state.createdAt.addingTimeInterval(72 * 3600), countsDown: true)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("72h")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("⏳").font(.system(size: 12))
            } compactTrailing: {
                Text(timerInterval: context.state.createdAt...context.state.createdAt.addingTimeInterval(72 * 3600), countsDown: true)
                    .font(.system(size: 11).monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Text("⏳").font(.system(size: 12))
            }
        }
    }
}
