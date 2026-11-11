import SwiftUI
import WatchConnectivity
import WatchKit

/// FR-24 Apple Watch 快记 — 表冠滚动金额、单击常用分类、保存震动确认
/// 经 WatchConnectivity 同步到 iPhone 写入同一 SwiftData 库，Watch 端不独立存储
@main
struct StoicSpendWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchQuickAddView()
                .environmentObject(WatchSender.shared)
        }
    }
}

// MARK: - 发送器（Watch 端 WCSession）

final class WatchSender: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSender()

    /// iPhone 推送的最近 3 组合（[[natureRaw, categoryRaw]]）
    @Published var recentPairs: [[String]] = []

    private let session = WCSession.default

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        reloadCombos(from: session.receivedApplicationContext)
    }

    /// 发送一笔快记：可达时 sendMessage（带回复），否则 transferUserInfo 保证送达
    func send(_ capture: WatchCapture, completion: @escaping (Bool) -> Void) {
        guard capture.isValid, let data = capture.encodedData else {
            completion(false)
            return
        }
        if session.isReachable {
            session.sendMessage(
                [WatchSyncKeys.messageKey: data],
                replyHandler: { _ in completion(true) },
                errorHandler: { _ in
                    self.session.transferUserInfo([WatchSyncKeys.messageKey: data])
                    completion(true)
                }
            )
        } else {
            session.transferUserInfo([WatchSyncKeys.messageKey: data])
            completion(true)
        }
    }

    private func reloadCombos(from context: [String: Any]) {
        DispatchQueue.main.async {
            self.recentPairs = context[WatchSyncKeys.recentCombosKey] as? [[String]] ?? []
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        reloadCombos(from: session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        reloadCombos(from: applicationContext)
    }
}

// MARK: - 快记页

struct WatchQuickAddView: View {
    @EnvironmentObject private var sender: WatchSender

    @State private var amountIndex = 0 // 步长 ¥5，表冠滚动，上限 ¥10000
    @State private var nature: ExpenseNature = .chosen
    @State private var category: ExpenseCategory = .food
    @State private var showSynced = false

    private var amount: Double { Double(amountIndex) * 5 }

    /// 最近组合解码为可直接套用的 (性质, 分类)
    private var combos: [(nature: ExpenseNature, category: ExpenseCategory)] {
        sender.recentPairs.compactMap { pair in
            guard pair.count == 2,
                  let n = ExpenseNature(rawValue: pair[0]),
                  let c = ExpenseCategory(rawValue: pair[1]) else { return nil }
            return (n, c)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                // 金额：表冠滚动（步长 5）
                Text(verbatim: "¥\(Int(amount))")
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .foregroundStyle(amount > 0 ? Color.green : Color.secondary)
                Picker("amount", selection: $amountIndex) {
                    ForEach(0...2000, id: \.self) { i in
                        Text(verbatim: "\(i * 5)")
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 52)

                // 性质三选
                HStack(spacing: 4) {
                    ForEach([ExpenseNature.chosen, .necessity, .impulse], id: \.self) { n in
                        Button { nature = n } label: {
                            Text(n.localizedName)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(nature == n ? Color.green.opacity(0.35) : Color.white.opacity(0.08))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 最近 3 组合（iPhone 推送，同 FR-17）
                if !combos.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(combos, id: \.category) { combo in
                            Button {
                                nature = combo.nature
                                category = combo.category
                            } label: {
                                Text(verbatim: combo.category.emoji)
                                    .font(.system(size: 15))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 九分类宫格（emoji 即按钮）
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(ExpenseCategory.allCases) { c in
                        Button { category = c } label: {
                            Text(verbatim: c.emoji)
                                .font(.system(size: 17))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(category == c ? Color.green.opacity(0.35) : Color.white.opacity(0.08))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 保存
                Button {
                    send()
                } label: {
                    Text("保存")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .disabled(amount <= 0)
                .padding(.top, 2)
            }
            .padding(.horizontal, 2)
        }
        .overlay {
            if showSynced {
                Text("已同步")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.4), in: Capsule())
            }
        }
        .navigationTitle("Stoic Spend")
    }

    private func send() {
        let capture = WatchCapture(
            amount: amount,
            natureRaw: nature.rawValue,
            categoryRaw: category.rawValue,
            date: .now
        )
        sender.send(capture) { ok in
            DispatchQueue.main.async {
                guard ok else { return }
                WKInterfaceDevice.current().play(.success)
                showSynced = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showSynced = false
                    amountIndex = 0
                }
            }
        }
    }
}
