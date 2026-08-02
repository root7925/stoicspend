import Foundation
import StoreKit

/// StoreKit 2 订阅服务
/// 产品 ID: stoicspend.monthly / stoicspend.yearly / stoicspend.intro
/// 详见 Agent.md 第 2.1 节
@Observable
final class StoreKitService {
    static let shared = StoreKitService()

    // 产品 ID
    enum ProductID {
        static let monthly = "stoicspend.monthly"
        static let yearly  = "stoicspend.yearly"
        static let intro   = "stoicspend.intro"
    }

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - 加载商品

    func loadProducts() async {
        do {
            products = try await Product.products(for: [
                ProductID.monthly,
                ProductID.yearly,
                ProductID.intro
            ])
        } catch {
            print("StoreKit 商品加载失败: \(error)")
        }
    }

    // MARK: - 购买

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return true

        case .userCancelled:
            return false

        case .pending:
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - 恢复购买

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - 订阅状态

    var isPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.updatePurchasedProducts()
                }
            }
        }
    }

    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.unverified
        }
    }

    enum StoreError: Error {
        case unverified
    }
}
