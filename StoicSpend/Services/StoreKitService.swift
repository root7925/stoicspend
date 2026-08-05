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

        static let all: [String] = [monthly, yearly, intro]
    }

    /// 购买结果
    enum PurchaseResult {
        case success
        case userCancelled
        case pending
        case failure(Error)
    }

    /// 当前订阅状态（仅订阅类商品）
    struct SubscriptionStatus {
        let productID: String
        let state: Product.SubscriptionInfo.RenewalState
        let expirationDate: Date?
        let renewalInfo: Product.SubscriptionInfo.RenewalInfo?

        var isActive: Bool {
            state == .subscribed || state == .inGracePeriod || state == .inBillingRetryPeriod
        }
    }

    private(set) var products: [Product] = []
    private(set) var subscriptionStatus: SubscriptionStatus?
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
            products = try await Product.products(for: ProductID.all)
        } catch {
            print("StoreKit 商品加载失败: \(error)")
        }
    }

    // MARK: - 购买

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseResult {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchasedProducts()
                await transaction.finish()
                return .success

            case .userCancelled:
                return .userCancelled

            case .pending:
                return .pending

            @unknown default:
                return .failure(StoreError.unknown)
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 恢复购买

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - 订阅状态

    var isPremium: Bool {
        subscriptionStatus?.isActive ?? false
    }

    /// 当前生效的订阅商品（用于 Paywall/Settings 展示）
    var activeProduct: Product? {
        guard let id = subscriptionStatus?.productID else { return nil }
        return products.first { $0.id == id }
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.updatePurchasedProducts()
                }
            }
        }
    }

    private func updatePurchasedProducts() async {
        // 遍历当前权益，找到第一个订阅类的活跃 transaction
        var active: SubscriptionStatus?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            // 拉对应 Product 的 subscription status（订阅类才有）
            if let product = products.first(where: { $0.id == transaction.productID }),
               let statuses = try? await product.subscription?.status,
               let status = statuses.first(where: { $0.state == .subscribed || $0.state == .inGracePeriod || $0.state == .inBillingRetryPeriod }) {
                let renewalInfo: Product.SubscriptionInfo.RenewalInfo?
                if case .verified(let info) = status.renewalInfo {
                    renewalInfo = info
                } else {
                    renewalInfo = nil
                }
                active = SubscriptionStatus(
                    productID: transaction.productID,
                    state: status.state,
                    expirationDate: transaction.expirationDate,
                    renewalInfo: renewalInfo
                )
                break
            }

            // 兜底：products 还没加载完，先用 transaction 拼装
            if active == nil {
                active = SubscriptionStatus(
                    productID: transaction.productID,
                    state: .subscribed,
                    expirationDate: transaction.expirationDate,
                    renewalInfo: nil
                )
            }
        }

        subscriptionStatus = active
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.unverified
        }
    }

    enum StoreError: Error, LocalizedError {
        case unverified
        case unknown

        var errorDescription: String? {
            switch self {
            case .unverified: return "Purchase verification failed."
            case .unknown: return "Unknown purchase error."
            }
        }
    }
}
