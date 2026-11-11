import Foundation
import WatchConnectivity
import SwiftData

/// FR-24 Watch 快记 — iPhone 端接收：
/// 收到 WatchCapture 后写入同一 SwiftData 库 + 记录常用组合 + 反向推送组合给表
@MainActor
final class WatchSyncService: NSObject, ObservableObject {
    static let shared = WatchSyncService()

    private var modelContext: ModelContext?
    private let session = WCSession.default

    /// App 启动时挂接（幂等）
    func activate(container: ModelContainer) {
        guard modelContext == nil else { return }
        modelContext = ModelContext(container)
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        pushRecentCombos()
    }

    /// 处理一笔手表快记：落库 + 记忆组合 + 通知首页刷新
    func handleIncoming(_ message: [String: Any]) {
        guard let capture = WatchCapture.decode(from: message),
              capture.isValid else { return }
        let expense = Expense(
            amount: capture.amount,
            date: capture.date,
            nature: capture.nature,
            category: capture.category ?? .food
        )
        modelContext?.insert(expense)
        try? modelContext?.save()

        if let nature = capture.nature {
            RecentComboStore.record(nature: nature, category: expense.category)
        }
        NotificationCenter.default.post(name: .quickAddSaved, object: nil)
        pushRecentCombos()
    }

    /// 把最近 3 组合推给手表（手表默认展示，同 FR-17）
    func pushRecentCombos() {
        guard WCSession.isSupported() else { return }
        let combos: [[String]] = RecentComboStore.load().map { [$0.natureRaw, $0.categoryRaw] }
        try? session.updateApplicationContext([WatchSyncKeys.recentCombosKey: combos])
    }
}

// MARK: - WCSessionDelegate（回调线程非主线程，跳回 MainActor）

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            Task { @MainActor in self.pushRecentCombos() }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.handleIncoming(message)
            replyHandler(["ok": true])
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor in self.handleIncoming(userInfo) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
