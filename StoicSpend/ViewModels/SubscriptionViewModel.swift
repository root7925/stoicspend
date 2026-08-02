import SwiftUI
import StoreKit

/// 订阅 ViewModel — 管理订阅状态和购买流程
@Observable
final class SubscriptionViewModel {
    var isPremium: Bool = false
    var isLoading: Bool = false
    var products: [Product] = []

    private let store = StoreKitService.shared

    init() {
        isPremium = store.isPremium
        products = store.products
    }

    /// 购买产品
    func purchase(_ product: Product) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let success = try await store.purchase(product)
            if success {
                isPremium = store.isPremium
            }
        } catch {
            print("购买失败: \(error)")
        }
    }

    /// 恢复购买
    func restore() async {
        isLoading = true
        defer { isLoading = false }

        await store.restorePurchases()
        isPremium = store.isPremium
    }

    /// 刷新状态
    func refresh() {
        isPremium = store.isPremium
        products = store.products
    }
}
