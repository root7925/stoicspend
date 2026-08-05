import SwiftUI
import StoreKit

/// 订阅 ViewModel — 管理订阅状态和购买流程
@Observable
final class SubscriptionViewModel {
    var isPremium: Bool = false
    var isLoading: Bool = false
    var products: [Product] = []
    var purchaseError: String?
    var lastPurchaseResult: StoreKitService.PurchaseResult?
    var subscriptionStatus: StoreKitService.SubscriptionStatus?

    private let store = StoreKitService.shared

    init() {
        refresh()
    }

    /// 购买产品
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        let result = await store.purchase(product)
        lastPurchaseResult = result
        refresh()

        switch result {
        case .success:
            return true
        case .failure(let error):
            purchaseError = error.localizedDescription
            return false
        case .userCancelled, .pending:
            return false
        }
    }

    /// 恢复购买
    func restore() async {
        isLoading = true
        defer { isLoading = false }

        await store.restorePurchases()
        refresh()
    }

    /// 刷新状态
    func refresh() {
        isPremium = store.isPremium
        products = store.products
        subscriptionStatus = store.subscriptionStatus
    }

    /// 当前订阅到期日期（用于 Settings 展示）
    var expirationDate: Date? {
        subscriptionStatus?.expirationDate
    }

    /// 已订阅的本地化标题
    var activeProductDisplayName: String? {
        store.activeProduct?.displayName
    }
}
