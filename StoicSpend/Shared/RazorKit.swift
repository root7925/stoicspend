import ActivityKit
import Foundation

/// FR-20 冷静清单倒计时 — App 与 Widget 扩展共享
/// 剩余时间 = createdAt + 72h - now，UI 用 Text(timerInterval:) 自动走秒
struct RazorActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var createdAt: Date
    }

    var itemName: String
}

// MARK: - 时间剃刀清单存储（App 内使用，UserDefaults JSON）

struct RazorItem: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date

    var endDate: Date { createdAt.addingTimeInterval(72 * 3600) }
    var expired: Bool { Date.now >= endDate }
}

@MainActor
enum RazorStore {
    static let storageKey = "occam.razorList"
    static let activityIDKey = "razor.activity.id"

    static func load() -> [RazorItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([RazorItem].self, from: data) else {
            return []
        }
        return items
    }

    /// 放入清单 → 保存 + 启动 Live Activity（锁屏/灵动岛倒计时）
    static func add(name: String) -> [RazorItem] {
        var items = load()
        let item = RazorItem(id: UUID(), name: name, createdAt: .now)
        items.insert(item, at: 0)
        save(items)
        RazorActivityService.startActivity(for: item)
        return items
    }

    /// 移出清单（剃掉 / 还是想要）→ 保存 + 结束 Live Activity
    static func remove(id: UUID) -> [RazorItem] {
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
        RazorActivityService.endActivity()
        return items
    }

    static func save(_ items: [RazorItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Live Activity 控制（iOS 16.1+ ActivityKit，部署目标 18+ 无需门控）

@MainActor
enum RazorActivityService {
    static func startActivity(for item: RazorItem) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // 清理同项目旧活动，避免重复
        endActivity()

        let attributes = RazorActivityAttributes(itemName: item.name)
        let state = RazorActivityAttributes.ContentState(createdAt: item.createdAt)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: item.endDate)
            )
            UserDefaults.standard.set(activity.id, forKey: RazorStore.activityIDKey)
        } catch {
            // 系统限制（如超过 Live Activity 上限）时静默降级：清单内仍有倒计时
        }
    }

    static func endActivity() {
        let savedID = UserDefaults.standard.string(forKey: RazorStore.activityIDKey)
        Task {
            for activity in Activity<RazorActivityAttributes>.activities where activity.id == savedID {
                await activity.end(
                    ActivityContent(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            UserDefaults.standard.removeObject(forKey: RazorStore.activityIDKey)
        }
    }
}
